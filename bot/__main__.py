import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand

from .config import load_config
from .db import Database
from .followups import followup_worker
from .handlers import setup_routers


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    config = load_config()

    db = Database(config.db_path)
    await db.connect()

    bot = Bot(config.bot_token, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    dp = Dispatcher(storage=MemoryStorage(), db=db, config=config)
    dp.include_router(setup_routers())

    await bot.set_my_commands([BotCommand(command="start", description="Начать / пройти тест по ПДД")])
    worker = asyncio.create_task(followup_worker(bot, db, config))
    try:
        await bot.delete_webhook(drop_pending_updates=True)
        await dp.start_polling(bot)
    finally:
        worker.cancel()
        await db.close()
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
