import pytest

from catalog.app import create_app


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_version_defaults_to_dev(client, monkeypatch):
    monkeypatch.delenv("GIT_SHA", raising=False)
    assert client.get("/version").get_json()["commit"] == "dev"


def test_list_books_sorted_by_title(client):
    titles = [b["title"] for b in client.get("/books").get_json()]
    assert titles == sorted(titles)


def test_get_missing_book_is_404(client):
    assert client.get("/books/0000000000000").status_code == 404


def test_add_book_then_fetch_it(client):
    new = {"isbn": "9780596007126", "title": "Head First Design Patterns", "author": "Freeman"}
    assert client.post("/books", json=new).status_code == 201
    assert client.get("/books/9780596007126").get_json()["title"] == new["title"]


def test_add_book_validates_isbn(client):
    resp = client.post("/books", json={"isbn": "123", "title": "Bad"})
    assert resp.status_code == 400


def test_add_duplicate_book_is_409(client):
    resp = client.post("/books", json={"isbn": "9780132350884", "title": "Clean Code"})
    assert resp.status_code == 409


def test_loan_quote_late_return(client):
    resp = client.get("/loans/quote?borrowed=2025-03-01&returned=2025-03-20")
    assert resp.get_json() == {"due": "2025-03-15", "fine": 1.25}


def test_loan_quote_bad_date(client):
    assert client.get("/loans/quote?borrowed=yesterday").status_code == 400
