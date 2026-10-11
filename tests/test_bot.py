"""Сквозные тесты бота: апдейты идут через настоящий Dispatcher, а вместо
Telegram API — сессия-заглушка, которая записывает все запросы.

Запуск: python tests/test_bot.py   (или pytest)
"""
import asyncio
import os
import sys
import tempfile
import time
from dataclasses import replace
from datetime import datetime
from itertools import count

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from aiogram import Bot
from aiogram.client.session.base import BaseSession
from aiogram.methods import (
    AnswerCallbackQuery,
    CopyMessage,
    CreateChatInviteLink,
    GetChatMember,
    SendDocument,
    SendMessage,
    SendPhoto,
    SendVideo,
)
from aiogram.types import (
    CallbackQuery,
    Chat,
    ChatInviteLink,
    ChatMemberLeft,
    ChatMemberMember,
    Message,
    MessageEntity,
    MessageId,
    PhotoSize,
    Update,
    User,
    Video,
)

from bot import content
from bot.__main__ import build_dispatcher
from bot.config import Config
from bot.db import Database
from bot.followups import process_due
from bot.questions import QuestionBank

ADMIN = 1000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUESTIONS = QuestionBank.load(os.path.join(ROOT, "data", "questions.json"))
_ids = count(1)


class MockSession(BaseSession):
    def __init__(self) -> None:
        super().__init__()
        self.requests: list = []
        self.members: set[tuple[str | int, int]] = set()

    async def make_request(self, bot, method, timeout=None):
        self.requests.append(method)
        if isinstance(method, GetChatMember):
            u = User(id=method.user_id, is_bot=False, first_name="x")
            if (method.chat_id, method.user_id) in self.members:
                return ChatMemberMember(user=u)
            return ChatMemberLeft(user=u)
        if isinstance(method, CreateChatInviteLink):
            return ChatInviteLink(
                invite_link=f"https://t.me/+invite{next(_ids)}", creator=User(id=1, is_bot=True, first_name="b"),
                creates_join_request=False, is_primary=False, is_revoked=False,
            )
        if isinstance(method, CopyMessage):
            return MessageId(message_id=next(_ids))
        if isinstance(method, (SendMessage, SendPhoto, SendVideo, SendDocument)):
            return Message(message_id=next(_ids), date=datetime.now(),
                           chat=Chat(id=method.chat_id, type="private"))
        return True

    async def stream_content(self, *a, **kw):  # pragma: no cover
        yield b""

    async def close(self) -> None:
        pass

    def texts(self, chat_id: int) -> list[str]:
        out = []
        for r in self.requests:
            if isinstance(r, SendMessage) and r.chat_id == chat_id:
                out.append(r.text)
            elif isinstance(r, (SendPhoto, SendVideo, SendDocument)) and r.chat_id == chat_id and r.caption:
                out.append(r.caption)
        return out

    def of(self, kind, chat_id: int | None = None) -> list:
        return [r for r in self.requests if isinstance(r, kind) and (chat_id is None or r.chat_id == chat_id)]

    def alerts(self) -> list[str]:
        return [r.text for r in self.of(AnswerCallbackQuery) if r.text]

    def clear(self) -> None:
        self.requests.clear()


def make_config(db_path: str, **overrides) -> Config:
    base = Config(
        bot_token="42:TEST", admin_ids=(ADMIN,), db_path=db_path,
        subscribe_channel="@eldar_pdd", subscribe_url="", private_channel_id=-100500, access_link="",
        price=1490, old_price=None, manager_username="eldar",
        payment_details="Т-Банк, +7 900 000-00-00, Эльдар", questions_path="",
        followup_delay_scale=1, timezone="Europe/Moscow",
    )
    return replace(base, **overrides)


# Роутеры aiogram — модульные объекты, поэтому диспетчер один на все тесты,
# а db/config передаются в каждый апдейт.
_DP = None


class Harness:
    def __init__(self, db: Database, config: Config):
        global _DP
        if _DP is None:
            _DP = build_dispatcher(db, config, QUESTIONS)
        self.db, self.config = db, config
        self.s = MockSession()
        self.bot = Bot(config.bot_token, session=self.s)

    async def _feed(self, **upd) -> None:
        await _DP.feed_update(self.bot, Update(update_id=next(_ids), **upd),
                              db=self.db, config=self.config, questions=QUESTIONS)

    def _user(self, uid: int) -> User:
        return User(id=uid, is_bot=False, first_name=f"U{uid}", username=f"user{uid}")

    def _msg(self, uid: int, **kw) -> Message:
        return Message(message_id=next(_ids), date=datetime.now(), chat=Chat(id=uid, type="private"),
                       from_user=self._user(uid), **kw)

    async def text(self, uid: int, text: str) -> None:
        entities = None
        if text.startswith("/"):
            entities = [MessageEntity(type="bot_command", offset=0, length=len(text.split()[0]))]
        await self._feed(message=self._msg(uid, text=text, entities=entities))

    async def photo(self, uid: int) -> None:
        await self._feed(message=self._msg(uid, photo=[PhotoSize(file_id="receipt", file_unique_id="r",
                                                                 width=1, height=1)]))

    async def video(self, uid: int, file_id: str) -> None:
        await self._feed(message=self._msg(uid, video=Video(file_id=file_id, file_unique_id=file_id,
                                                            width=1, height=1, duration=1)))

    async def click(self, uid: int, data: str) -> None:
        await self._feed(callback_query=CallbackQuery(
            id=str(next(_ids)), from_user=self._user(uid), chat_instance="x", data=data,
            message=self._msg(uid, text="old"),
        ))

    async def force_followup(self, uid: int) -> int:
        await self.db.update_user(uid, next_followup_at=int(time.time()) - 1)
        return await process_due(self.bot, self.db, self.config)


async def with_db(fn, **cfg):
    with tempfile.TemporaryDirectory() as tmp:
        db = Database(os.path.join(tmp, "bot.db"))
        await db.connect()
        try:
            await fn(Harness(db, make_config(db.path, **cfg)))
        finally:
            await db.close()


# ---------------------------------------------------------------- сценарии

async def scenario_purchase(h: Harness) -> None:
    db, s, uid = h.db, h.s, 501

    # /start с меткой источника → приветствие с кнопкой подписки
    await h.text(uid, "/start insta")
    user = await db.get_user(uid)
    assert user["source"] == "insta" and not user["subscribed"] and user["next_followup_at"]
    assert "Эльдар" not in s.texts(uid)[0] and content.SUBSCRIBE_PROMPT in s.texts(uid)[0]

    # не подписан → не пускаем
    await h.click(uid, "sub:check")
    assert "Не вижу подписки" in s.alerts()[-1]
    assert not (await db.get_user(uid))["subscribed"]

    # подписался → меню + «о себе»
    s.members.add(("@eldar_pdd", uid))
    s.clear()
    await h.click(uid, "sub:check")
    assert (await db.get_user(uid))["subscribed"]
    texts = s.texts(uid)
    assert content.SUBSCRIBED_OK in texts and any("Меня зовут Эльдар" in t for t in texts)
    assert any("Чат с учениками и поддержка" in t for t in texts)

    # «Показать» без видео → только текст
    s.clear()
    await h.click(uid, "f:show")
    assert any("Вот как это выглядит" in t for t in s.texts(uid)) and not s.of(SendVideo)

    # админ загружает видео-показ и бесплатный разбор
    await h.text(ADMIN, "/admin")
    await h.click(ADMIN, "adm:m_demo")
    await h.video(ADMIN, "demo_vid")
    await h.click(ADMIN, "adm:m_free")
    await h.video(ADMIN, "free_vid")
    assert (await db.get_setting("demo_media"))["file_id"] == "demo_vid"
    assert [m["file_id"] for m in await db.get_setting("free_media")] == ["free_vid"]

    s.clear()
    await h.click(uid, "f:show")
    assert s.of(SendVideo, uid)[0].video == "demo_vid"
    await h.click(uid, "f:free")
    assert s.of(SendVideo, uid)[1].video == "free_vid"
    assert any("Вот так разобраны" in t for t in s.texts(uid))

    # оффер → цепочка «не оплатил»
    s.clear()
    await h.click(uid, "f:offer")
    assert any("<b>Стоимость:</b> 1490₽" in t for t in s.texts(uid))
    s.clear()
    assert await h.force_followup(uid) == 1
    assert "открыл оплату" in s.texts(uid)[0]

    # промокод → не найден
    s.clear()
    await h.click(uid, "pay:promo")
    await h.text(uid, "SALE")
    assert content.PROMO_NOT_FOUND in s.texts(uid)

    # оплата по СБП: реквизиты → «я оплатил» → чек
    s.clear()
    await h.click(uid, "pay:sbp")
    assert any("Т-Банк" in t for t in s.texts(uid))
    await h.click(uid, "pay:sent")
    await h.text(uid, "оплатил")
    assert content.RECEIPT_NEED_PHOTO in s.texts(uid)
    await h.photo(uid)
    assert content.RECEIPT_RECEIVED in s.texts(uid)
    admin_card = s.of(SendPhoto, ADMIN)[0]
    assert admin_card.photo == "receipt" and "Проверь оплату #1" in admin_card.caption

    # админ подтверждает → доступ и одноразовая ссылка
    s.clear()
    await h.click(ADMIN, "adm:pay_ok:1")
    user = await db.get_user(uid)
    assert user["paid"] and user["next_followup_at"] is None
    link_req = s.of(CreateChatInviteLink)[0]
    assert link_req.chat_id == -100500 and link_req.member_limit == 1
    assert any("персональная ссылка" in t and "t.me/+invite" in t for t in s.texts(uid))
    assert any("Новая покупка — 1490 ₽" in t for t in s.texts(ADMIN))

    # повторное нажатие не выдаёт доступ дважды
    s.clear()
    await h.click(ADMIN, "adm:pay_ok:1")
    assert "уже обработана" in s.alerts()[-1] and not s.of(CreateChatInviteLink)

    # купившему дожим не приходит
    assert await h.force_followup(uid) == 0

    # «Видео разборы» купившему → ссылка; если уже в канале — без новой ссылки
    s.clear()
    await h.text(uid, content.MENU_VIDEOS)
    assert any("Твоя ссылка" in t for t in s.texts(uid))
    s.members.add((-100500, uid))
    s.clear()
    await h.text(uid, content.MENU_VIDEOS)
    assert content.ACCESS_ALREADY_MEMBER in s.texts(uid) and not s.of(CreateChatInviteLink)

    # второй пользователь дошёл до оплаты и не купил
    s.members.add(("@eldar_pdd", 777))
    await h.text(777, "/start")
    await h.click(777, "sub:check")
    await h.click(777, "f:offer")

    # статистика и списки
    s.clear()
    await h.click(ADMIN, "adm:stats:all")
    stats = [r.text for r in s.requests if hasattr(r, "text") and r.text and "Статистика" in r.text][0]
    assert "Купили: <b>1</b>" in stats and "Выручка: <b>1 490 ₽</b>" in stats
    assert "дошли до оплаты и не купили (всего): <b>1</b>" in stats
    assert "insta: 1 / 1" in stats

    s.clear()
    await h.click(ADMIN, "adm:list:checkout:0")
    listing = [r.text for r in s.requests if hasattr(r, "text") and r.text and "не купили" in r.text][0]
    assert "user777" in listing and "user501" not in listing

    # рассылка тем, кто не купил
    s.clear()
    await h.click(ADMIN, "adm:bc")
    await h.click(ADMIN, "adm:bc_to:unpaid")
    await h.text(ADMIN, "Скидка только сегодня!")
    await h.click(ADMIN, "adm:bc_go")
    await asyncio.sleep(0.5)
    targets = {r.chat_id for r in s.of(CopyMessage)}
    assert 777 in targets and uid not in targets
    assert any("Рассылка завершена" in t for t in s.texts(ADMIN))

    # ручная выдача доступа по @username
    s.clear()
    await h.click(ADMIN, "adm:grant")
    await h.text(ADMIN, "@user777")
    assert (await db.get_user(777))["paid"]
    assert any("Доступ выдан" in t for t in s.texts(ADMIN))

    # не-админ не попадает в админку
    s.clear()
    await h.text(uid, "/admin")
    assert s.texts(uid) == [content.FALLBACK]


async def scenario_reject(h: Harness) -> None:
    db, s, uid = h.db, h.s, 601
    s.members.add(("@eldar_pdd", uid))
    await h.text(uid, "/start")
    await h.click(uid, "sub:check")
    await h.click(uid, "f:offer")
    await h.click(uid, "pay:sbp")
    await h.click(uid, "pay:sent")
    await h.photo(uid)
    s.clear()
    await h.click(ADMIN, "adm:pay_no:1")
    assert not (await db.get_user(uid))["paid"]
    assert any("Не нашёл твою оплату" in t for t in s.texts(uid))


async def scenario_browse_followups(h: Harness) -> None:
    s, uid = h.s, 701
    await h.text(uid, "/start")
    # первое сообщение — через 6 часов, не раньше
    first_at = (await h.db.get_user(uid))["next_followup_at"]
    assert first_at - time.time() >= 6 * 3600 - 5
    assert await process_due(h.bot, h.db, h.config) == 0

    s.clear()
    total = 0
    while await h.force_followup(uid):
        total += 1
        assert total < 50
    texts = s.texts(uid)
    # не подписан → сначала просьба подписаться, дальше все сообщения по порядку, без повторов
    assert "так и не подписался" in texts[0]
    assert "Почему зубрёжка не работает" in texts[1]
    assert total == 1 + len(content.FOLLOWUP_ORDER) == len(set(texts))
    assert "последнее сообщение" in texts[-1]
    assert (await h.db.get_user(uid))["next_followup_at"] is None


def test_quiet_hours():
    from zoneinfo import ZoneInfo
    from bot.followups import next_followup_time
    cfg = make_config("x")
    tz = ZoneInfo("Europe/Moscow")
    at = lambda h, m=0: int(datetime(2026, 10, 12, h, m, tzinfo=tz).timestamp())
    local = lambda ts: datetime.fromtimestamp(ts, tz)
    assert local(next_followup_time(at(10), cfg)).hour == 16           # днём — ровно +6 ч
    night = local(next_followup_time(at(18), cfg))                     # 00:00 → утро
    assert (night.day, night.hour, night.minute) == (13, 9, 0)
    early = local(next_followup_time(at(1), cfg))                      # 07:00 → 09:00
    assert (early.day, early.hour) == (12, 9)


async def scenario_exam(h: Harness) -> None:
    db, s, uid = h.db, h.s, 888
    # канал для подписки не настроен → сразу «о себе»
    await h.text(uid, "/start")
    assert any("Меня зовут Эльдар" in t for t in s.texts(uid))

    s.clear()
    await h.text(uid, content.MENU_TRAINING)
    assert any("Экзамен" in t for t in s.texts(uid))

    # 3 ошибки → экзамен окончен, предлагаем доступ
    await h.click(uid, "ex:start")
    for i in range(3):
        user = await db.get_user(uid)
        q = QUESTIONS.by_id[__import__("json").loads(user["exam_ids"])[i]]
        await h.click(uid, f"ex:{i}:{(q.correct + 1) % len(q.answers)}")
    fail = [t for t in s.texts(uid) if "Экзамен не сдан" in t]
    assert fail and "3 ошибки на 3 вопросах" in fail[0]
    assert await db.add_event(uid, "exam_fail") is False  # событие уже записано

    # повторное нажатие после окончания
    s.clear()
    await h.click(uid, "ex:0:0")
    assert "уже ответил" in s.alerts()[-1]

    # без ошибок → короткая похвала
    s.clear()
    await h.click(uid, "ex:start")
    import json
    ids = json.loads((await db.get_user(uid))["exam_ids"])
    for i, qid in enumerate(ids):
        await h.click(uid, f"ex:{i}:{QUESTIONS.by_id[qid].correct}")
    assert any(f"Экзамен сдан!</b> {len(ids)} из {len(ids)}" in t for t in s.texts(uid))


def test_purchase():
    asyncio.run(with_db(scenario_purchase))


def test_reject():
    asyncio.run(with_db(scenario_reject))


def test_browse_followups():
    asyncio.run(with_db(scenario_browse_followups))


def test_exam():
    asyncio.run(with_db(scenario_exam, subscribe_channel=""))


if __name__ == "__main__":
    test_purchase()
    test_reject()
    test_browse_followups()
    test_quiet_hours()
    test_exam()
    print("OK")
