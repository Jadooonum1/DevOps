"""loan-service: tiny JSON API for the library, Python standard library only."""
import json
import logging
import os
from datetime import date, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LEVEL = os.environ.get("LOG_LEVEL", "info").upper()
logging.basicConfig(level=LEVEL, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("loan-service")

PERIOD = int(os.environ.get("LOAN_PERIOD_DAYS", "14"))
MAX_LOANS = int(os.environ.get("MAX_LOANS_PER_MEMBER", "5"))

LOANS = [
    {"isbn": "9780131103627", "title": "The C Programming Language", "member": "M-1001"},
    {"isbn": "9781491950357", "title": "Building Microservices", "member": "M-1002"},
    {"isbn": "9781617293726", "title": "Kubernetes in Action", "member": "M-1001"},
]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "ok"})
        elif self.path == "/loans":
            due = (date.today() + timedelta(days=PERIOD)).isoformat()
            self._send(200, [dict(loan, due=due) for loan in LOANS])
        elif self.path == "/":
            self._send(200, {
                "service": "loan-service",
                "environment": os.environ.get("ENVIRONMENT", "unknown"),
                "branch": os.environ.get("BRANCH_NAME", ""),
                "loan_period_days": PERIOD,
                "max_loans_per_member": MAX_LOANS,
                "pod": os.environ.get("HOSTNAME", ""),
            })
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        log.debug("%s %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    log.info("loan-service listening on :%d (period=%dd, max=%d)", port, PERIOD, MAX_LOANS)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
