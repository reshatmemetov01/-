import re

from aiogram import Bot, F, Router
from aiogram.filters import StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, Message, ReplyKeyboardRemove
from html import escape

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..notify import notify_admins, user_card

router = Router()


class LeadForm(StatesGroup):
    name = State()
    phone = State()


async def start_lead_form(message: Message, state: FSMContext, tariff_title: str | None = None) -> None:
    await state.set_state(LeadForm.name)
    prefix = f"Тариф «{tariff_title}» — отличный выбор! 👍\n\n" if tariff_title else ""
    await message.answer(prefix + content.LEAD_ASK_NAME)


@router.callback_query(F.data == "lead:start")
async def lead_start(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.answer()
    await start_lead_form(callback.message, state)


@router.message(StateFilter(LeadForm.name), F.text)
async def lead_name(message: Message, state: FSMContext) -> None:
    name = message.text.strip()[:64]
    if name.startswith("/"):
        await message.answer(content.LEAD_ASK_NAME)
        return
    await state.update_data(name=name)
    await state.set_state(LeadForm.phone)
    await message.answer(content.LEAD_ASK_PHONE.format(name=escape(name)), reply_markup=keyboards.request_phone())


def normalize_phone(raw: str) -> str | None:
    digits = re.sub(r"\D", "", raw)
    if len(digits) == 11 and digits[0] == "8":
        digits = "7" + digits[1:]
    elif len(digits) == 10:
        digits = "7" + digits
    if not 10 <= len(digits) <= 15:
        return None
    return "+" + digits


@router.message(StateFilter(LeadForm.phone), F.contact | F.text)
async def lead_phone(message: Message, state: FSMContext, db: Database, config: Config, bot: Bot) -> None:
    raw = message.contact.phone_number if message.contact else message.text
    phone = normalize_phone(raw or "")
    if not phone:
        await message.answer(content.LEAD_BAD_PHONE, reply_markup=keyboards.request_phone())
        return

    data = await state.get_data()
    await state.clear()
    user_id = message.from_user.id
    await db.update_user(user_id, lead_name=data.get("name"), phone=phone, next_followup_at=None)
    await db.advance_stage(user_id, "lead")

    await message.answer(content.LEAD_DONE, reply_markup=ReplyKeyboardRemove())

    user = await db.get_user(user_id)
    await notify_admins(bot, config, f"🔥 <b>Новая заявка</b>\n\n{user_card(user)}")
