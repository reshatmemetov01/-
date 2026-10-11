import os
from dataclasses import dataclass

from dotenv import load_dotenv


@dataclass(frozen=True)
class Config:
    bot_token: str
    admin_ids: tuple[int, ...]
    db_path: str
    payment_provider_token: str
    currency: str
    manager_username: str
    access_link: str
    followup_delay_scale: float


def load_config() -> Config:
    load_dotenv()

    token = os.getenv("BOT_TOKEN", "").strip()
    if not token:
        raise RuntimeError("Не задан BOT_TOKEN (см. .env.example)")

    admin_ids = tuple(
        int(x) for x in os.getenv("ADMIN_IDS", "").replace(" ", "").split(",") if x
    )

    return Config(
        bot_token=token,
        admin_ids=admin_ids,
        db_path=os.getenv("DB_PATH", "pdd_bot.db"),
        payment_provider_token=os.getenv("PAYMENT_PROVIDER_TOKEN", "").strip(),
        currency=os.getenv("CURRENCY", "RUB").strip() or "RUB",
        manager_username=os.getenv("MANAGER_USERNAME", "").strip().lstrip("@"),
        access_link=os.getenv("ACCESS_LINK", "").strip(),
        followup_delay_scale=float(os.getenv("FOLLOWUP_DELAY_SCALE", "1")),
    )
