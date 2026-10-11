"""Разделы нижнего меню. У каждого сообщения раздела есть кнопка «Назад»."""
from aiogram import Bot, F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.types import CallbackQuery, Message

from .. import content, keyboards
from ..config import Config
from ..db import Database
from ..questions import QuestionBank
from .funnel import send_offer

router = Router()


@router.message(F.text == content.MENU_VIDEOS)
async def videos(message: Message, state: FSMContext, bot: Bot, db: Database, config: Config,
                 user: dict) -> None:
    await state.clear()
    await send_offer(bot, db, config, user, back=True)  # купившим — ссылку в группу, остальным — оффер


@router.message(F.text == content.MENU_TRAINING)
async def training(message: Message, state: FSMContext, questions: QuestionBank) -> None:
    await state.clear()
    if not questions.questions:
        await message.answer(content.EXAM_NO_QUESTIONS, reply_markup=keyboards.with_back(None))
        return
    await message.answer(
        content.EXAM_INTRO.format(
            n=min(content.EXAM_QUESTIONS, len(questions.questions)), max_errors=content.EXAM_MAX_ERRORS
        ),
        reply_markup=keyboards.with_back(keyboards.exam_start()),
    )


@router.message(F.text == content.MENU_FAQ)
async def faq(message: Message, state: FSMContext, config: Config) -> None:
    await state.clear()
    await message.answer(content.faq_text(config.manager_username), reply_markup=keyboards.with_back(None))


@router.message(F.text == content.MENU_INFO)
async def info(message: Message, state: FSMContext) -> None:
    await state.clear()
    await message.answer(content.INFO, reply_markup=keyboards.info())


@router.message(F.text == content.MENU_SUPPORT)
@router.message(Command("support"))
async def support(message: Message, state: FSMContext, config: Config) -> None:
    await state.clear()
    if not config.manager_username:
        await message.answer(content.SUPPORT_NOT_SET, reply_markup=keyboards.with_back(None))
        return
    await message.answer(content.SUPPORT, reply_markup=keyboards.with_back(keyboards.manager(config)))


async def reviews_page(db: Database, page: int) -> tuple[str, object]:
    size = content.REVIEWS_PAGE_SIZE
    reviews, total = await db.reviews(limit=size, offset=page * size)
    if not total:
        return content.REVIEWS_EMPTY, keyboards.with_back(None)
    pages = (total + size - 1) // size
    return content.reviews_text(reviews, page, pages), keyboards.reviews_nav(page, pages)


@router.message(F.text == content.MENU_REVIEWS)
async def reviews(message: Message, state: FSMContext, db: Database) -> None:
    await state.clear()
    text, markup = await reviews_page(db, 0)
    await message.answer(text, reply_markup=markup)


@router.callback_query(F.data.startswith("rev:"))
async def reviews_flip(callback: CallbackQuery, db: Database) -> None:
    await callback.answer()
    text, markup = await reviews_page(db, int(callback.data.split(":")[1]))
    await callback.message.edit_text(text, reply_markup=markup)


@router.callback_query(F.data == "menu:back")
async def back(callback: CallbackQuery, state: FSMContext) -> None:
    """«Назад» — раздел превращается в «Добро пожаловать! Выбери категорию»."""
    await state.clear()
    await callback.answer()
    try:
        await callback.message.edit_text(content.MAIN_MENU, reply_markup=None)
    except Exception:  # например, сообщение слишком старое — отправим новое
        await callback.message.answer(content.MAIN_MENU)
