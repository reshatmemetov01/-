from aiogram import Bot, F, Router
from aiogram.filters import StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, Message

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..services import (
    extract_media,
    is_channel_member,
    make_access_link,
    manager_suffix,
    notify_admins,
    send_media,
    user_link,
)

router = Router()


class PayForm(StatesGroup):
    receipt = State()
    promo = State()


async def send_access_again(bot: Bot, db: Database, config: Config, user_id: int, back: bool = False) -> None:
    def markup(base=None):
        return keyboards.with_back(base) if back else base

    if await is_channel_member(bot, db, config, user_id):
        await bot.send_message(user_id, content.ACCESS_ALREADY_MEMBER, reply_markup=markup())
        return
    link = await make_access_link(bot, db, config, user_id)
    if link:
        await bot.send_message(user_id, content.ACCESS_LINK_AGAIN.format(link=link), reply_markup=markup())
    else:
        await bot.send_message(user_id, content.ACCESS_MANUAL, reply_markup=markup(keyboards.manager(config)))


async def send_offer(bot: Bot, db: Database, config: Config, user: dict, back: bool = False) -> None:
    """back=True — открыто из нижнего меню, добавляем кнопку «Назад»."""
    if user["paid"]:
        await send_access_again(bot, db, config, user["user_id"], back=back)
        return
    await db.add_event(user["user_id"], "checkout")
    markup = keyboards.offer(config.manager_username)
    await bot.send_message(
        user["user_id"],
        content.offer_text(config.price, config.old_price, config.manager_username),
        reply_markup=keyboards.with_back(markup) if back else markup,
        disable_web_page_preview=True,
    )


@router.callback_query(F.data == "f:show")
async def show(callback: CallbackQuery, bot: Bot, db: Database, config: Config, user: dict) -> None:
    await callback.answer()
    await db.add_event(user["user_id"], "show")
    demo = await db.get_setting("demo_media")
    if demo:
        await send_media(bot, user["user_id"], demo, caption=content.SHOW, reply_markup=keyboards.after_show())
    else:
        await callback.message.answer(content.SHOW, reply_markup=keyboards.after_show())


@router.callback_query(F.data == "f:offer")
async def offer(callback: CallbackQuery, state: FSMContext, bot: Bot, db: Database, config: Config,
                user: dict) -> None:
    await callback.answer()
    await state.clear()
    await send_offer(bot, db, config, user)


# ------------------------------------------------ оплата по СБП (временная)

@router.callback_query(F.data == "pay:sbp")
async def pay_sbp(callback: CallbackQuery, db: Database, config: Config, user: dict) -> None:
    await callback.answer()
    await db.add_event(user["user_id"], "pay_click")
    if not config.payment_details:
        await callback.message.answer(
            content.PAYMENT_NOT_READY.format(manager=manager_suffix(config)),
            reply_markup=keyboards.manager(config),
        )
        return
    await callback.message.answer(
        content.SBP_TEXT.format(price=config.price, details=config.payment_details),
        reply_markup=keyboards.sbp(),
    )


@router.callback_query(F.data == "pay:sent")
async def pay_sent(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.answer()
    await state.set_state(PayForm.receipt)
    await callback.message.answer(content.ASK_RECEIPT)


@router.message(StateFilter(PayForm.receipt))
async def receipt(message: Message, state: FSMContext, bot: Bot, db: Database, config: Config,
                  user: dict) -> None:
    media = extract_media(message)
    if not media or media["type"] not in ("photo", "document"):
        await message.answer(content.RECEIPT_NEED_PHOTO)
        return
    await state.clear()
    request_id = await db.create_payment_request(user["user_id"], media["file_id"])
    await message.answer(content.RECEIPT_RECEIVED)

    caption = f"💳 <b>Проверь оплату #{request_id}</b> — {config.price} ₽\n\n{user_link(user)}"
    for admin_id in config.admin_ids:
        try:
            await send_media(bot, admin_id, media, caption=caption,
                             reply_markup=keyboards.admin_payment(request_id))
        except Exception:
            await notify_admins(bot, config, caption, reply_markup=keyboards.admin_payment(request_id))


# ------------------------------------------------------------------ промокод

@router.callback_query(F.data == "pay:promo")
async def promo(callback: CallbackQuery, state: FSMContext) -> None:
    await callback.answer()
    await state.set_state(PayForm.promo)
    await callback.message.answer(content.PROMO_ASK)


@router.message(StateFilter(PayForm.promo), F.text)
async def promo_code(message: Message, state: FSMContext, config: Config) -> None:
    # Промокодов пока нет — когда появятся, проверка будет здесь
    await state.clear()
    await message.answer(content.PROMO_NOT_FOUND, reply_markup=keyboards.offer(config.manager_username))
