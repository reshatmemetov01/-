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


@router.message(F.text == content.MENU_REVIEWS)
async def reviews(message: Message, state: FSMContext) -> None:
    await state.clear()
    await message.answer(content.COMING_SOON, reply_markup=keyboards.with_back(None))


@router.callback_query(F.data == "menu:back")
async def back(callback: CallbackQuery, state: FSMContext) -> None:
    """«Назад» — закрываем раздел, пользователь возвращается к нижнему меню."""
    await state.clear()
    await callback.answer()
    try:
        await callback.message.delete()
    except Exception:  # сообщение старше 48 часов удалить нельзя — просто убираем кнопки
        await callback.message.edit_reply_markup(reply_markup=None)
