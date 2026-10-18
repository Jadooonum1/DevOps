"""loan-service: FastAPI backend for the bookshelf app.

Talks to PostgreSQL with psycopg 3. Connection settings come from environment
variables so the same image works locally, in compose, and in Kubernetes.
"""
import os
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException
from psycopg.rows import dict_row
from pydantic import BaseModel, Field


def dsn() -> str:
    return (
        f"host={os.environ.get('DB_HOST', 'db')} "
        f"port={os.environ.get('DB_PORT', '5432')} "
        f"dbname={os.environ['POSTGRES_DB']} "
        f"user={os.environ['POSTGRES_USER']} "
        f"password={os.environ['POSTGRES_PASSWORD']} "
        "connect_timeout=3"
    )


def connect():
    return psycopg.connect(dsn(), row_factory=dict_row, autocommit=True)


SCHEMA = """
CREATE TABLE IF NOT EXISTS books (
    id         SERIAL PRIMARY KEY,
    title      TEXT NOT NULL,
    author     TEXT NOT NULL,
    on_loan    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Deliberately no retry loop: the compose healthcheck + depends_on condition
    # is what guarantees the database is ready (see troubleshooting/).
    with connect() as conn:
        conn.execute(SCHEMA)
    yield


# Docs live under /api/ so the nginx /api/ proxy also exposes them (http://localhost:18080/api/docs)
app = FastAPI(
    title="loan-service",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url=None,
    openapi_url="/api/openapi.json",
)


class BookIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    author: str = Field(min_length=1, max_length=200)


@app.get("/api/health")
def health():
    try:
        with connect() as conn:
            conn.execute("SELECT 1")
        return {"status": "ok", "database": "up"}
    except psycopg.OperationalError as exc:
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}") from exc


@app.get("/api/books")
def list_books():
    with connect() as conn:
        return conn.execute("SELECT id, title, author, on_loan FROM books ORDER BY id").fetchall()


@app.post("/api/books", status_code=201)
def add_book(book: BookIn):
    with connect() as conn:
        return conn.execute(
            "INSERT INTO books (title, author) VALUES (%s, %s) RETURNING id, title, author, on_loan",
            (book.title, book.author),
        ).fetchone()


def _set_loan(book_id: int, on_loan: bool):
    with connect() as conn:
        row = conn.execute(
            "UPDATE books SET on_loan = %s WHERE id = %s AND on_loan = %s "
            "RETURNING id, title, author, on_loan",
            (on_loan, book_id, not on_loan),
        ).fetchone()
        if row:
            return row
        exists = conn.execute("SELECT 1 FROM books WHERE id = %s", (book_id,)).fetchone()
    if not exists:
        raise HTTPException(status_code=404, detail="book not found")
    raise HTTPException(status_code=409, detail="book already " + ("on loan" if on_loan else "returned"))


@app.post("/api/books/{book_id}/borrow")
def borrow(book_id: int):
    return _set_loan(book_id, True)


@app.post("/api/books/{book_id}/return")
def give_back(book_id: int):
    return _set_loan(book_id, False)


@app.delete("/api/books/{book_id}", status_code=204)
def delete_book(book_id: int):
    with connect() as conn:
        deleted = conn.execute("DELETE FROM books WHERE id = %s", (book_id,)).rowcount
    if not deleted:
        raise HTTPException(status_code=404, detail="book not found")
