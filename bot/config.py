import os
from dataclasses import dataclass

from dotenv import load_dotenv


@dataclass(frozen=True)
class Config:
    bot_token: str
    admin_ids: tuple[int, ...]
    db_path: str
    # Ссылка на Telegram-канал для кнопки «Подписаться» в приветствии (подписка не обязательна)
    channel_url: str
    # Закрытая группа с разборами и чатом: бот выдаёт в неё одноразовые ссылки
    private_channel_id: int | None
    # Запасная постоянная ссылка, если закрытая группа не настроена
    access_link: str
    price: int
    old_price: int | None
    manager_username: str
    # Многоразовая ссылка на оплату (Paydex). Кнопка «Оплатить по СБП» ведёт на неё
    payment_url: str
    # Реквизиты для оплаты переводом, если ссылки нет (запасной вариант)
    payment_details: str
    questions_path: str
    followup_delay_scale: float
    timezone: str


def _int_or_none(value: str | None) -> int | None:
    value = (value or "").strip()
    return int(value) if value else None


def load_config() -> Config:
    load_dotenv()

    token = os.getenv("BOT_TOKEN", "").strip()
    if not token:
        raise RuntimeError("Не задан BOT_TOKEN (см. .env.example)")

    return Config(
        bot_token=token,
        admin_ids=tuple(int(x) for x in os.getenv("ADMIN_IDS", "").replace(" ", "").split(",") if x),
        db_path=os.getenv("DB_PATH", "pdd_bot.db"),
        channel_url=os.getenv("CHANNEL_URL", "").strip(),
        private_channel_id=_int_or_none(os.getenv("PRIVATE_CHANNEL_ID")),
        access_link=os.getenv("ACCESS_LINK", "").strip(),
        price=int(os.getenv("PRICE", "1490")),
        old_price=_int_or_none(os.getenv("OLD_PRICE")),
        manager_username=os.getenv("MANAGER_USERNAME", "").strip().lstrip("@"),
        payment_url=os.getenv("PAYMENT_URL", "").strip(),
        payment_details=os.getenv("PAYMENT_DETAILS", "").replace("\\n", "\n").strip(),
        questions_path=os.getenv("QUESTIONS_PATH", "data/questions.json"),
        followup_delay_scale=float(os.getenv("FOLLOWUP_DELAY_SCALE", "1")),
        timezone=os.getenv("TIMEZONE", "Europe/Moscow").strip(),
    )
