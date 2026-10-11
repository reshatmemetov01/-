from aiogram.types import (
    InlineKeyboardButton as B,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
)

from . import content
from .config import Config


def inline(*rows: list[B] | B) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[r if isinstance(r, list) else [r] for r in rows])


def main_menu(is_admin: bool) -> ReplyKeyboardMarkup:
    rows = [
        [KeyboardButton(text=content.MENU_VIDEOS)],
        [KeyboardButton(text=content.MENU_TRAINING), KeyboardButton(text=content.MENU_REVIEWS)],
        [KeyboardButton(text=content.MENU_FAQ), KeyboardButton(text=content.MENU_INFO)],
        [KeyboardButton(text=content.MENU_SUPPORT)],
    ]
    if is_admin:
        rows.append([KeyboardButton(text=content.MENU_ADMIN)])
    return ReplyKeyboardMarkup(keyboard=rows, resize_keyboard=True)


# ---------------------------------------------------------------- воронка

def welcome(channel_url: str) -> InlineKeyboardMarkup:
    return inline(
        B(text="📢 Подписаться на канал", url=channel_url),
        B(text="➡️ Продолжить", callback_data="go:continue"),
    )


def show() -> InlineKeyboardMarkup:
    return inline(B(text="⭐ ПОКАЗАТЬ", callback_data="f:show"))


def after_show() -> InlineKeyboardMarkup:
    return get_access()


def get_access() -> InlineKeyboardMarkup:
    return inline(B(text="👑 ПОЛУЧИТЬ ДОСТУП", callback_data="f:offer"))


def support_button(manager_username: str) -> B | None:
    if not manager_username:
        return None
    return B(text="💬 Поддержка", url=f"https://t.me/{manager_username}")


def offer(manager_username: str) -> InlineKeyboardMarkup:
    # Сюда же добавится кнопка Platega, когда платёжка будет подключена
    rows = [
        B(text="💳 Оплатить по СБП", callback_data="pay:sbp"),
        B(text="🎟 Ввести промокод", callback_data="pay:promo"),
    ]
    if support := support_button(manager_username):
        rows.append(support)
    return inline(*rows)


def sbp() -> InlineKeyboardMarkup:
    return inline(
        B(text="✅ Я оплатил", callback_data="pay:sent"),
        B(text="⬅️ Назад", callback_data="f:offer"),
    )


def manager(config: Config) -> InlineKeyboardMarkup | None:
    if not config.manager_username:
        return None
    return inline(B(text="💬 Написать в поддержку", url=f"https://t.me/{config.manager_username}"))


# ---------------------------------------------------------------- экзамен

def exam_start() -> InlineKeyboardMarkup:
    return inline(B(text="▶️ Начать экзамен", callback_data="ex:start"))


def exam_answers(index: int, count: int) -> InlineKeyboardMarkup:
    return inline([B(text=str(i + 1), callback_data=f"ex:{index}:{i}") for i in range(count)])


def exam_finish(failed: bool, paid: bool) -> InlineKeyboardMarkup:
    rows = []
    if failed and not paid:
        rows.append(B(text="👑 ПОЛУЧИТЬ ДОСТУП", callback_data="f:offer"))
    rows.append(B(text="🔄 Пройти ещё раз", callback_data="ex:start"))
    return inline(*rows)


# ------------------------------------------------------------------ дожим

def followup(button: str, manager_username: str = "") -> InlineKeyboardMarkup:
    if button == "show":
        return inline(B(text="⭐ Посмотреть, что внутри", callback_data="f:show"))
    if button == "offer_support" and (support := support_button(manager_username)):
        return inline(B(text="👑 ПОЛУЧИТЬ ДОСТУП", callback_data="f:offer"), support)
    if button == "exam":
        return inline(B(text="📝 Пройти экзамен", callback_data="ex:start"))
    return get_access()


# ------------------------------------------------------------------ админка

def admin_menu(pending: int) -> InlineKeyboardMarkup:
    pending_text = f"💳 Ждут подтверждения ({pending})" if pending else "💳 Ждут подтверждения"
    return inline(
        B(text="📊 Статистика", callback_data="adm:stats:day"),
        B(text="👥 Пользователи", callback_data="adm:users"),
        B(text=pending_text, callback_data="adm:pending"),
        B(text="📣 Рассылка", callback_data="adm:bc"),
        B(text="🎁 Выдать доступ", callback_data="adm:grant"),
        B(text="🎬 Видео в воронке", callback_data="adm:media"),
        B(text="🔗 Каналы и группа", callback_data="adm:chats"),
    )


def admin_setchat(chat_id: int) -> InlineKeyboardMarkup:
    return inline(
        B(text="🔒 Закрытая группа с разборами", callback_data=f"setchat:private:{chat_id}"),
        B(text="📢 Наш канал (ссылка в приветствии)", callback_data=f"setchat:channel:{chat_id}"),
        B(text="✖️ Ни то, ни другое", callback_data="setchat:none:0"),
    )


def admin_chats(has_channel: bool) -> InlineKeyboardMarkup:
    rows = []
    if has_channel:
        rows.append(B(text="🚫 Убрать канал из приветствия", callback_data="setchat:channel_off:0"))
    rows.append(B(text="⬅️ В админку", callback_data="adm:menu"))
    return inline(*rows)


def admin_back() -> InlineKeyboardMarkup:
    return inline(B(text="⬅️ В админку", callback_data="adm:menu"))


def admin_stats(period: str) -> InlineKeyboardMarkup:
    labels = {"day": "Сегодня", "week": "7 дней", "all": "Всё время"}
    return inline(
        [B(text=("• " if p == period else "") + t, callback_data=f"adm:stats:{p}") for p, t in labels.items()],
        B(text="⬅️ В админку", callback_data="adm:menu"),
    )


def admin_users() -> InlineKeyboardMarkup:
    return inline(
        B(text="🛒 Дошли до оплаты, не купили", callback_data="adm:list:checkout:0"),
        B(text="✅ Купили", callback_data="adm:list:paid:0"),
        B(text="🆕 Все (новые сверху)", callback_data="adm:list:all:0"),
        B(text="⬅️ В админку", callback_data="adm:menu"),
    )


def admin_list_nav(kind: str, page: int, has_next: bool) -> InlineKeyboardMarkup:
    nav = []
    if page > 0:
        nav.append(B(text="◀️", callback_data=f"adm:list:{kind}:{page - 1}"))
    if has_next:
        nav.append(B(text="▶️", callback_data=f"adm:list:{kind}:{page + 1}"))
    rows = [nav] if nav else []
    rows.append(B(text="⬅️ Назад", callback_data="adm:users"))
    return inline(*rows)


def admin_payment(request_id: int) -> InlineKeyboardMarkup:
    return inline([
        B(text="✅ Подтвердить", callback_data=f"adm:pay_ok:{request_id}"),
        B(text="❌ Отклонить", callback_data=f"adm:pay_no:{request_id}"),
    ])


def admin_broadcast_audience() -> InlineKeyboardMarkup:
    return inline(
        B(text="👥 Всем", callback_data="adm:bc_to:all"),
        B(text="🛒 Кто не купил", callback_data="adm:bc_to:unpaid"),
        B(text="✅ Кто купил", callback_data="adm:bc_to:paid"),
        B(text="⬅️ В админку", callback_data="adm:menu"),
    )


def admin_broadcast_confirm() -> InlineKeyboardMarkup:
    return inline([
        B(text="🚀 Отправить", callback_data="adm:bc_go"),
        B(text="✖️ Отмена", callback_data="adm:menu"),
    ])


def admin_media(has_demo: bool) -> InlineKeyboardMarkup:
    rows = [
        B(text=("🔁 Заменить" if has_demo else "➕ Загрузить") + " видео-показ канала", callback_data="adm:m_demo"),
    ]
    if has_demo:
        rows.append(B(text="👁 Посмотреть, как видит клиент", callback_data="adm:m_preview"))
    rows.append(B(text="⬅️ В админку", callback_data="adm:menu"))
    return inline(*rows)
