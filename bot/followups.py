"""Фоновая отправка дожимающих сообщений тем, кто не купил."""
import asyncio
import logging
import time
from datetime import timedelta

from aiogram import Bot
from aiogram.exceptions import TelegramForbiddenError, TelegramRetryAfter

from . import content, keyboards
from .config import Config
from .db import Database

log = logging.getLogger(__name__)

CHECK_INTERVAL = 20  # секунд


def scaled(delay: timedelta, config: Config) -> float:
    return delay.total_seconds() * config.followup_delay_scale


async def start_checkout_chain(db: Database, config: Config, user: dict) -> None:
    """Пользователь открыл оплату: переключаем его на цепочку «не оплатил»."""
    if user["paid"] or user["chain"] == "checkout":
        return
    first_delay = content.FOLLOWUPS["checkout"][0][0]
    await db.update_user(
        user["user_id"], chain="checkout", followup_step=0,
        next_followup_at=int(time.time() + scaled(first_delay, config)),
    )


def render(user: dict, key: str, config: Config) -> tuple[str, object]:
    if key == "browse_1" and not user["subscribed"] and config.subscribe_channel:
        key = "browse_1_unsubscribed"
    manager = f": @{config.manager_username}" if config.manager_username else ""
    text = content.FOLLOWUP_TEXTS[key].format(price=config.price, manager=manager)
    return text, keyboards.followup(key, config)


async def process_due(bot: Bot, db: Database, config: Config) -> int:
    now = int(time.time())
    sent = 0
    for user in await db.due_followups(now):
        chain = content.FOLLOWUPS.get(user["chain"] or "")
        step = user["followup_step"]
        if not chain or step >= len(chain):
            await db.update_user(user["user_id"], next_followup_at=None)
            continue

        text, markup = render(user, chain[step][1], config)
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

        next_at = now + int(scaled(chain[step + 1][0], config)) if step + 1 < len(chain) else None
        await db.update_user(user["user_id"], followup_step=step + 1, next_followup_at=next_at)
        await asyncio.sleep(0.05)
    return sent


async def followup_worker(bot: Bot, db: Database, config: Config) -> None:
    while True:
        try:
            await process_due(bot, db, config)
        except Exception:
            log.exception("Сбой в цикле дожимающих сообщений")
        await asyncio.sleep(CHECK_INTERVAL)
