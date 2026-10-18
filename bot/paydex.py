"""Клиент Paydex API v1 (https://paydex.pro/docs): создание счёта и проверка его статуса."""
import logging
from typing import Any

import aiohttp

log = logging.getLogger(__name__)

PAID = "paid"
FINAL_UNPAID = {"failed", "expired"}
WAITING = {"created", "pending"}


class PaydexError(Exception):
    pass


class PaydexClient:
    def __init__(self, secret_key: str, base_url: str = "https://paydex.pro/api/v1"):
        self.secret_key = secret_key
        self.base_url = base_url.rstrip("/")
        self._session: aiohttp.ClientSession | None = None

    async def _request(self, method: str, path: str, json: dict | None = None) -> dict[str, Any]:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={"Authorization": f"Bearer {self.secret_key}"},
                timeout=aiohttp.ClientTimeout(total=20),
                trust_env=True,
            )
        async with self._session.request(method, self.base_url + path, json=json) as resp:
            try:
                data = await resp.json(content_type=None)
            except Exception:
                data = {}
            if resp.status >= 400:
                err = (data or {}).get("error", {})
                raise PaydexError(f"{resp.status} {err.get('code', '')}: {err.get('message', '')}".strip())
            return data

    async def create_invoice(self, *, order_id: str, amount: int, description: str, success_url: str,
                             expire_minutes: int, user_id: int) -> dict[str, Any]:
        return await self._request("POST", "/invoices", {
            "orderId": order_id,
            "amount": f"{amount}.00",
            "description": description,
            "successUrl": success_url,
            "failUrl": success_url,
            "expire": expire_minutes,
            "customer": {"userId": str(user_id)},
        })

    async def get_invoice(self, invoice_id: str) -> dict[str, Any]:
        return await self._request("GET", f"/invoices/{invoice_id}")

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
