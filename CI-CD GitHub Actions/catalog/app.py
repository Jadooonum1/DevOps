"""HTTP layer for catalog-api. Books live in memory, which is enough for a CI demo."""

import os
from datetime import date

from flask import Flask, jsonify, request

from . import __version__
from .loans import due_date, is_valid_isbn13, overdue_fine

SEED_BOOKS = [
    {"isbn": "9780132350884", "title": "Clean Code", "author": "Robert C. Martin"},
    {"isbn": "9781491950357", "title": "Building Microservices", "author": "Sam Newman"},
]


def create_app() -> Flask:
    app = Flask(__name__)
    books = {b["isbn"]: dict(b) for b in SEED_BOOKS}

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/version")
    def version():
        # GIT_SHA is baked into the image by the pipeline so a running pod can be traced to a commit.
        return jsonify(version=__version__, commit=os.environ.get("GIT_SHA", "dev"))

    @app.get("/books")
    def list_books():
        return jsonify(sorted(books.values(), key=lambda b: b["title"]))

    @app.get("/books/<isbn>")
    def get_book(isbn):
        book = books.get(isbn)
        if book is None:
            return jsonify(error="book not found"), 404
        return jsonify(book)

    @app.post("/books")
    def add_book():
        data = request.get_json(silent=True) or {}
        isbn, title = data.get("isbn", ""), data.get("title", "")
        if not title or not is_valid_isbn13(isbn):
            return jsonify(error="a title and a valid ISBN-13 are required"), 400
        if isbn in books:
            return jsonify(error="book already exists"), 409
        books[isbn] = {"isbn": isbn, "title": title, "author": data.get("author", "unknown")}
        return jsonify(books[isbn]), 201

    @app.get("/loans/quote")
    def loan_quote():
        """?borrowed=YYYY-MM-DD[&returned=YYYY-MM-DD] -> due date and any fine."""
        try:
            borrowed = date.fromisoformat(request.args["borrowed"])
            returned = date.fromisoformat(request.args.get("returned", borrowed.isoformat()))
        except (KeyError, ValueError):
            return jsonify(error="borrowed (and optional returned) must be YYYY-MM-DD"), 400
        due = due_date(borrowed)
        return jsonify(due=due.isoformat(), fine=overdue_fine(due, returned))

    return app


app = create_app()
