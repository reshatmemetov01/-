"""Фоновая отправка дожимающих сообщений тем, кто не оставил заявку."""
import asyncio
import logging
import time
from datetime import timedelta

from aiogram import Bot
from aiogram.exceptions import TelegramForbiddenError, TelegramRetryAfter

from . import content, keyboards
from .config import Config
from .db import Database, stage_rank

log = logging.getLogger(__name__)

CHECK_INTERVAL = 20  # секунд


def scaled_delay(delay: timedelta, config: Config) -> float:
    return delay.total_seconds() * config.followup_delay_scale


def render(key: str, user: dict, config: Config) -> tuple[str, object]:
    quiz_done = stage_rank(user["stage"]) >= stage_rank("quiz_done")
    if key == "nudge" and not quiz_done:
        text = content.FOLLOWUP_TEXTS["nudge_no_quiz"]
    else:
        text = content.FOLLOWUP_TEXTS[key].format(percent=content.DISCOUNT_PERCENT)
    return text, keyboards.followup(key, quiz_done, config.manager_username)


async def process_due(bot: Bot, db: Database, config: Config) -> int:
    now = int(time.time())
    sent = 0
    for user in await db.due_followups(now):
        step = user["followup_step"]
        if step >= len(content.FOLLOWUPS):
            await db.update_user(user["user_id"], next_followup_at=None)
            continue

        followup = content.FOLLOWUPS[step]
        text, markup = render(followup.key, user, config)
        updates: dict = {"followup_step": step + 1}
        try:
            await bot.send_message(user["user_id"], text, reply_markup=markup)
            sent += 1
        except TelegramForbiddenError:
            await db.update_user(user["user_id"], blocked=1, next_followup_at=None)
            continue
        except TelegramRetryAfter as e:
            await asyncio.sleep(e.retry_after)
            continue
        except Exception:
            log.exception("Ошибка отправки дожима пользователю %s", user["user_id"])
            continue

        if followup.key == "discount":
            updates["discount_until"] = now + int(scaled_delay(content.DISCOUNT_DURATION, config))
        if step + 1 < len(content.FOLLOWUPS):
            updates["next_followup_at"] = now + int(scaled_delay(content.FOLLOWUPS[step + 1].delay, config))
        else:
            updates["next_followup_at"] = None
        await db.update_user(user["user_id"], **updates)
        await asyncio.sleep(0.05)
    return sent


async def followup_worker(bot: Bot, db: Database, config: Config) -> None:
    while True:
        try:
            await process_due(bot, db, config)
        except Exception:
            log.exception("Сбой в цикле дожимающих сообщений")
        await asyncio.sleep(CHECK_INTERVAL)
