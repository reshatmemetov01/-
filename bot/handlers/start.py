import time

from aiogram import F, Router
from aiogram.filters import CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message
from html import escape

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..followups import scaled_delay

router = Router()


@router.message(CommandStart())
async def cmd_start(
    message: Message, command: CommandObject, state: FSMContext, db: Database, config: Config
) -> None:
    await state.clear()
    user = message.from_user
    # Источник трафика из deep-link: t.me/your_bot?start=vk_ads → source = "vk_ads"
    source = (command.args or "").strip()[:64] or None
    first_at = int(time.time() + scaled_delay(content.FOLLOWUPS[0].delay, config))
    await db.create_user_if_missing(user.id, user.username, user.full_name, source, first_at)

    await message.answer(
        content.WELCOME.format(name=escape(user.first_name or "друг")),
        reply_markup=keyboards.segments(),
    )


@router.callback_query(F.data.startswith("seg:"))
async def choose_segment(callback: CallbackQuery, db: Database) -> None:
    segment = callback.data.split(":", 1)[1]
    if segment not in content.SEGMENTS:
        await callback.answer()
        return
    await db.update_user(callback.from_user.id, segment=segment)
    await db.advance_stage(callback.from_user.id, "segment")

    await callback.message.edit_reply_markup(reply_markup=None)
    await callback.message.answer(
        f"{content.SEGMENTS[segment]}\n\n{content.SEGMENT_REPLY[segment]}\n\n{content.QUIZ_INVITE}",
        reply_markup=keyboards.start_quiz(),
    )
    await callback.answer()
