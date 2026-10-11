import asyncio
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from aiogram import Bot, F, Router
from aiogram.filters import Command, Filter, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, Message, User

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..services import extract_media, grant_access, manager_suffix, send_media, user_link

log = logging.getLogger(__name__)
router = Router()

PAGE_SIZE = 15


class IsAdmin(Filter):
    async def __call__(self, event, config: Config, event_from_user: User | None = None) -> bool:
        return event_from_user is not None and event_from_user.id in config.admin_ids


router.message.filter(IsAdmin())
router.callback_query.filter(IsAdmin())


class AdminForm(StatesGroup):
    broadcast = State()
    grant = State()
    demo = State()
    free = State()


async def admin_menu_text(db: Database) -> tuple[str, object]:
    pending = len(await db.pending_payment_requests())
    return "🛠 <b>Админка</b>", keyboards.admin_menu(pending)


@router.message(Command("admin"))
@router.message(F.text == content.MENU_ADMIN)
async def admin_entry(message: Message, state: FSMContext, db: Database) -> None:
    await state.clear()
    text, markup = await admin_menu_text(db)
    await message.answer(text, reply_markup=markup)


@router.callback_query(F.data == "adm:menu")
async def admin_menu(callback: CallbackQuery, state: FSMContext, db: Database) -> None:
    await state.clear()
    await callback.answer()
    text, markup = await admin_menu_text(db)
    await callback.message.answer(text, reply_markup=markup)


# ---------------------------------------------------------------- статистика

def period_start(period: str, tz: str) -> int:
    now = datetime.now(ZoneInfo(tz))
    if period == "day":
        return int(now.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
    if period == "week":
        return int(now.timestamp()) - 7 * 86400
    return 0


def pct(part: int, whole: int) -> str:
    return f" ({part / whole * 100:.0f}%)" if whole else ""


@router.callback_query(F.data.startswith("adm:stats:"))
async def stats(callback: CallbackQuery, db: Database, config: Config) -> None:
    period = callback.data.split(":")[2]
    c = await db.event_counts(period_start(period, config.timezone))
    title = {"day": "сегодня", "week": "за 7 дней", "all": "за всё время"}[period]
    started = c.get("start", 0)
    paid = c.get("paid", 0)

    lines = [
        f"📊 <b>Статистика {title}</b>\n",
        f"👋 Зашли в бота: <b>{started}</b>",
        f"✅ Подписались на канал: <b>{c.get('subscribed', 0)}</b>{pct(c.get('subscribed', 0), started)}",
        f"⭐ Смотрели «Показать»: <b>{c.get('show', 0)}</b>{pct(c.get('show', 0), started)}",
        f"🎁 Смотрели бесплатные разборы: <b>{c.get('free', 0)}</b>",
        f"🛒 Дошли до оплаты: <b>{c.get('checkout', 0)}</b>{pct(c.get('checkout', 0), started)}",
        f"💳 Нажали «Оплатить»: <b>{c.get('pay_click', 0)}</b>",
        f"💰 Купили: <b>{paid}</b>{pct(paid, started)}",
        f"💵 Выручка: <b>{paid * config.price:,} ₽</b>".replace(",", " "),
        "",
        f"📝 Экзамен: начали {c.get('exam_start', 0)}, сдали {c.get('exam_pass', 0)}, "
        f"не сдали {c.get('exam_fail', 0)}",
        "",
        f"🔥 Сейчас дошли до оплаты и не купили (всего): <b>{await db.checkout_not_paid_count()}</b>",
    ]
    if period == "all":
        sources = await db.source_counts()
        if any(s["src"] != "—" for s in sources):
            lines.append("\n🔗 <b>Источники</b> (зашли / купили)")
            lines += [f"{s['src']}: {s['total']} / {s['paid'] or 0}" for s in sources]
    lines.append("\n<i>% — от тех, кто зашёл за этот период</i>")

    await callback.answer()
    try:
        await callback.message.edit_text("\n".join(lines), reply_markup=keyboards.admin_stats(period))
    except Exception:  # «message is not modified» при повторном нажатии
        pass


# -------------------------------------------------------------- пользователи

@router.callback_query(F.data == "adm:users")
async def users_menu(callback: CallbackQuery) -> None:
    await callback.answer()
    await callback.message.edit_text("👥 <b>Пользователи</b>\n\nКого показать?", reply_markup=keyboards.admin_users())


@router.callback_query(F.data.startswith("adm:list:"))
async def users_list(callback: CallbackQuery, db: Database, config: Config) -> None:
    _, _, kind, page_s = callback.data.split(":")
    page = int(page_s)
    rows, total = await db.list_users(kind, PAGE_SIZE, page * PAGE_SIZE)
    title = {
        "checkout": "🛒 Дошли до оплаты, но не купили",
        "paid": "✅ Купили",
        "all": "🆕 Все пользователи",
    }[kind]
    tz = ZoneInfo(config.timezone)
    lines = [f"<b>{title}</b> — {total}\n"]
    for i, u in enumerate(rows, start=page * PAGE_SIZE + 1):
        when = datetime.fromtimestamp(u["ts"], tz).strftime("%d.%m %H:%M") if u["ts"] else ""
        mark = " 💰" if kind == "all" and u["paid"] else ""
        lines.append(f"{i}. {user_link(u)} — {when}{mark}")
    if not rows:
        lines.append("Пока никого.")
    await callback.answer()
    await callback.message.edit_text(
        "\n".join(lines),
        reply_markup=keyboards.admin_list_nav(kind, page, (page + 1) * PAGE_SIZE < total),
        disable_web_page_preview=True,
    )


# ----------------------------------------------------- подтверждение оплат

@router.callback_query(F.data == "adm:pending")
async def pending(callback: CallbackQuery, bot: Bot, db: Database, config: Config) -> None:
    await callback.answer()
    requests = await db.pending_payment_requests()
    if not requests:
        await callback.message.answer("💳 Нет оплат, ожидающих подтверждения.", reply_markup=keyboards.admin_back())
        return
    for r in requests:
        caption = f"💳 <b>Проверь оплату #{r['id']}</b> — {config.price} ₽\n\n{user_link(r)}"
        markup = keyboards.admin_payment(r["id"])
        try:
            await send_media(bot, callback.from_user.id, {"type": "photo", "file_id": r["file_id"]},
                             caption=caption, reply_markup=markup)
        except Exception:
            try:
                await send_media(bot, callback.from_user.id, {"type": "document", "file_id": r["file_id"]},
                                 caption=caption, reply_markup=markup)
            except Exception:
                await callback.message.answer(caption, reply_markup=markup)


async def _mark_handled(callback: CallbackQuery, note: str) -> None:
    msg = callback.message
    try:
        if msg.caption is not None:
            await msg.edit_caption(caption=f"{msg.html_text}\n\n{note}", reply_markup=None)
        else:
            await msg.edit_text(f"{msg.html_text}\n\n{note}", reply_markup=None)
    except Exception:
        await msg.edit_reply_markup(reply_markup=None)


@router.callback_query(F.data.startswith("adm:pay_ok:"))
async def payment_ok(callback: CallbackQuery, bot: Bot, db: Database, config: Config) -> None:
    request_id = int(callback.data.split(":")[2])
    request = await db.get_payment_request(request_id)
    if not request or not await db.set_payment_request_status(request_id, "approved"):
        await callback.answer("Эта оплата уже обработана", show_alert=True)
        await callback.message.edit_reply_markup(reply_markup=None)
        return
    await callback.answer("Доступ выдан ✅")
    await grant_access(bot, db, config, request["user_id"], via=f"СБП, чек #{request_id}")
    await _mark_handled(callback, "✅ <b>Подтверждено, доступ выдан</b>")


@router.callback_query(F.data.startswith("adm:pay_no:"))
async def payment_no(callback: CallbackQuery, bot: Bot, db: Database, config: Config) -> None:
    request_id = int(callback.data.split(":")[2])
    request = await db.get_payment_request(request_id)
    if not request or not await db.set_payment_request_status(request_id, "rejected"):
        await callback.answer("Эта оплата уже обработана", show_alert=True)
        await callback.message.edit_reply_markup(reply_markup=None)
        return
    await callback.answer("Отклонено")
    try:
        await bot.send_message(request["user_id"], content.PAYMENT_REJECTED.format(manager=manager_suffix(config)),
                               reply_markup=keyboards.manager(config))
    except Exception:
        log.exception("Не удалось уведомить об отклонении %s", request["user_id"])
    await _mark_handled(callback, "❌ <b>Отклонено</b>")


# ------------------------------------------------------------------ рассылка

AUDIENCE_TITLES = {"all": "всем", "unpaid": "тем, кто не купил", "paid": "тем, кто купил"}


@router.callback_query(F.data == "adm:bc")
async def broadcast_menu(callback: CallbackQuery) -> None:
    await callback.answer()
    await callback.message.edit_text("📣 <b>Рассылка</b>\n\nКому отправить?",
                                     reply_markup=keyboards.admin_broadcast_audience())


@router.callback_query(F.data.startswith("adm:bc_to:"))
async def broadcast_audience(callback: CallbackQuery, state: FSMContext) -> None:
    audience = callback.data.split(":")[2]
    await state.set_state(AdminForm.broadcast)
    await state.update_data(audience=audience)
    await callback.answer()
    await callback.message.edit_text(
        f"📣 Рассылка {AUDIENCE_TITLES[audience]}.\n\n"
        "Пришли сообщение, которое нужно разослать — текст, фото, видео, кружок, что угодно. "
        "Оно уйдёт копией, без пометки «переслано».",
        reply_markup=keyboards.admin_back(),
    )


@router.message(StateFilter(AdminForm.broadcast))
async def broadcast_message(message: Message, state: FSMContext, db: Database) -> None:
    data = await state.get_data()
    await state.update_data(chat_id=message.chat.id, message_id=message.message_id)
    count = len(await db.user_ids(data["audience"]))
    await message.answer(
        f"☝️ Так будет выглядеть сообщение.\n\nОтправить {AUDIENCE_TITLES[data['audience']]} — "
        f"<b>{count}</b> чел.?",
        reply_markup=keyboards.admin_broadcast_confirm(),
    )


async def run_broadcast(bot: Bot, db: Database, admin_id: int, audience: str, chat_id: int,
                        message_id: int) -> None:
    sent = failed = 0
    for uid in await db.user_ids(audience):
        try:
            await bot.copy_message(uid, chat_id, message_id)
            sent += 1
        except Exception:
            failed += 1
            await db.update_user(uid, blocked=1)
        await asyncio.sleep(0.05)  # лимит Telegram ~30 сообщений в секунду
    await bot.send_message(admin_id, f"✅ Рассылка завершена.\nДоставлено: {sent}\nНе доставлено: {failed}")


@router.callback_query(F.data == "adm:bc_go")
async def broadcast_go(callback: CallbackQuery, state: FSMContext, bot: Bot, db: Database) -> None:
    data = await state.get_data()
    await state.clear()
    if "message_id" not in data:
        await callback.answer("Сначала пришли сообщение", show_alert=True)
        return
    await callback.answer()
    await callback.message.edit_text("🚀 Рассылка запущена, пришлю отчёт, когда закончу.")
    asyncio.create_task(run_broadcast(
        bot, db, callback.from_user.id, data["audience"], data["chat_id"], data["message_id"]
    ))


# ------------------------------------------------------------- выдать доступ

@router.callback_query(F.data == "adm:grant")
async def grant_menu(callback: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(AdminForm.grant)
    await callback.answer()
    await callback.message.edit_text(
        "🎁 <b>Выдать доступ вручную</b>\n\n"
        "Пришли ID пользователя, его @username или перешли любое его сообщение.\n"
        "<i>Человек должен хотя бы раз запустить бота.</i>",
        reply_markup=keyboards.admin_back(),
    )


@router.message(StateFilter(AdminForm.grant))
async def grant_input(message: Message, state: FSMContext, bot: Bot, db: Database, config: Config) -> None:
    user = None
    if message.forward_from:
        user = await db.get_user(message.forward_from.id)
    elif message.text:
        value = message.text.strip()
        if value.lstrip("-").isdigit():
            user = await db.get_user(int(value))
        else:
            user = await db.find_user_by_username(value)
    if not user:
        await message.answer(
            "Не нашёл такого пользователя в боте 🤔 Проверь ID/username — "
            "или попроси человека нажать /start и попробуй снова.",
            reply_markup=keyboards.admin_back(),
        )
        return
    await state.clear()
    if await grant_access(bot, db, config, user["user_id"], via="выдан вручную"):
        await message.answer(f"✅ Доступ выдан: {user_link(user)}", reply_markup=keyboards.admin_back())
    else:
        await message.answer(f"У {user_link(user)} уже есть доступ.", reply_markup=keyboards.admin_back())


# ------------------------------------------------------------- видео воронки

async def media_screen(db: Database) -> tuple[str, object]:
    demo = await db.get_setting("demo_media")
    free = await db.get_setting("free_media", [])
    text = (
        "🎬 <b>Видео в воронке</b>\n\n"
        f"• Видео-показ канала (после кнопки «Показать»): {'✅ есть' if demo else '❌ нет'}\n"
        f"• Бесплатные разборы: {len(free)} шт.\n\n"
        "<i>Пока видео нет, клиенты видят только текст.</i>"
    )
    return text, keyboards.admin_media(bool(demo), len(free))


@router.callback_query(F.data == "adm:media")
async def media_menu(callback: CallbackQuery, state: FSMContext, db: Database) -> None:
    await state.clear()
    await callback.answer()
    text, markup = await media_screen(db)
    await callback.message.answer(text, reply_markup=markup)


@router.callback_query(F.data == "adm:m_demo")
async def media_demo(callback: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(AdminForm.demo)
    await callback.answer()
    await callback.message.answer("Пришли видео, где ты показываешь канал 🎬", reply_markup=keyboards.admin_back())


@router.callback_query(F.data == "adm:m_free")
async def media_free(callback: CallbackQuery, state: FSMContext) -> None:
    await state.set_state(AdminForm.free)
    await callback.answer()
    await callback.message.answer(
        "Пришли видео с бесплатным разбором 🎁 Можно несколько подряд.", reply_markup=keyboards.admin_back()
    )


@router.message(StateFilter(AdminForm.demo, AdminForm.free))
async def media_upload(message: Message, state: FSMContext, db: Database) -> None:
    media = extract_media(message)
    if not media:
        await message.answer("Это не видео/фото 🤔 Пришли файл или нажми «В админку».")
        return
    if await state.get_state() == AdminForm.demo.state:
        await db.set_setting("demo_media", media)
        await state.clear()
        await message.answer("✅ Видео-показ сохранён.")
        text, markup = await media_screen(db)
        await message.answer(text, reply_markup=markup)
    else:
        free = await db.get_setting("free_media", [])
        free.append(media)
        await db.set_setting("free_media", free)
        await message.answer(
            f"✅ Добавлено (всего: {len(free)}). Пришли ещё или вернись в админку.",
            reply_markup=keyboards.admin_back(),
        )


@router.callback_query(F.data == "adm:m_free_clear")
async def media_free_clear(callback: CallbackQuery, db: Database) -> None:
    await db.set_setting("free_media", [])
    await callback.answer("Удалено")
    text, markup = await media_screen(db)
    await callback.message.edit_text(text, reply_markup=markup)


@router.callback_query(F.data == "adm:m_preview")
async def media_preview(callback: CallbackQuery, bot: Bot, db: Database) -> None:
    await callback.answer()
    uid = callback.from_user.id
    demo = await db.get_setting("demo_media")
    if demo:
        await send_media(bot, uid, demo, caption=content.SHOW, reply_markup=keyboards.after_show())
    for media in await db.get_setting("free_media", []):
        await send_media(bot, uid, media)
