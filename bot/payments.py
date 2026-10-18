"""Автоматическая оплата через Paydex: счёт на каждого клиента и проверка его статуса."""
import asyncio
import logging
import time
from datetime import datetime

from aiogram import Bot

from .config import Config
from .db import Database
from .paydex import FINAL_UNPAID, PAID, PaydexClient
from .services import grant_access

log = logging.getLogger(__name__)

CHECK_INTERVAL = 15  # секунд


def _ts(iso: str | None, default: int) -> int:
    if not iso:
        return default
    try:
        return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return default


async def get_or_create_invoice(bot: Bot, db: Database, config: Config, paydex: PaydexClient,
                                user_id: int) -> dict:
    """Возвращает действующий счёт клиента или создаёт новый. Бросает PaydexError при ошибке API."""
    existing = await db.active_invoice_for(user_id)
    if existing:
        return existing
    me = await bot.me()
    now = int(time.time())
    order_id = f"tg{user_id}-{now}"
    data = await paydex.create_invoice(
        order_id=order_id, amount=config.price, user_id=user_id,
        description=f"Доступ к видеоразборам ПДД — @{me.username}",
        success_url=f"https://t.me/{me.username}",
        expire_minutes=config.paydex_expire_minutes,
    )
    expires_at = _ts(data.get("expiresAt"), now + config.paydex_expire_minutes * 60)
    await db.add_invoice(data["id"], user_id, order_id, data["url"], data.get("status", "created"), expires_at)
    return await db.get_invoice(data["id"])


async def refresh_invoice(bot: Bot, db: Database, config: Config, paydex: PaydexClient,
                          invoice: dict) -> str:
    """Запрашивает статус в Paydex. Если оплачен — выдаёт доступ (ровно один раз). Возвращает статус."""
    data = await paydex.get_invoice(invoice["id"])
    status = data.get("status", invoice["status"])
    if status == PAID:
        # set_invoice_status вернёт True только один раз — доступ не выдастся дважды
        if await db.set_invoice_status(invoice["id"], PAID):
            await grant_access(bot, db, config, invoice["user_id"],
                               via=f"Paydex, автооплата, заказ {invoice['order_id']}")
    elif status != invoice["status"]:
        await db.set_invoice_status(invoice["id"], status)
    return status


async def check_waiting(bot: Bot, db: Database, config: Config, paydex: PaydexClient) -> int:
    """Один проход: проверяет все ожидающие счета. Возвращает число оплаченных."""
    paid = 0
    for invoice in await db.waiting_invoices():
        try:
            status = await refresh_invoice(bot, db, config, paydex, invoice)
            paid += status == PAID
            if status in FINAL_UNPAID:
                log.info("Счёт %s: %s", invoice["id"], status)
        except Exception:
            log.exception("Не удалось проверить счёт %s", invoice["id"])
        await asyncio.sleep(0.2)
    return paid


async def payments_worker(bot: Bot, db: Database, config: Config, paydex: PaydexClient) -> None:
    while True:
        try:
            await check_waiting(bot, db, config, paydex)
        except Exception:
            log.exception("Сбой в цикле проверки оплат")
        await asyncio.sleep(CHECK_INTERVAL)
