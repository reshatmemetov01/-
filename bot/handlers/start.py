from html import escape

from aiogram import Bot, F, Router
from aiogram.filters import CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..services import check_subscription, is_admin, mark_subscribed

router = Router()


async def after_subscribed(bot: Bot, db: Database, config: Config, user_id: int) -> None:
    await bot.send_message(
        user_id, content.SUBSCRIBED_OK, reply_markup=keyboards.main_menu(is_admin(user_id, config))
    )
    await bot.send_message(user_id, content.ABOUT, reply_markup=keyboards.show())
    await db.add_event(user_id, "about")


@router.message(CommandStart())
async def cmd_start(message: Message, command: CommandObject, state: FSMContext, bot: Bot,
                    db: Database, config: Config, user: dict, is_new: bool) -> None:
    await state.clear()
    uid = user["user_id"]
    # Источник трафика из ссылки t.me/бот?start=метка — запоминаем только при первом входе
    if is_new and command.args:
        await db.update_user(uid, source=command.args.strip()[:64])

    if user["paid"]:
        await message.answer(content.WELCOME_BACK_PAID, reply_markup=keyboards.main_menu(is_admin(uid, config)))
        return

    welcome = content.WELCOME.format(name=escape(message.from_user.first_name or "друг"))
    if config.subscribe_channel and not user["subscribed"]:
        await message.answer(f"{welcome}\n\n{content.SUBSCRIBE_PROMPT}", reply_markup=keyboards.subscribe(config))
        return

    await message.answer(welcome)
    if not user["subscribed"]:
        await mark_subscribed(db, uid)
    await after_subscribed(bot, db, config, uid)


@router.callback_query(F.data == "sub:check")
async def sub_check(callback: CallbackQuery, bot: Bot, db: Database, config: Config, user: dict) -> None:
    uid = user["user_id"]
    if not user["subscribed"]:
        if not await check_subscription(bot, config, uid):
            await callback.answer("Не вижу подписки 🙈 Подпишись и нажми ещё раз", show_alert=True)
            return
        await mark_subscribed(db, uid)
    await callback.answer()
    await callback.message.edit_reply_markup(reply_markup=None)
    await after_subscribed(bot, db, config, uid)
