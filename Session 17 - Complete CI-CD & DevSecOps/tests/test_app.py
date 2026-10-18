import pytest

from loan_service.app import create_app


@pytest.fixture
def client():
    return create_app(":memory:").test_client()


def test_healthz_and_security_headers(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in resp.headers["Content-Security-Policy"]


def test_borrow_list_and_return(client):
    created = client.post("/loans", json={"member_id": "M00042", "isbn": "9780132350884"})
    assert created.status_code == 201
    loan_id = created.get_json()["id"]

    loans = client.get("/members/M00042/loans").get_json()
    assert loans == [{"id": loan_id, "isbn": "9780132350884", "returned": False}]

    assert client.post(f"/loans/{loan_id}/return").status_code == 200
    assert client.get("/members/M00042/loans").get_json()[0]["returned"] is True
    # returning twice is rejected
    assert client.post(f"/loans/{loan_id}/return").status_code == 404


@pytest.mark.parametrize(
    "payload",
    [
        {"member_id": "M1' OR '1'='1", "isbn": "9780132350884"},
        {"member_id": "M00042", "isbn": "978-0132350884"},
        {},
    ],
)
def test_borrow_rejects_bad_input(client, payload):
    assert client.post("/loans", json=payload).status_code == 400


def test_member_id_injection_is_rejected(client):
    assert client.get("/members/x' OR 1=1--/loans").status_code == 400
