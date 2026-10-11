"""Общая логика: проверка подписки, выдача доступа, медиа, уведомления админам."""
import logging
import time
from html import escape
from typing import Any

from aiogram import Bot
from aiogram.enums import ChatMemberStatus
from aiogram.types import InlineKeyboardMarkup

from . import content, keyboards
from .config import Config
from .db import Database

log = logging.getLogger(__name__)

MEMBER_STATUSES = {ChatMemberStatus.MEMBER, ChatMemberStatus.ADMINISTRATOR, ChatMemberStatus.CREATOR}


def is_admin(user_id: int, config: Config) -> bool:
    return user_id in config.admin_ids


def manager_suffix(config: Config) -> str:
    return f": @{config.manager_username}" if config.manager_username else ""


def user_link(user: dict[str, Any]) -> str:
    name = escape(user.get("full_name") or str(user["user_id"]))
    username = f" (@{escape(user['username'])})" if user.get("username") else ""
    return f'<a href="tg://user?id={user["user_id"]}">{name}</a>{username}'


async def notify_admins(bot: Bot, config: Config, text: str, **kwargs: Any) -> None:
    for admin_id in config.admin_ids:
        try:
            await bot.send_message(admin_id, text, **kwargs)
        except Exception:
            log.exception("Не удалось написать админу %s", admin_id)


# ------------------------------------------------------------------ каналы
#
# Каналы можно задать в .env, но удобнее так: добавить бота админом в канал/группу,
# и он сам спросит у админа, что это за чат (см. handlers/admin.py → setchat).
# Выбор сохраняется в базе и имеет приоритет над .env.

async def subscribe_target(db: Database, config: Config) -> tuple[int | str, str] | None:
    """(чат для проверки подписки, ссылка для кнопки) или None, если подписка не нужна."""
    saved = await db.get_setting("subscribe_chat")
    if saved:
        return saved["id"], saved["url"]
    if config.subscribe_channel:
        return config.subscribe_channel, config.subscribe_button_url
    return None


async def private_chat_id(db: Database, config: Config) -> int | None:
    saved = await db.get_setting("private_chat")
    return saved["id"] if saved else config.private_channel_id


# ----------------------------------------------------------------- подписка

async def check_subscription(bot: Bot, db: Database, config: Config, user_id: int) -> bool:
    target = await subscribe_target(db, config)
    if not target:
        return True
    try:
        member = await bot.get_chat_member(target[0], user_id)
    except Exception:
        # Чаще всего бот не добавлен админом в канал. Не блокируем пользователя из-за нашей настройки.
        log.exception("Не удалось проверить подписку — бот должен быть админом канала %s", target[0])
        return True
    return member.status in MEMBER_STATUSES


async def ensure_subscribed(bot: Bot, db: Database, config: Config, user: dict[str, Any]) -> bool:
    """True — можно пускать дальше. Иначе отправляет просьбу подписаться."""
    if user["subscribed"]:
        return True
    if await check_subscription(bot, db, config, user["user_id"]):
        await mark_subscribed(db, user["user_id"])
        return True
    target = await subscribe_target(db, config)
    await bot.send_message(user["user_id"], content.NOT_SUBSCRIBED,
                           reply_markup=keyboards.subscribe(target[1] if target else ""))
    return False


async def mark_subscribed(db: Database, user_id: int) -> None:
    await db.update_user(user_id, subscribed=1)
    await db.add_event(user_id, "subscribed")


# ------------------------------------------------------------------ доступ

async def make_access_link(bot: Bot, db: Database, config: Config, user_id: int) -> str | None:
    chat_id = await private_chat_id(db, config)
    if chat_id:
        try:
            link = await bot.create_chat_invite_link(chat_id, name=f"user {user_id}", member_limit=1)
            return link.invite_link
        except Exception:
            log.exception("Не удалось создать ссылку — бот должен быть админом закрытого канала")
    return config.access_link or None


async def is_channel_member(bot: Bot, db: Database, config: Config, user_id: int) -> bool:
    chat_id = await private_chat_id(db, config)
    if not chat_id:
        return False
    try:
        member = await bot.get_chat_member(chat_id, user_id)
        return member.status in MEMBER_STATUSES
    except Exception:
        return False


async def grant_access(bot: Bot, db: Database, config: Config, user_id: int, via: str) -> bool:
    """Отмечает покупку и отправляет ссылку. False — у пользователя уже был доступ."""
    user = await db.get_user(user_id)
    if user is None:
        now = int(time.time())
        user, _ = await db.touch_user(user_id, None, str(user_id), now)
    if user["paid"]:
        return False

    await db.update_user(user_id, paid=1, paid_at=int(time.time()), next_followup_at=None)
    await db.add_event(user_id, "paid")

    link = await make_access_link(bot, db, config, user_id)
    try:
        if link:
            await bot.send_message(user_id, content.ACCESS_GRANTED.format(link=link))
        else:
            await bot.send_message(user_id, content.ACCESS_MANUAL)
    except Exception:
        log.exception("Не удалось отправить доступ пользователю %s", user_id)

    note = "" if link else "\n\n⚠️ Закрытая группа не настроена — отправь ссылку вручную!"
    await notify_admins(
        bot, config,
        f"💰 <b>Новая покупка — {config.price} ₽</b> ({via})\n\n{user_link(user)}{note}",
    )
    return True


# ------------------------------------------------------------------- медиа

async def send_media(bot: Bot, chat_id: int, media: dict[str, str], caption: str | None = None,
                     reply_markup: InlineKeyboardMarkup | None = None) -> None:
    kind, file_id = media["type"], media["file_id"]
    sender = {
        "video": bot.send_video,
        "photo": bot.send_photo,
        "animation": bot.send_animation,
        "document": bot.send_document,
    }[kind]
    await sender(chat_id, file_id, caption=caption, reply_markup=reply_markup)


def extract_media(message) -> dict[str, str] | None:
    if message.video:
        return {"type": "video", "file_id": message.video.file_id}
    if message.photo:
        return {"type": "photo", "file_id": message.photo[-1].file_id}
    if message.animation:
        return {"type": "animation", "file_id": message.animation.file_id}
    if message.document:
        return {"type": "document", "file_id": message.document.file_id}
    return None
