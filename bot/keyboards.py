from aiogram.types import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    ReplyKeyboardMarkup,
)

from . import content


def _rows(*buttons: InlineKeyboardButton) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[[b] for b in buttons])


def segments() -> InlineKeyboardMarkup:
    return _rows(
        *(InlineKeyboardButton(text=t, callback_data=f"seg:{k}") for k, t in content.SEGMENTS.items())
    )


def start_quiz() -> InlineKeyboardMarkup:
    return _rows(InlineKeyboardButton(text="▶️ Пройти тест", callback_data="quiz:start"))


def quiz_options(index: int, question: content.Question) -> InlineKeyboardMarkup:
    # Варианты перечислены в тексте вопроса, на кнопках — только номера (в один ряд),
    # чтобы длинные ответы не обрезались на экране телефона.
    return InlineKeyboardMarkup(
        inline_keyboard=[[
            InlineKeyboardButton(text=str(i + 1), callback_data=f"q:{index}:{i}")
            for i in range(len(question.options))
        ]]
    )


def after_quiz() -> InlineKeyboardMarkup:
    return _rows(
        InlineKeyboardButton(text="🚀 Как сдать с первого раза", callback_data="offer:show"),
        InlineKeyboardButton(text="🔄 Пройти тест ещё раз", callback_data="quiz:start"),
    )


def to_offer(text: str = "👉 Посмотреть тарифы") -> InlineKeyboardMarkup:
    return _rows(InlineKeyboardButton(text=text, callback_data="offer:show"))


def tariffs(discount_active: bool, manager_username: str) -> InlineKeyboardMarkup:
    buttons = [
        InlineKeyboardButton(
            text=f"{t.title} — {content.discounted(t.price, discount_active)} ₽",
            callback_data=f"tariff:{t.id}",
        )
        for t in content.TARIFFS
    ]
    buttons.append(
        InlineKeyboardButton(text="💬 Задать вопрос / оставить заявку", callback_data="lead:start")
    )
    if manager_username:
        buttons.append(
            InlineKeyboardButton(text="👤 Написать менеджеру", url=f"https://t.me/{manager_username}")
        )
    return _rows(*buttons)


def request_phone() -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        keyboard=[[KeyboardButton(text="📱 Отправить номер", request_contact=True)]],
        resize_keyboard=True,
        one_time_keyboard=True,
    )


def followup(key: str, quiz_done: bool, manager_username: str) -> InlineKeyboardMarkup:
    if key == "nudge" and not quiz_done:
        return start_quiz()
    if key == "discount":
        return to_offer(f"🔥 Забрать скидку {content.DISCOUNT_PERCENT}%")
    if key == "last_call" and manager_username:
        return _rows(
            InlineKeyboardButton(text="👉 Посмотреть тарифы", callback_data="offer:show"),
            InlineKeyboardButton(text="👤 Написать менеджеру", url=f"https://t.me/{manager_username}"),
        )
    return to_offer()
