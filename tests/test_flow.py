"""Сквозной тест воронки: апдейты идут через настоящий Dispatcher,
а вместо Telegram API — сессия-заглушка, которая записывает запросы.

Запуск: python -m pytest -q  (или python tests/test_flow.py)
"""
import asyncio
import os
import sys
import tempfile
import time
from datetime import datetime
from itertools import count

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from aiogram import Bot, Dispatcher
from aiogram.client.session.base import BaseSession
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.methods import (
    AnswerCallbackQuery,
    AnswerPreCheckoutQuery,
    SendDocument,
    SendInvoice,
    SendMessage,
)
from aiogram.types import (
    CallbackQuery,
    Chat,
    Contact,
    Message,
    PreCheckoutQuery,
    SuccessfulPayment,
    Update,
    User,
)

from bot import content
from bot.config import Config
from bot.db import Database
from bot.followups import process_due
from bot.handlers import setup_routers
from bot.handlers.lead import normalize_phone

ADMIN_ID = 1000
_ids = count(1)


class MockSession(BaseSession):
    def __init__(self) -> None:
        super().__init__()
        self.requests: list = []

    async def make_request(self, bot, method, timeout=None):
        self.requests.append(method)
        if isinstance(method, (SendMessage, SendDocument, SendInvoice)):
            return Message(
                message_id=next(_ids),
                date=datetime.now(),
                chat=Chat(id=method.chat_id, type="private"),
                text=getattr(method, "text", None),
            )
        return True

    async def stream_content(self, *a, **kw):  # pragma: no cover
        yield b""

    async def close(self) -> None:
        pass

    def sent_texts(self, chat_id: int) -> list[str]:
        return [r.text for r in self.requests if isinstance(r, SendMessage) and r.chat_id == chat_id]

    def clear(self) -> None:
        self.requests.clear()


def make_config(db_path: str, payment_token: str = "") -> Config:
    return Config(
        bot_token="42:TEST",
        admin_ids=(ADMIN_ID,),
        db_path=db_path,
        payment_provider_token=payment_token,
        currency="RUB",
        manager_username="manager",
        access_link="https://example.com/course",
        followup_delay_scale=1,
    )


# Роутеры — модульные объекты aiogram и подключаются к диспетчеру один раз,
# поэтому диспетчер общий, а db/config передаются в каждый апдейт.
DP = Dispatcher(storage=MemoryStorage())
DP.include_router(setup_routers())


class _FeedProxy:
    def __init__(self, harness: "Harness"):
        self.h = harness

    async def feed_update(self, bot, update):
        await DP.feed_update(bot, update, db=self.h.db, config=self.h.config)


class Harness:
    def __init__(self, config: Config, db: Database):
        self.session = MockSession()
        self.bot = Bot(config.bot_token, session=self.session)
        self.dp = _FeedProxy(self)
        self.db = db
        self.config = config

    def user(self, uid: int) -> User:
        return User(id=uid, is_bot=False, first_name=f"User{uid}", username=f"user{uid}")

    def _msg(self, uid: int, **kw) -> Message:
        return Message(
            message_id=next(_ids), date=datetime.now(),
            chat=Chat(id=uid, type="private"), from_user=self.user(uid), **kw,
        )

    async def text(self, uid: int, text: str) -> None:
        entities = None
        if text.startswith("/"):
            from aiogram.types import MessageEntity
            entities = [MessageEntity(type="bot_command", offset=0, length=len(text.split()[0]))]
        msg = self._msg(uid, text=text, entities=entities)
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), message=msg))

    async def contact(self, uid: int, phone: str) -> None:
        msg = self._msg(uid, contact=Contact(phone_number=phone, first_name="X", user_id=uid))
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), message=msg))

    async def click(self, uid: int, data: str) -> None:
        cb = CallbackQuery(
            id=str(next(_ids)), from_user=self.user(uid), chat_instance="x", data=data,
            message=self._msg(uid, text="old"),
        )
        await self.dp.feed_update(self.bot, Update(update_id=next(_ids), callback_query=cb))

    def callback_answers(self) -> list[str | None]:
        return [r.text for r in self.session.requests if isinstance(r, AnswerCallbackQuery)]

    async def force_followup_due(self, uid: int) -> int:
        await self.db.update_user(uid, next_followup_at=int(time.time()) - 1)
        return await process_due(self.bot, self.db, self.config)


async def run_lead_funnel(tmp: str) -> None:
    db = Database(os.path.join(tmp, "lead.db"))
    await db.connect()
    try:
        await _lead_funnel(db)
    finally:
        await db.close()


async def _lead_funnel(db: Database) -> None:
    h = Harness(make_config(db.path), db)
    uid = 501

    # 1. /start с меткой источника
    await h.text(uid, "/start vk_ads")
    user = await db.get_user(uid)
    assert user["source"] == "vk_ads" and user["stage"] == "start"
    assert user["next_followup_at"] > time.time()
    assert "ПДД с первого раза" in h.session.sent_texts(uid)[0]

    # 2. сегмент
    await h.click(uid, "seg:retake")
    user = await db.get_user(uid)
    assert user["segment"] == "retake" and user["stage"] == "segment"

    # 3. тест: 7 правильных, 3 неправильных
    await h.click(uid, "quiz:start")
    assert (await db.get_user(uid))["stage"] == "quiz"
    for i, q in enumerate(content.QUIZ):
        answer = q.correct if i < 7 else (q.correct + 1) % len(q.options)
        await h.click(uid, f"q:{i}:{answer}")
    user = await db.get_user(uid)
    assert user["quiz_score"] == 7 and user["stage"] == "quiz_done"
    texts = h.session.sent_texts(uid)
    assert any("Ваш результат: 7 из 10" in t for t in texts)
    assert any("10 ловушек" in t for t in texts)

    # повторное нажатие на старый вопрос не ломает счёт
    h.session.clear()
    await h.click(uid, "q:0:1")
    assert "уже отвечен" in h.callback_answers()[0]
    assert (await db.get_user(uid))["quiz_score"] == 7

    # 4. оффер
    await h.click(uid, "offer:show")
    assert (await db.get_user(uid))["stage"] == "offer"
    assert any("990 ₽" in t for t in h.session.sent_texts(uid))

    # 5. дожимающая цепочка: nudge → story → discount
    h.session.clear()
    assert await h.force_followup_due(uid) == 1
    assert "прошли тест" in h.session.sent_texts(uid)[0]
    assert await h.force_followup_due(uid) == 1
    assert "История" in h.session.sent_texts(uid)[1]
    assert await h.force_followup_due(uid) == 1
    user = await db.get_user(uid)
    assert user["followup_step"] == 3 and user["discount_until"] > time.time()

    # оффер теперь со скидкой
    h.session.clear()
    await h.click(uid, "offer:show")
    assert any("<s>990 ₽</s> <b>790 ₽</b>" in t for t in h.session.sent_texts(uid))

    # 6. выбор тарифа без платёжки → форма заявки
    h.session.clear()
    await h.click(uid, "tariff:curator")
    assert "Как к вам обращаться" in h.session.sent_texts(uid)[0]
    await h.text(uid, "Иван")
    await h.text(uid, "123")  # плохой номер
    assert "Не получилось" in h.session.sent_texts(uid)[-1]
    await h.text(uid, "8 (900) 123-45-67")
    user = await db.get_user(uid)
    assert user["stage"] == "lead" and user["phone"] == "+79001234567"
    assert user["lead_name"] == "Иван" and user["tariff"] == "curator"
    assert user["next_followup_at"] is None
    admin_msgs = h.session.sent_texts(ADMIN_ID)
    assert admin_msgs and "Новая заявка" in admin_msgs[0] and "+79001234567" in admin_msgs[0]

    # после заявки дожим не отправляется, даже если время «наступило»
    h.session.clear()
    assert await h.force_followup_due(uid) == 0

    # 7. второй пользователь не прошёл тест — первый дожим зовёт в тест
    await h.text(777, "/start")
    h.session.clear()
    assert await h.force_followup_due(777) == 1
    assert "так и не прошли" in h.session.sent_texts(777)[0]

    # 8. админка
    h.session.clear()
    await h.text(ADMIN_ID, "/stats")
    stats = h.session.sent_texts(ADMIN_ID)[0]
    assert "Нажали /start: <b>2</b>" in stats and "Оставили заявку: <b>1</b>" in stats
    assert "vk_ads: 1 / 1" in stats

    await h.text(ADMIN_ID, "/export")
    assert any(isinstance(r, SendDocument) for r in h.session.requests)

    # не-админ не получает статистику
    h.session.clear()
    await h.text(uid, "/stats")
    assert h.session.sent_texts(uid) == []


async def run_payment_funnel(tmp: str) -> None:
    db = Database(os.path.join(tmp, "pay.db"))
    await db.connect()
    try:
        await _payment_funnel(db)
    finally:
        await db.close()


async def _payment_funnel(db: Database) -> None:
    h = Harness(make_config(db.path, payment_token="TEST:PROVIDER"), db)
    uid = 601

    await h.text(uid, "/start")
    await h.click(uid, "offer:show")
    h.session.clear()
    await h.click(uid, "tariff:base")
    invoices = [r for r in h.session.requests if isinstance(r, SendInvoice)]
    assert invoices and invoices[0].prices[0].amount == 99000

    pcq = PreCheckoutQuery(
        id="pcq", from_user=h.user(uid), currency="RUB", total_amount=99000, invoice_payload="tariff:base"
    )
    await h.dp.feed_update(h.bot, Update(update_id=next(_ids), pre_checkout_query=pcq))
    answers = [r for r in h.session.requests if isinstance(r, AnswerPreCheckoutQuery)]
    assert answers[-1].ok is True

    paid = h._msg(uid, successful_payment=SuccessfulPayment(
        currency="RUB", total_amount=99000, invoice_payload="tariff:base",
        telegram_payment_charge_id="t", provider_payment_charge_id="p",
    ))
    await h.dp.feed_update(h.bot, Update(update_id=next(_ids), message=paid))
    user = await db.get_user(uid)
    assert user["stage"] == "paid" and user["next_followup_at"] is None
    assert any("example.com/course" in t for t in h.session.sent_texts(uid))
    assert "Новая оплата: 990 RUB" in h.session.sent_texts(ADMIN_ID)[0]


def test_phone_normalization():
    assert normalize_phone("8 900 123-45-67") == "+79001234567"
    assert normalize_phone("+7 (900) 123 45 67") == "+79001234567"
    assert normalize_phone("9001234567") == "+79001234567"
    assert normalize_phone("12345") is None


def test_quiz_content_is_valid():
    for q in content.QUIZ:
        assert 0 <= q.correct < len(q.options)
        assert 2 <= len(q.options) <= 5


def test_lead_funnel():
    with tempfile.TemporaryDirectory() as tmp:
        asyncio.run(run_lead_funnel(tmp))


def test_payment_funnel():
    with tempfile.TemporaryDirectory() as tmp:
        asyncio.run(run_payment_funnel(tmp))


if __name__ == "__main__":
    test_phone_normalization()
    test_quiz_content_is_valid()
    test_lead_funnel()
    test_payment_funnel()
    print("OK")
