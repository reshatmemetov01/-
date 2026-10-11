import time

from aiogram import Bot, F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, LabeledPrice, Message, PreCheckoutQuery

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..notify import notify_admins, user_card
from .lead import start_lead_form

router = Router()


def discount_active(user: dict) -> bool:
    return bool(user.get("discount_until")) and user["discount_until"] > time.time()


@router.callback_query(F.data == "offer:show")
async def show_offer(callback: CallbackQuery, db: Database, config: Config) -> None:
    user = await db.get_user(callback.from_user.id)
    if not user:
        await callback.answer("Нажмите /start", show_alert=True)
        return
    await db.advance_stage(user["user_id"], "offer")

    active = discount_active(user)
    intro = content.OFFER_INTRO.get(user.get("segment"), content.OFFER_INTRO[None])
    await callback.message.answer(
        intro + content.OFFER_BODY + "\n\n" + content.tariffs_text(active),
        reply_markup=keyboards.tariffs(active, config.manager_username),
    )
    await callback.answer()


@router.callback_query(F.data.startswith("tariff:"))
async def choose_tariff(
    callback: CallbackQuery, db: Database, config: Config, state: FSMContext, bot: Bot
) -> None:
    tariff = content.TARIFFS_BY_ID.get(callback.data.split(":", 1)[1])
    user = await db.get_user(callback.from_user.id)
    if not tariff or not user:
        await callback.answer()
        return
    await db.update_user(user["user_id"], tariff=tariff.id)
    await callback.answer()

    if config.payment_provider_token:
        price = content.discounted(tariff.price, discount_active(user))
        await bot.send_invoice(
            chat_id=user["user_id"],
            title=f"{content.PRODUCT_NAME}",
            description=f"Тариф «{tariff.title}». {tariff.description}"[:255],
            payload=f"tariff:{tariff.id}",
            provider_token=config.payment_provider_token,
            currency=config.currency,
            prices=[LabeledPrice(label=f"Тариф «{tariff.title}»", amount=price * 100)],
        )
    else:
        await start_lead_form(callback.message, state, tariff_title=tariff.title)


@router.pre_checkout_query()
async def pre_checkout(query: PreCheckoutQuery) -> None:
    ok = query.invoice_payload.split(":", 1)[-1] in content.TARIFFS_BY_ID
    await query.answer(ok=ok, error_message=None if ok else "Тариф не найден, попробуйте ещё раз")


@router.message(F.successful_payment)
async def successful_payment(message: Message, db: Database, config: Config, bot: Bot) -> None:
    payment = message.successful_payment
    tariff_id = payment.invoice_payload.split(":", 1)[-1]
    user_id = message.from_user.id
    await db.update_user(user_id, tariff=tariff_id, next_followup_at=None)
    await db.advance_stage(user_id, "paid")

    access = f"🔑 Ваш доступ: {config.access_link}\n\n" if config.access_link else ""
    await message.answer(content.PAYMENT_DONE.format(access=access))

    user = await db.get_user(user_id)
    amount = payment.total_amount / 100
    await notify_admins(
        bot, config, f"💰 <b>Новая оплата: {amount:.0f} {payment.currency}</b>\n\n{user_card(user)}"
    )
