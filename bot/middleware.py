import time
from typing import Any, Awaitable, Callable

from aiogram import BaseMiddleware
from aiogram.types import TelegramObject, User

from .config import Config
from .db import Database
from .followups import next_followup_time


class UserMiddleware(BaseMiddleware):
    """Создаёт/обновляет пользователя в базе и передаёт его в обработчик как `user`."""

    async def __call__(
        self,
        handler: Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]],
        event: TelegramObject,
        data: dict[str, Any],
    ) -> Any:
        tg_user: User | None = data.get("event_from_user")
        if tg_user is None or tg_user.is_bot:
            return await handler(event, data)
        db: Database = data["db"]
        config: Config = data["config"]
        user, is_new = await db.touch_user(
            tg_user.id, tg_user.username, tg_user.full_name, next_followup_time(int(time.time()), config),
        )
        data["user"] = user
        data["is_new"] = is_new
        return await handler(event, data)
