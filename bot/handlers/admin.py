import asyncio
import csv
import io
import time
from datetime import datetime

from aiogram import Bot, Router
from aiogram.filters import Command, CommandObject
from aiogram.types import BufferedInputFile, Message

from .. import content
from ..config import Config
from ..db import STAGE_TITLES, STAGES, Database

router = Router()


def is_admin(message: Message, config: Config) -> bool:
    return message.from_user is not None and message.from_user.id in config.admin_ids


@router.message(Command("stats"))
async def stats(message: Message, db: Database, config: Config) -> None:
    if not is_admin(message, config):
        return
    counts = await db.stage_counts()
    total = sum(counts.values())
    if not total:
        await message.answer("Пока нет ни одного пользователя.")
        return

    # Этап воронки = сколько людей дошло до него или дальше
    lines = ["📈 <b>Воронка</b>\n"]
    for i, stage in enumerate(STAGES):
        reached = sum(counts.get(s, 0) for s in STAGES[i:])
        pct = reached / total * 100
        lines.append(f"{STAGE_TITLES[stage]}: <b>{reached}</b> ({pct:.0f}%)")

    lines.append("\n🔗 <b>Источники</b> (всего / заявок)\n")
    for src, n, conv in await db.source_counts():
        lines.append(f"{src}: {n} / {conv}")
    await message.answer("\n".join(lines))


@router.message(Command("export"))
async def export(message: Message, db: Database, config: Config) -> None:
    if not is_admin(message, config):
        return
    leads = await db.leads()
    if not leads:
        await message.answer("Заявок пока нет.")
        return

    buf = io.StringIO()
    writer = csv.writer(buf, delimiter=";")
    writer.writerow(["Дата", "Статус", "Имя", "Телефон", "Username", "Цель", "Тест", "Тариф", "Источник"])
    for u in leads:
        tariff = content.TARIFFS_BY_ID.get(u["tariff"] or "")
        writer.writerow([
            datetime.fromtimestamp(u["updated_at"]).strftime("%d.%m.%Y %H:%M"),
            "оплата" if u["stage"] == "paid" else "заявка",
            u["lead_name"] or u["full_name"],
            u["phone"] or "",
            f"@{u['username']}" if u["username"] else "",
            content.SEGMENTS.get(u["segment"] or "", ""),
            u["quiz_score"] if u["quiz_score"] is not None else "",
            tariff.title if tariff else "",
            u["source"] or "",
        ])
    # utf-8-sig — чтобы Excel корректно открыл кириллицу
    data = buf.getvalue().encode("utf-8-sig")
    await message.answer_document(
        BufferedInputFile(data, filename=f"leads_{int(time.time())}.csv"),
        caption=f"Заявок: {len(leads)}",
    )


@router.message(Command("broadcast"))
async def broadcast(message: Message, command: CommandObject, db: Database, config: Config, bot: Bot) -> None:
    """/broadcast текст — или ответом на любое сообщение командой /broadcast"""
    if not is_admin(message, config):
        return
    source = message.reply_to_message
    if not source and not command.args:
        await message.answer(
            "Использование:\n• <code>/broadcast текст</code>\n"
            "• или ответьте командой /broadcast на сообщение (можно с фото/видео)"
        )
        return

    user_ids = await db.active_user_ids()
    await message.answer(f"Начинаю рассылку на {len(user_ids)} пользователей…")
    sent = failed = 0
    for uid in user_ids:
        try:
            if source:
                await bot.copy_message(uid, source.chat.id, source.message_id)
            else:
                await bot.send_message(uid, command.args)
            sent += 1
        except Exception:
            failed += 1
            await db.update_user(uid, blocked=1)
        await asyncio.sleep(0.05)  # лимит Telegram ~30 сообщений/сек
    await message.answer(f"✅ Рассылка завершена. Доставлено: {sent}, ошибок: {failed}")
