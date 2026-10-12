"""Сквозные тесты бота: апдейты идут через настоящий Dispatcher, а вместо
Telegram API — сессия-заглушка, которая записывает все запросы.

Запуск: python tests/test_bot.py   (или pytest)
"""
import asyncio
import re
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
    EditMessageText,
    ExportChatInviteLink,
    GetChat,
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
    ChatFullInfo,
    ChatMemberAdministrator,
    ChatMemberUpdated,
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
        if isinstance(method, GetChatMember) and method.user_id == bot.id:
            return admin_member(bot.id)
        if isinstance(method, GetChat):
            username = "eldar_channel" if method.chat_id == -100900 else None
            return ChatFullInfo(id=method.chat_id, type="supergroup", title=f"Chat {method.chat_id}",
                                username=username, accent_color_id=0, max_reaction_count=0)
        if isinstance(method, ExportChatInviteLink):
            return "https://t.me/+exported"
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


def admin_member(user_id: int) -> ChatMemberAdministrator:
    flags = dict.fromkeys([
        "can_be_edited", "is_anonymous", "can_manage_chat", "can_delete_messages", "can_manage_video_chats",
        "can_restrict_members", "can_promote_members", "can_change_info", "can_post_stories",
        "can_edit_stories", "can_delete_stories",
    ], False)
    return ChatMemberAdministrator(user=User(id=user_id, is_bot=True, first_name="bot"),
                                   can_invite_users=True, **flags)


def make_config(db_path: str, **overrides) -> Config:
    base = Config(
        bot_token="42:TEST", admin_ids=(ADMIN,), db_path=db_path,
        channel_url="https://t.me/+channel", private_channel_id=-100500, access_link="",
        price=1490, old_price=None, manager_username="eldar", payment_url="",
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

    # /start с меткой источника → приветствие + необязательный канал: «Подписаться» и «Продолжить»
    await h.text(uid, "/start insta")
    user = await db.get_user(uid)
    assert user["source"] == "insta" and user["next_followup_at"]
    welcome = s.of(SendMessage, uid)[0]
    assert "не обязательна" in welcome.text and "Подписка есть" not in welcome.text
    buttons = [b for row in welcome.reply_markup.inline_keyboard for b in row]
    assert buttons[0].url == "https://t.me/+channel" and buttons[1].callback_data == "go:continue"

    # «Продолжить» — без всякой проверки подписки → меню + «о себе»
    s.clear()
    await h.click(uid, "go:continue")
    assert not s.of(GetChatMember)
    texts = s.texts(uid)
    assert content.MENU_HINT in texts and any("Меня зовут Эльдар" in t for t in texts)
    assert any("Чат с учениками и поддержка" in t for t in texts)

    # «Показать» без видео → только текст
    s.clear()
    await h.click(uid, "f:show")
    assert any("Вот как это выглядит" in t for t in s.texts(uid)) and not s.of(SendVideo)

    # админ загружает видео-показ
    await h.text(ADMIN, "/admin")
    await h.click(ADMIN, "adm:m_demo")
    await h.video(ADMIN, "demo_vid")
    assert (await db.get_setting("demo_media"))["file_id"] == "demo_vid"

    s.clear()
    await h.click(uid, "f:show")
    show_msg = s.of(SendVideo, uid)[0]
    assert show_msg.video == "demo_vid"
    show_buttons = [b.text for row in show_msg.reply_markup.inline_keyboard for b in row]
    assert show_buttons == ["👑 ПОЛУЧИТЬ ДОСТУП"]  # бесплатных разборов больше нет

    # оффер: юзернейм в тексте + кнопка поддержки
    s.clear()
    await h.click(uid, "f:offer")
    offer_msg = [r for r in s.of(SendMessage, uid) if "<b>Стоимость:</b> 1490₽" in r.text][0]
    assert "@eldar" in offer_msg.text
    assert content.AGREEMENT_URL in offer_msg.text and content.PRIVACY_URL in offer_msg.text
    assert offer_msg.disable_web_page_preview
    urls = [b.url for row in offer_msg.reply_markup.inline_keyboard for b in row if b.url]
    assert urls == ["https://t.me/eldar"]
    s.clear()
    assert await h.force_followup(uid) == 1
    checkout_msg = s.of(SendMessage, uid)[0]
    assert "открыл оплату" in checkout_msg.text
    assert any(b.url == "https://t.me/eldar" for row in checkout_msg.reply_markup.inline_keyboard for b in row)

    # кнопка «Поддержка» в меню
    s.clear()
    await h.text(uid, content.MENU_SUPPORT)
    support_msg = s.of(SendMessage, uid)[0]
    assert support_msg.reply_markup.inline_keyboard[0][0].url == "https://t.me/eldar"

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
    assert content.PAYMENT_CHECKING in s.texts(uid)
    admin_card = [r for r in s.of(SendMessage, ADMIN) if "Оплата на проверку #1" in r.text][0]
    assert "@user501" in admin_card.text and "1490 ₽" in admin_card.text
    assert re.search(r"\d\d\.\d\d\.\d{4} \d\d:\d\d", admin_card.text)  # дата и время
    buttons = [b.callback_data for b in admin_card.reply_markup.inline_keyboard[0]]
    assert buttons == ["adm:pay_ok:1", "adm:pay_no:1"]
    # повторное «Я оплатил» не создаёт вторую заявку
    s.clear()
    await h.click(uid, "pay:sent")
    assert content.PAYMENT_ALREADY_CHECKING in s.texts(uid) and not s.texts(ADMIN)

    # админ подтверждает → доступ и одноразовая ссылка
    s.clear()
    await h.click(ADMIN, "adm:pay_ok:1")
    user = await db.get_user(uid)
    assert user["paid"] and user["next_followup_at"] is None
    link_req = s.of(CreateChatInviteLink)[0]
    assert link_req.chat_id == -100500 and link_req.member_limit == 1
    assert any("СПАСИБО ЗА ПОКУПКУ" in t and "t.me/+invite" in t for t in s.texts(uid))
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
    await h.text(777, "/start")
    await h.click(777, "go:continue")
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


async def scenario_payment_link(h: Harness) -> None:
    db, s, uid = h.db, h.s, 620
    await h.text(uid, "/start")
    s.clear()
    await h.click(uid, "f:offer")
    rows = [r for r in s.of(SendMessage, uid) if "Стоимость" in r.text][0].reply_markup.inline_keyboard
    assert rows[0][0].text == "💳 Оплатить по СБП" and rows[0][0].callback_data == "pay:sbp"
    # отдельное меню оплаты: «Оплатить» (ссылка) и «Я оплатил»
    s.clear()
    await h.click(uid, "pay:sbp")
    menu = s.of(SendMessage, uid)[0]
    assert "Оплата по СБП" in menu.text and "1490 ₽" in menu.text
    rows = menu.reply_markup.inline_keyboard
    assert rows[0][0].text == "💳 Оплатить" and rows[0][0].url == "https://paydex.pro/pay/link-abc"
    assert rows[1][0].callback_data == "pay:sent" and rows[2][0].callback_data == "f:offer"
    await h.click(uid, "pay:sent")
    assert any("Оплата на проверку #1" in t for t in s.texts(ADMIN))
    await h.click(ADMIN, "adm:pay_ok:1")
    assert (await db.get_user(uid))["paid"]
    assert any("СПАСИБО ЗА ПОКУПКУ" in t for t in s.texts(uid))


async def scenario_reject(h: Harness) -> None:
    db, s, uid = h.db, h.s, 601
    await h.text(uid, "/start")
    await h.click(uid, "go:continue")
    await h.click(uid, "f:offer")
    await h.click(uid, "pay:sbp")
    await h.click(uid, "pay:sent")
    s.clear()
    await h.click(ADMIN, "adm:pay_no:1")
    assert not (await db.get_user(uid))["paid"]
    assert any("Платёж не найден" in t and "техподдержку" in t and "@eldar" in t for t in s.texts(uid))
    # после отклонения можно снова нажать «Я оплатил»
    s.clear()
    await h.click(uid, "pay:sent")
    assert content.PAYMENT_CHECKING in s.texts(uid)


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
    # все сообщения по порядку, без повторов и без напоминаний про подписку
    assert "Почему зубрёжка не работает" in texts[0]
    assert not any("подписал" in t for t in texts)
    assert total == len(content.FOLLOWUP_ORDER) == len(set(texts))
    assert "последнее сообщение" in texts[-1]
    assert (await h.db.get_user(uid))["next_followup_at"] is None

    # админу напоминания не приходят
    await h.text(ADMIN, "/start")
    s.clear()
    assert await h.force_followup(ADMIN) == 0
    assert s.texts(ADMIN) == [] and (await h.db.get_user(ADMIN))["next_followup_at"] is None


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


async def scenario_chat_setup(h: Harness) -> None:
    """Бота добавили админом в группу → админ выбирает роль чата кнопкой."""
    db, s = h.db, h.s

    async def added_to(chat_id: int) -> None:
        await h._feed(my_chat_member=ChatMemberUpdated(
            chat=Chat(id=chat_id, type="supergroup", title="ПДД | Правила"),
            from_user=h._user(ADMIN), date=datetime.now(),
            old_chat_member=ChatMemberLeft(user=User(id=42, is_bot=True, first_name="b")),
            new_chat_member=admin_member(42),
        ))

    await added_to(-100777)
    question = [r for r in s.of(SendMessage, ADMIN) if "Меня сделали админом" in r.text][0]
    assert "ПДД | Правила" in question.text
    buttons = [b.callback_data for row in question.reply_markup.inline_keyboard for b in row]
    assert "setchat:private:-100777" in buttons

    await h.click(ADMIN, "setchat:private:-100777")
    assert (await db.get_setting("private_chat"))["id"] == -100777

    await added_to(-100900)
    await h.click(ADMIN, "setchat:channel:-100900")
    assert (await db.get_setting("channel"))["url"] == "https://t.me/eldar_channel"

    # новый пользователь видит кнопку «Подписаться» на выбранный канал
    s.clear()
    await h.text(901, "/start")
    welcome = s.of(SendMessage, 901)[0]
    assert welcome.reply_markup.inline_keyboard[0][0].url == "https://t.me/eldar_channel"
    await h.click(901, "go:continue")

    # после выдачи доступа ссылка создаётся в выбранной группе
    s.clear()
    await h.click(ADMIN, "adm:grant")
    await h.text(ADMIN, "901")
    assert s.of(CreateChatInviteLink)[0].chat_id == -100777

    # канал можно убрать из приветствия
    await h.click(ADMIN, "setchat:channel_off:0")
    s.clear()
    await h.text(902, "/start")
    assert any("Меня зовут Эльдар" in t for t in s.texts(902))


async def scenario_menu(h: Harness) -> None:
    s, uid = h.s, 950
    await h.text(uid, "/start")
    await h.click(uid, "go:continue")

    def last_markup_rows():
        return s.of(SendMessage, uid)[-1].reply_markup.inline_keyboard

    def is_back(row):
        return row[0].callback_data == "menu:back" and row[0].text == content.BACK

    # у каждого раздела нижнего меню последняя кнопка — «Назад»
    for item in (content.MENU_VIDEOS, content.MENU_TRAINING, content.MENU_REVIEWS,
                 content.MENU_FAQ, content.MENU_INFO, content.MENU_SUPPORT):
        s.clear()
        await h.text(uid, item)
        assert is_back(last_markup_rows()[-1]), item

    # «Видео разборы» — оффер с кнопками оплаты и «Назад»
    s.clear()
    await h.text(uid, content.MENU_VIDEOS)
    rows = last_markup_rows()
    assert rows[0][0].callback_data == "pay:sbp" and is_back(rows[-1])

    # «Частые вопросы» — с юзернеймом поддержки
    s.clear()
    await h.text(uid, content.MENU_FAQ)
    faq = s.of(SendMessage, uid)[0].text
    assert "Частые вопросы" in faq and "@eldar" in faq and "pddAndrey" not in faq

    # «Информация» — Эльдар, ссылки на документы
    s.clear()
    await h.text(uid, content.MENU_INFO)
    msg = s.of(SendMessage, uid)[0]
    assert "Меня зовут Эльдар" in msg.text and "Яковлев" not in msg.text
    urls = [r[0].url for r in msg.reply_markup.inline_keyboard[:2]]
    assert urls == [content.AGREEMENT_URL, content.PRIVACY_URL]

    # «Назад» не удаляет сообщение, а превращает его в «Добро пожаловать!»
    s.clear()
    await h.click(uid, "menu:back")
    edits = [r for r in s.requests if isinstance(r, EditMessageText)]
    assert edits and edits[0].text == content.MAIN_MENU and edits[0].reply_markup is None

    # отзывы: пусто → админ добавляет → пользователь видит → админ удаляет
    s.clear()
    await h.text(uid, content.MENU_REVIEWS)
    assert s.texts(uid)[0] == content.REVIEWS_EMPTY
    for i in range(7):
        await h.click(ADMIN, "adm:rev_add")
        await h.text(ADMIN, f"Сдал с первого раза <{i}>")
        await h.text(ADMIN, f"@student{i}")
    s.clear()
    await h.text(uid, content.MENU_REVIEWS)
    page1 = s.of(SendMessage, uid)[0]
    assert "@student6" in page1.text and "&lt;6&gt;" in page1.text and "(стр. 1/2)" in page1.text
    assert page1.reply_markup.inline_keyboard[0][0].callback_data == "rev:1"
    s.clear()
    await h.click(uid, "rev:1")
    page2 = [r for r in s.requests if isinstance(r, EditMessageText)][0]
    assert "@student0" in page2.text and "@student6" not in page2.text
    await h.click(ADMIN, "adm:rev_del:1")
    rows, total = await h.db.reviews()
    assert total == 6 and all(r["id"] != 1 for r in rows)

    # оффер из воронки (не из меню) — без «Назад»
    s.clear()
    await h.click(uid, "f:offer")
    assert not is_back(last_markup_rows()[-1])


async def scenario_tickets(h: Harness) -> None:
    import json
    db, s, uid = h.db, h.s, 960
    await h.text(uid, "/start")

    def questions_sent():
        return [t for t in s.texts(uid) if t.startswith("<b>Вопрос ")]

    # список билетов: только те, что есть в базе
    s.clear()
    await h.click(uid, "tk:list")
    grid = s.of(SendMessage, uid)[0].reply_markup.inline_keyboard
    numbers = [b.callback_data for row in grid for b in row if b.callback_data.startswith("tk:")]
    assert numbers == [f"tk:{n}" for n in QUESTIONS.ticket_numbers()]

    # билет 3: вопросы по порядку, 3 ошибки не прерывают, в конце итог и оффер
    s.clear()
    await h.click(uid, "tk:3")
    ticket = QUESTIONS.ticket(3)
    for i, q in enumerate(ticket):
        assert json.loads((await db.get_user(uid))["exam_ids"])[i] == q.id
        answer = q.correct if i >= 3 else (q.correct + 1) % len(q.answers)
        await h.click(uid, f"ex:{i}:{answer}")
    assert len(questions_sent()) == 20 and "Вопрос 1 из 20" in questions_sent()[0]
    result = [r for r in s.of(SendMessage, uid) if "Билет 3 пройден" in r.text][0]
    assert "17 из 20" in result.text and "ошибок: 3" in result.text
    assert result.reply_markup.inline_keyboard[0][0].callback_data == "f:offer"

    # картинки из билета отправляются фото
    assert s.of(SendPhoto, uid)

    # ссылка из поста в группе: /start ticket_4 сразу запускает билет 4
    s.clear()
    await h.text(uid, "/start ticket_4")
    first = QUESTIONS.ticket(4)[0]
    assert json.loads((await db.get_user(uid))["exam_ids"])[0] == first.id
    assert (await db.get_user(uid))["exam_mode"] == "ticket:4"

    # билета нет в базе
    s.clear()
    await h.text(uid, "/start ticket_39")
    assert content.TICKET_NOT_FOUND in s.texts(uid)


async def scenario_exam(h: Harness) -> None:
    db, s, uid = h.db, h.s, 888
    # канал не задан → сразу «о себе»
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


def test_payment_link():
    asyncio.run(with_db(scenario_payment_link, payment_url="https://paydex.pro/pay/link-abc"))


def test_reject():
    asyncio.run(with_db(scenario_reject))


def test_browse_followups():
    asyncio.run(with_db(scenario_browse_followups))


def test_chat_setup():
    asyncio.run(with_db(scenario_chat_setup, channel_url="", private_channel_id=None))


def test_menu():
    asyncio.run(with_db(scenario_menu))


def test_tickets():
    asyncio.run(with_db(scenario_tickets, channel_url=""))


def test_exam():
    asyncio.run(with_db(scenario_exam, channel_url=""))


if __name__ == "__main__":
    test_purchase()
    test_payment_link()
    test_reject()
    test_browse_followups()
    test_quiet_hours()
    test_chat_setup()
    test_menu()
    test_tickets()
    test_exam()
    print("OK")
