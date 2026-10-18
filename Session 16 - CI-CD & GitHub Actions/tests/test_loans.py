from datetime import date

import pytest

from catalog.loans import MAX_FINE, due_date, is_valid_isbn13, overdue_fine


def test_due_date_is_two_weeks_later():
    assert due_date(date(2025, 1, 1)) == date(2025, 1, 15)


def test_due_date_rejects_non_positive_period():
    with pytest.raises(ValueError):
        due_date(date(2025, 1, 1), loan_days=0)


@pytest.mark.parametrize(
    "returned, expected",
    [
        (date(2025, 1, 10), 0.0),   # early
        (date(2025, 1, 15), 0.0),   # on the due date
        (date(2025, 1, 19), 1.0),   # 4 days late
    ],
)
def test_overdue_fine(returned, expected):
    assert overdue_fine(date(2025, 1, 15), returned) == expected


def test_fine_is_capped():
    assert overdue_fine(date(2025, 1, 1), date(2025, 12, 31)) == MAX_FINE


@pytest.mark.parametrize(
    "isbn, ok",
    [
        ("9780132350884", True),
        ("978-1-4919-5035-7", True),
        ("9780132350885", False),  # bad check digit
        ("12345", False),
        ("97801323508AB", False),
    ],
)
def test_isbn13_checksum(isbn, ok):
    assert is_valid_isbn13(isbn) is ok
