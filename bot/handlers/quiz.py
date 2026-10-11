import asyncio

from aiogram import Bot, F, Router
from aiogram.types import CallbackQuery

from .. import content, keyboards
from ..db import Database

router = Router()


def question_text(index: int) -> str:
    q = content.QUIZ[index]
    options = "\n".join(f"{i + 1}. {opt}" for i, opt in enumerate(q.options))
    return f"<b>Вопрос {index + 1} из {len(content.QUIZ)}</b>\n\n{q.text}\n\n{options}"


@router.callback_query(F.data == "quiz:start")
async def quiz_start(callback: CallbackQuery, db: Database) -> None:
    user_id = callback.from_user.id
    if not await db.get_user(user_id):
        await callback.answer("Нажмите /start", show_alert=True)
        return
    await db.update_user(user_id, quiz_index=0, quiz_correct=0)
    await db.advance_stage(user_id, "quiz")

    await callback.message.edit_reply_markup(reply_markup=None)
    await callback.message.answer(question_text(0), reply_markup=keyboards.quiz_options(0, content.QUIZ[0]))
    await callback.answer()


@router.callback_query(F.data.startswith("q:"))
async def quiz_answer(callback: CallbackQuery, db: Database, bot: Bot) -> None:
    user_id = callback.from_user.id
    _, idx_s, ans_s = callback.data.split(":")
    index, answer = int(idx_s), int(ans_s)

    user = await db.get_user(user_id)
    # Защита от повторных нажатий и старых сообщений с кнопками
    if not user or user["quiz_index"] != index or index >= len(content.QUIZ):
        await callback.answer("Этот вопрос уже отвечен 🙂")
        return

    q = content.QUIZ[index]
    is_correct = answer == q.correct
    correct_total = user["quiz_correct"] + int(is_correct)
    next_index = index + 1
    await db.update_user(user_id, quiz_index=next_index, quiz_correct=correct_total)

    mark = "✅ Верно!" if is_correct else f"❌ Неверно. Правильный ответ: <b>{q.options[q.correct]}</b>"
    await callback.message.edit_text(
        f"{question_text(index)}\n\nВаш ответ: {q.options[answer]}\n\n{mark}\n<i>{q.explanation}</i>",
        reply_markup=None,
    )
    await callback.answer()

    if next_index < len(content.QUIZ):
        await callback.message.answer(
            question_text(next_index),
            reply_markup=keyboards.quiz_options(next_index, content.QUIZ[next_index]),
        )
        return

    # Тест пройден
    await db.update_user(user_id, quiz_score=correct_total)
    await db.advance_stage(user_id, "quiz_done")
    await bot.send_chat_action(user_id, "typing")
    await asyncio.sleep(1)
    await callback.message.answer(content.quiz_result_text(correct_total, len(content.QUIZ)))
    await asyncio.sleep(1)
    await callback.message.answer(content.GIFT_CHECKLIST, reply_markup=keyboards.after_quiz())
