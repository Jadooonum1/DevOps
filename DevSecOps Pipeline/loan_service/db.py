"""SQLite storage for loans. Every query is parameterised - never build SQL with f-strings."""

import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS loans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id TEXT NOT NULL,
    isbn TEXT NOT NULL,
    returned INTEGER NOT NULL DEFAULT 0
);
"""


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def create_loan(conn, member_id: str, isbn: str) -> int:
    cur = conn.execute("INSERT INTO loans (member_id, isbn) VALUES (?, ?)", (member_id, isbn))
    conn.commit()
    return cur.lastrowid


def loans_for_member(conn, member_id: str) -> list:
    rows = conn.execute(
        "SELECT id, isbn, returned FROM loans WHERE member_id = ? ORDER BY id", (member_id,)
    ).fetchall()
    return [{"id": r["id"], "isbn": r["isbn"], "returned": bool(r["returned"])} for r in rows]


def mark_returned(conn, loan_id: int) -> bool:
    cur = conn.execute("UPDATE loans SET returned = 1 WHERE id = ? AND returned = 0", (loan_id,))
    conn.commit()
    return cur.rowcount == 1
