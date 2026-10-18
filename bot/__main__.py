import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand

from . import content
from .config import Config, load_config
from .db import Database
from .followups import followup_worker
from .handlers import setup_routers
from .middleware import UserMiddleware
from .paydex import PaydexClient
from .payments import payments_worker
from .questions import QuestionBank

log = logging.getLogger(__name__)


def build_dispatcher(db: Database, config: Config, questions: QuestionBank,
                     paydex: PaydexClient | None = None) -> Dispatcher:
    dp = Dispatcher(storage=MemoryStorage(), db=db, config=config, questions=questions, paydex=paydex)
    dp.message.outer_middleware(UserMiddleware())
    dp.callback_query.outer_middleware(UserMiddleware())
    dp.include_router(setup_routers())
    return dp


async def setup_bot_profile(bot: Bot) -> None:
    try:
        await bot.set_my_commands([BotCommand(command="start", description="Запустить бота")])
        await bot.set_my_description(content.BOT_DESCRIPTION)
        await bot.set_my_short_description(content.BOT_SHORT_DESCRIPTION)
    except Exception:
        log.exception("Не удалось обновить описание бота")


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    config = load_config()
    if not config.admin_ids:
        log.warning("ADMIN_IDS не задан — админка и уведомления о покупках работать не будут")

    db = Database(config.db_path)
    await db.connect()
    questions = QuestionBank.load(config.questions_path)

    bot = Bot(config.bot_token, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    paydex = PaydexClient(config.paydex_secret_key, config.paydex_api_url) if config.paydex_secret_key else None
    dp = build_dispatcher(db, config, questions, paydex)
    await setup_bot_profile(bot)

    workers = [asyncio.create_task(followup_worker(bot, db, config))]
    if paydex:
        log.info("Paydex: автооплата включена")
        workers.append(asyncio.create_task(payments_worker(bot, db, config, paydex)))
    try:
        await bot.delete_webhook(drop_pending_updates=True)
        await dp.start_polling(bot)
    finally:
        for w in workers:
            w.cancel()
        if paydex:
            await paydex.close()
        await db.close()
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
