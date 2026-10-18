"""Pure business rules for the library, kept free of Flask so they are easy to unit test."""

from datetime import date, timedelta

LOAN_DAYS = 14
FINE_PER_DAY = 0.25
MAX_FINE = 10.00


def due_date(borrowed_on: date, loan_days: int = LOAN_DAYS) -> date:
    """Return the date a book borrowed on `borrowed_on` must be returned."""
    if loan_days <= 0:
        raise ValueError("loan_days must be positive")
    return borrowed_on + timedelta(days=loan_days)


def overdue_fine(due: date, returned_on: date) -> float:
    """Fine owed for a late return: a flat rate per day, capped at MAX_FINE."""
    days_late = (returned_on - due).days
    if days_late <= 0:
        return 0.0
    return round(min(days_late * FINE_PER_DAY, MAX_FINE), 2)


def is_valid_isbn13(isbn: str) -> bool:
    """Check an ISBN-13 using its weighted (1,3,1,3...) checksum."""
    digits = isbn.replace("-", "").replace(" ", "")
    if len(digits) != 13 or not digits.isdigit():
        return False
    total = sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(digits[:12]))
    return (10 - total % 10) % 10 == int(digits[12])
