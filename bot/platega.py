"""Клиент Platega API (https://docs.platega.io): платёжная ссылка и проверка статуса."""
from typing import Any

import aiohttp

from .gateway import FAILED, PAID, PENDING, REFUNDED, PaymentError, PaymentLink, duration_to_ts

# Статусы Platega → общие
STATUSES = {"PENDING": PENDING, "CONFIRMED": PAID, "CANCELED": FAILED, "CHARGEBACKED": REFUNDED}


class PlategaClient:
    name = "platega"
    title = "Platega"

    def __init__(self, merchant_id: str, secret: str, base_url: str = "https://app.platega.io"):
        self.merchant_id = merchant_id
        self.secret = secret
        self.base_url = base_url.rstrip("/")
        self._session: aiohttp.ClientSession | None = None

    async def _request(self, method: str, path: str, json: dict | None = None) -> dict[str, Any]:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={"X-MerchantId": self.merchant_id, "X-Secret": self.secret},
                timeout=aiohttp.ClientTimeout(total=20),
                trust_env=True,
            )
        async with self._session.request(method, self.base_url + path, json=json) as resp:
            try:
                data = await resp.json(content_type=None)
            except Exception:
                data = {}
            if resp.status >= 400:
                data = data if isinstance(data, dict) else {}
                raise PaymentError(f"Platega {resp.status} {data.get('code', '')}: {data.get('message', '')}".strip())
            return data

    async def create(self, *, order_id: str, amount: int, description: str, return_url: str,
                     user_id: int, username: str | None) -> PaymentLink:
        # Способ оплаты не задаём — покупатель выбирает на странице Platega
        data = await self._request("POST", "/v2/transaction/process", {
            "paymentDetails": {"amount": amount, "currency": "RUB"},
            "description": description,
            "return": return_url,
            "failedUrl": return_url,
            "payload": order_id,
            "orderId": order_id,
            # userId нужен антифроду Platega (Telegram ID покупателя)
            "metadata": {"userId": str(user_id), "userName": f"@{username}" if username else str(user_id)},
        })
        return PaymentLink(id=data["transactionId"], url=data["url"],
                           status=STATUSES.get(data.get("status", ""), PENDING),
                           expires_at=duration_to_ts(data.get("expiresIn"), 15 * 60))

    async def status(self, payment_id: str) -> str:
        data = await self._request("GET", f"/transaction/{payment_id}")
        return STATUSES.get(data.get("status", ""), PENDING)

    async def close(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
