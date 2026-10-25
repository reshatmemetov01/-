"""Автоматическая оплата (Paydex, Platega): платёж на каждого клиента и проверка его статуса."""
import asyncio
import logging
import time

from aiogram import Bot

from .config import Config
from .db import Database
from .gateway import FINAL_UNPAID, PAID, Gateway
from .services import grant_access, price_for

log = logging.getLogger(__name__)

CHECK_INTERVAL = 15  # секунд


async def get_or_create_invoice(bot: Bot, db: Database, config: Config, gateway: Gateway,
                                user_id: int, username: str | None = None) -> dict:
    """Действующий платёж клиента в этой платёжке или новый. Бросает исключение при ошибке API."""
    amount = price_for(config, user_id)
    existing = await db.active_invoice_for(user_id, gateway.name, amount)
    if existing:
        return existing
    me = await bot.me()
    order_id = f"tg{user_id}-{int(time.time())}"
    link = await gateway.create(
        order_id=order_id, amount=amount, user_id=user_id, username=username,
        description=f"Доступ к видеоразборам ПДД — @{me.username}",
        return_url=f"https://t.me/{me.username}",
    )
    await db.add_invoice(link.id, user_id, order_id, link.url, link.status, link.expires_at, gateway.name, amount)
    return await db.get_invoice(link.id)


async def refresh_invoice(bot: Bot, db: Database, config: Config, gateways: dict[str, Gateway],
                          invoice: dict) -> str:
    """Запрашивает статус. Если оплачен — выдаёт доступ (ровно один раз). Возвращает статус."""
    gateway = gateways.get(invoice["provider"])
    if gateway is None:
        return invoice["status"]
    status = await gateway.status(invoice["id"])
    if status == PAID:
        # set_invoice_status вернёт True только один раз — доступ не выдастся дважды
        if await db.set_invoice_status(invoice["id"], PAID):
            await grant_access(bot, db, config, invoice["user_id"],
                               via=f"{gateway.title}, автооплата, заказ {invoice['order_id']}")
    elif status != invoice["status"]:
        await db.set_invoice_status(invoice["id"], status)
    return status


async def check_waiting(bot: Bot, db: Database, config: Config, gateways: dict[str, Gateway]) -> int:
    """Один проход: проверяет все ожидающие платежи. Возвращает число оплаченных."""
    paid = 0
    for invoice in await db.waiting_invoices():
        try:
            status = await refresh_invoice(bot, db, config, gateways, invoice)
            paid += status == PAID
            if status in FINAL_UNPAID:
                log.info("Платёж %s (%s): %s", invoice["id"], invoice["provider"], status)
        except Exception:
            log.exception("Не удалось проверить платёж %s", invoice["id"])
        await asyncio.sleep(0.2)
    return paid


async def payments_worker(bot: Bot, db: Database, config: Config, gateways: dict[str, Gateway]) -> None:
    while True:
        try:
            await check_waiting(bot, db, config, gateways)
        except Exception:
            log.exception("Сбой в цикле проверки оплат")
        await asyncio.sleep(CHECK_INTERVAL)
