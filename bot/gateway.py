"""Общие типы для платёжных сервисов (Paydex, Platega).

Каждый клиент умеет две вещи: create() — создать платёж на одного клиента и вернуть ссылку,
status() — узнать статус платежа. Статусы приводятся к общему виду (константы ниже).
"""
import re
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

PENDING = "pending"
PAID = "paid"
FAILED = "failed"
EXPIRED = "expired"
REFUNDED = "refunded"

WAITING = {"created", PENDING}
FINAL_UNPAID = {FAILED, EXPIRED}


class PaymentError(Exception):
    pass


@dataclass
class PaymentLink:
    id: str
    url: str
    status: str
    expires_at: int


class Gateway(Protocol):
    name: str   # paydex / platega — хранится в базе у каждого счёта
    title: str  # как показывать на кнопке

    async def create(self, *, order_id: str, amount: int, description: str, return_url: str,
                     user_id: int, username: str | None) -> PaymentLink: ...

    async def status(self, payment_id: str) -> str: ...

    async def close(self) -> None: ...


def iso_to_ts(value: str | None, default: int) -> int:
    if not value:
        return default
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return default


def duration_to_ts(value: str | None, default_seconds: int) -> int:
    """'00:15:00' или '1.00:00:00' (как в .NET TimeSpan) → момент истечения."""
    now = int(time.time())
    m = re.fullmatch(r"(?:(\d+)\.)?(\d{1,2}):(\d{2}):(\d{2})(?:\.\d+)?", (value or "").strip())
    if not m:
        return now + default_seconds
    days, h, mi, s = (int(x or 0) for x in m.groups())
    return now + days * 86400 + h * 3600 + mi * 60 + s
