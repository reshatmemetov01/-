from aiogram import Bot, F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import Message

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..questions import QuestionBank
from ..services import ensure_subscribed
from .funnel import send_offer

router = Router()


@router.message(F.text == content.MENU_VIDEOS)
async def videos(message: Message, state: FSMContext, bot: Bot, db: Database, config: Config,
                 user: dict) -> None:
    await state.clear()
    if not user["paid"] and not await ensure_subscribed(bot, db, config, user):
        return
    await send_offer(bot, db, config, user)  # купившим — ссылку на канал, остальным — оффер


@router.message(F.text == content.MENU_TRAINING)
async def training(message: Message, state: FSMContext, bot: Bot, db: Database, config: Config,
                   user: dict, questions: QuestionBank) -> None:
    await state.clear()
    if not await ensure_subscribed(bot, db, config, user):
        return
    if not questions.questions:
        await message.answer(content.EXAM_NO_QUESTIONS)
        return
    await message.answer(
        content.EXAM_INTRO.format(
            n=min(content.EXAM_QUESTIONS, len(questions.questions)), max_errors=content.EXAM_MAX_ERRORS
        ),
        reply_markup=keyboards.exam_start(),
    )


@router.message(F.text.in_({content.MENU_REVIEWS, content.MENU_FAQ, content.MENU_INFO}))
async def coming_soon(message: Message, state: FSMContext) -> None:
    await state.clear()
    await message.answer(content.COMING_SOON)
