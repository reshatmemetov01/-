import time
from typing import Any

import aiosqlite

# Этапы воронки по порядку. Этап пользователя может только расти.
STAGES = ("start", "segment", "quiz", "quiz_done", "offer", "lead", "paid")
STAGE_TITLES = {
    "start": "Нажали /start",
    "segment": "Выбрали цель",
    "quiz": "Начали тест",
    "quiz_done": "Прошли тест",
    "offer": "Смотрели тарифы",
    "lead": "Оставили заявку",
    "paid": "Оплатили",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    user_id          INTEGER PRIMARY KEY,
    username         TEXT,
    full_name        TEXT,
    source           TEXT,
    segment          TEXT,
    stage            TEXT    NOT NULL DEFAULT 'start',
    quiz_index       INTEGER NOT NULL DEFAULT 0,
    quiz_correct     INTEGER NOT NULL DEFAULT 0,
    quiz_score       INTEGER,
    tariff           TEXT,
    lead_name        TEXT,
    phone            TEXT,
    discount_until   INTEGER,
    followup_step    INTEGER NOT NULL DEFAULT 0,
    next_followup_at INTEGER,
    blocked          INTEGER NOT NULL DEFAULT 0,
    created_at       INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_followup ON users(next_followup_at);
"""


def stage_rank(stage: str) -> int:
    return STAGES.index(stage)


class Database:
    def __init__(self, path: str):
        self.path = path
        self.conn: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        self.conn = await aiosqlite.connect(self.path)
        self.conn.row_factory = aiosqlite.Row
        await self.conn.executescript(SCHEMA)
        await self.conn.commit()

    async def close(self) -> None:
        if self.conn:
            await self.conn.close()

    async def get_user(self, user_id: int) -> dict[str, Any] | None:
        async with self.conn.execute(
            "SELECT * FROM users WHERE user_id = ?", (user_id,)
        ) as cur:
            row = await cur.fetchone()
        return dict(row) if row else None

    async def create_user_if_missing(
        self,
        user_id: int,
        username: str | None,
        full_name: str,
        source: str | None,
        first_followup_at: int,
    ) -> bool:
        """Создаёт пользователя. Возвращает True, если он новый."""
        now = int(time.time())
        cur = await self.conn.execute(
            """INSERT OR IGNORE INTO users
               (user_id, username, full_name, source, next_followup_at, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (user_id, username, full_name, source, first_followup_at, now, now),
        )
        created = cur.rowcount > 0
        if not created:
            # Пользователь вернулся: обновим имя и снимем флаг блокировки.
            await self.conn.execute(
                "UPDATE users SET username = ?, full_name = ?, blocked = 0, updated_at = ? "
                "WHERE user_id = ?",
                (username, full_name, now, user_id),
            )
        await self.conn.commit()
        return created

    async def update_user(self, user_id: int, **fields: Any) -> None:
        if not fields:
            return
        fields["updated_at"] = int(time.time())
        cols = ", ".join(f"{k} = ?" for k in fields)
        await self.conn.execute(
            f"UPDATE users SET {cols} WHERE user_id = ?", (*fields.values(), user_id)
        )
        await self.conn.commit()

    async def advance_stage(self, user_id: int, stage: str) -> None:
        user = await self.get_user(user_id)
        if user and stage_rank(stage) > stage_rank(user["stage"]):
            await self.update_user(user_id, stage=stage)

    async def due_followups(self, now: int) -> list[dict[str, Any]]:
        lead_rank_stages = tuple(s for s in STAGES if stage_rank(s) < stage_rank("lead"))
        placeholders = ",".join("?" * len(lead_rank_stages))
        async with self.conn.execute(
            f"""SELECT * FROM users
                WHERE next_followup_at IS NOT NULL AND next_followup_at <= ?
                  AND blocked = 0 AND stage IN ({placeholders})""",
            (now, *lead_rank_stages),
        ) as cur:
            return [dict(r) for r in await cur.fetchall()]

    async def stage_counts(self) -> dict[str, int]:
        async with self.conn.execute(
            "SELECT stage, COUNT(*) AS n FROM users GROUP BY stage"
        ) as cur:
            rows = await cur.fetchall()
        return {r["stage"]: r["n"] for r in rows}

    async def source_counts(self) -> list[tuple[str, int, int]]:
        """(источник, всего, заявок+оплат)"""
        async with self.conn.execute(
            """SELECT COALESCE(source, '—') AS src, COUNT(*) AS total,
                      SUM(stage IN ('lead', 'paid')) AS converted
               FROM users GROUP BY src ORDER BY total DESC"""
        ) as cur:
            return [(r["src"], r["total"], r["converted"] or 0) for r in await cur.fetchall()]

    async def leads(self) -> list[dict[str, Any]]:
        async with self.conn.execute(
            "SELECT * FROM users WHERE stage IN ('lead', 'paid') ORDER BY updated_at DESC"
        ) as cur:
            return [dict(r) for r in await cur.fetchall()]

    async def active_user_ids(self) -> list[int]:
        async with self.conn.execute("SELECT user_id FROM users WHERE blocked = 0") as cur:
            return [r["user_id"] for r in await cur.fetchall()]
