"""Клиент Paydex API v1 (https://paydex.pro/docs): создание счёта и проверка его статуса."""
import time
from typing import Any

import aiohttp

from .gateway import PENDING, PaymentError, PaymentLink, iso_to_ts

PaydexError = PaymentError  # совместимость


class PaydexClient:
    name = "paydex"
    title = "Paydex"

    def __init__(self, secret_key: str, base_url: str = "https://paydex.pro/api/v1", expire_minutes: int = 60):
        self.secret_key = secret_key
        self.base_url = base_url.rstrip("/")
        self.expire_minutes = expire_minutes
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
                raise PaymentError(f"Paydex {resp.status} {err.get('code', '')}: {err.get('message', '')}".strip())
            return data

    async def create(self, *, order_id: str, amount: int, description: str, return_url: str,
                     user_id: int, username: str | None) -> PaymentLink:
        data = await self._request("POST", "/invoices", {
            "orderId": order_id,
            "amount": f"{amount}.00",
            "description": description,
            "successUrl": return_url,
            "failUrl": return_url,
            "expire": self.expire_minutes,
            "customer": {"userId": str(user_id)},
        })
        default = int(time.time()) + self.expire_minutes * 60
        return PaymentLink(id=data["id"], url=data["url"], status=data.get("status") or PENDING,
                           expires_at=iso_to_ts(data.get("expiresAt"), default))

    async def status(self, payment_id: str) -> str:
        data = await self._request("GET", f"/invoices/{payment_id}")
        # Статусы Paydex: created, pending, paid, failed, expired, refunded, partially_refunded
        status = data.get("status") or PENDING
        return "refunded" if status == "partially_refunded" else status

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
