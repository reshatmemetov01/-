import json
import random
from html import escape

from aiogram import Bot, F, Router
from aiogram.types import CallbackQuery, FSInputFile

from .. import content, keyboards
from ..db import Database
from ..questions import Question, QuestionBank

router = Router()

CAPTION_LIMIT = 1024
# file_id уже загруженных картинок, чтобы не отправлять файл каждый раз заново
_photo_cache: dict[str, str] = {}


def question_text(q: Question, index: int, total: int) -> str:
    options = "\n".join(f"{i + 1}. {escape(a)}" for i, a in enumerate(q.answers))
    return f"<b>Вопрос {index + 1} из {total}</b>\n\n{escape(q.question)}\n\n{options}"


async def send_question(bot: Bot, chat_id: int, q: Question, index: int, total: int) -> None:
    text = question_text(q, index, total)
    markup = keyboards.exam_answers(index, len(q.answers))
    if not q.image:
        await bot.send_message(chat_id, text, reply_markup=markup)
        return

    key = str(q.image)
    photo = _photo_cache.get(key) or FSInputFile(q.image)
    if len(text) <= CAPTION_LIMIT:
        sent = await bot.send_photo(chat_id, photo, caption=text, reply_markup=markup)
    else:
        sent = await bot.send_photo(chat_id, photo)
        await bot.send_message(chat_id, text, reply_markup=markup)
    if sent.photo:
        _photo_cache[key] = sent.photo[-1].file_id


@router.callback_query(F.data == "ex:start")
async def exam_start(callback: CallbackQuery, bot: Bot, db: Database, user: dict,
                     questions: QuestionBank) -> None:
    await callback.answer()
    if not questions.questions:
        await callback.message.answer(content.EXAM_NO_QUESTIONS)
        return
    picked = random.sample(questions.questions, min(content.EXAM_QUESTIONS, len(questions.questions)))
    ids = [q.id for q in picked]
    await db.update_user(user["user_id"], exam_ids=json.dumps(ids), exam_index=0, exam_correct=0, exam_errors=0)
    await db.add_event(user["user_id"], "exam_start")
    await callback.message.edit_reply_markup(reply_markup=None)
    await send_question(bot, user["user_id"], picked[0], 0, len(ids))


@router.callback_query(F.data.regexp(r"^ex:\d+:\d+$"))
async def exam_answer(callback: CallbackQuery, bot: Bot, db: Database, user: dict,
                      questions: QuestionBank) -> None:
    _, index_s, answer_s = callback.data.split(":")
    index, answer = int(index_s), int(answer_s)
    ids = json.loads(user["exam_ids"] or "[]")
    # Защита от повторных нажатий и кнопок из старого экзамена
    if index != user["exam_index"] or index >= len(ids) or ids[index] not in questions.by_id:
        await callback.answer("На этот вопрос ты уже ответил 🙂")
        return
    await callback.answer()

    q = questions.by_id[ids[index]]
    is_correct = answer == q.correct
    correct = user["exam_correct"] + int(is_correct)
    errors = user["exam_errors"] + int(not is_correct)
    await db.update_user(user["user_id"], exam_index=index + 1, exam_correct=correct, exam_errors=errors)

    if is_correct:
        verdict = "✅ <b>Верно!</b>"
    else:
        verdict = f"❌ <b>Неверно.</b> Правильный ответ: {q.correct + 1}. {escape(q.answers[q.correct])}"
    if q.hint:
        verdict += f"\n<i>{escape(q.hint)}</i>"

    # Показываем результат в том же сообщении, а если не влезает — отдельным
    msg = callback.message
    current = msg.html_text if (msg.text or msg.caption) else ""
    new_text = f"{current}\n\n{verdict}" if current else verdict
    try:
        if msg.photo:
            if len(new_text) > CAPTION_LIMIT:
                raise ValueError("caption too long")
            await msg.edit_caption(caption=new_text, reply_markup=None)
        else:
            await msg.edit_text(new_text, reply_markup=None)
    except Exception:
        await msg.edit_reply_markup(reply_markup=None)
        await msg.answer(verdict)

    uid = user["user_id"]
    answered = index + 1
    if errors >= content.EXAM_MAX_ERRORS:
        await db.add_event(uid, "exam_fail")
        template = content.EXAM_FAIL_PAID if user["paid"] else content.EXAM_FAIL
        await bot.send_message(
            uid, template.format(errors=errors, answered=answered),
            reply_markup=keyboards.exam_finish(failed=True, paid=bool(user["paid"])),
        )
    elif answered == len(ids):
        await db.add_event(uid, "exam_pass")
        await bot.send_message(
            uid, content.EXAM_PASS.format(correct=correct, total=len(ids), errors=errors),
            reply_markup=keyboards.exam_finish(failed=False, paid=bool(user["paid"])),
        )
    else:
        await send_question(bot, uid, questions.by_id[ids[answered]], answered, len(ids))
