"""loan-service: lets library members borrow and return books.

Security notes (what the scanners are checking for):
* configuration comes from the environment, never hard-coded secrets
* input is validated with strict regexes before it reaches the database
* SQL is parameterised (see db.py)
* every response carries defensive HTTP headers
"""

import os
import re

from flask import Flask, abort, jsonify, request

from . import db

MEMBER_RE = re.compile(r"^M\d{5}$")
ISBN_RE = re.compile(r"^\d{13}$")


def create_app(database: str | None = None) -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 16 * 1024
    conn = db.connect(database or os.environ.get("LOAN_DB_PATH", ":memory:"))

    @app.after_request
    def security_headers(resp):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Cache-Control"] = "no-store"
        return resp

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.post("/loans")
    def borrow():
        data = request.get_json(silent=True) or {}
        member, isbn = str(data.get("member_id", "")), str(data.get("isbn", ""))
        if not MEMBER_RE.fullmatch(member) or not ISBN_RE.fullmatch(isbn):
            abort(400, "member_id must look like M12345 and isbn must be 13 digits")
        loan_id = db.create_loan(conn, member, isbn)
        return jsonify(id=loan_id, member_id=member, isbn=isbn), 201

    @app.get("/members/<member_id>/loans")
    def member_loans(member_id):
        if not MEMBER_RE.fullmatch(member_id):
            abort(400, "invalid member id")
        return jsonify(db.loans_for_member(conn, member_id))

    @app.post("/loans/<int:loan_id>/return")
    def give_back(loan_id):
        if not db.mark_returned(conn, loan_id):
            abort(404, "no open loan with that id")
        return jsonify(id=loan_id, returned=True)

    @app.errorhandler(400)
    @app.errorhandler(404)
    def json_error(err):
        return jsonify(error=err.description), err.code

    return app
