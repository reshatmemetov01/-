import logging
from html import escape
from typing import Any

from aiogram import Bot

from . import content
from .config import Config

log = logging.getLogger(__name__)


def user_card(user: dict[str, Any]) -> str:
    name = escape(user.get("lead_name") or user.get("full_name") or "—")
    username = f"@{escape(user['username'])}" if user.get("username") else "—"
    tariff = content.TARIFFS_BY_ID.get(user.get("tariff") or "")
    score = user.get("quiz_score")
    return (
        f'👤 <a href="tg://user?id={user["user_id"]}">{name}</a> ({username})\n'
        f"📱 {escape(user.get('phone') or '—')}\n"
        f"🎯 Цель: {content.SEGMENTS.get(user.get('segment') or '', '—')}\n"
        f"📊 Тест: {f'{score}/{len(content.QUIZ)}' if score is not None else 'не проходил'}\n"
        f"💼 Тариф: {tariff.title if tariff else 'не выбран'}\n"
        f"🔗 Источник: {escape(user.get('source') or '—')}"
    )


async def notify_admins(bot: Bot, config: Config, text: str) -> None:
    for admin_id in config.admin_ids:
        try:
            await bot.send_message(admin_id, text)
        except Exception:
            log.exception("Не удалось отправить уведомление админу %s", admin_id)
