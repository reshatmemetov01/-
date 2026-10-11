from aiogram import Router

from . import admin, fallback, lead, offer, quiz, start


def setup_routers() -> Router:
    root = Router()
    # admin — первым, чтобы команды админа не перехватывались; fallback — последним.
    root.include_routers(admin.router, start.router, quiz.router, offer.router, lead.router, fallback.router)
    return root
