"""Simulator-only Spoons spending service. Python standard library only."""

import hashlib
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import UUID


ROOT = Path(__file__).resolve().parent


def configuration():
    values = {}
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                key, separator, value = line.partition("=")
                if not separator:
                    raise ValueError("Expected KEY=value in backend/.env")
                values[key.strip()] = value.strip()
    values.update(os.environ)
    for name in ("REVENUECAT_SECRET_KEY", "REVENUECAT_PROJECT_ID"):
        if not values.get(name):
            raise ValueError(f"Set {name} in backend/.env")
    cost = int(values.get("IMPORT_COST", "25"))
    currency = values.get("CURRENCY_CODE", "SPOON")
    if cost <= 0 or not currency or len(currency) > 100:
        raise ValueError("IMPORT_COST must be positive and CURRENCY_CODE nonempty")
    return values, currency, cost


class RevenueCat:
    def __init__(self, secret, project):
        self.secret = secret
        self.project = project

    def spend(self, customer, operation, currency, cost, key):
        url = (
            "https://api.revenuecat.com/v2/projects/"
            + quote(self.project, safe="")
            + "/customers/"
            + quote(customer, safe="")
            + "/virtual_currencies/transactions"
        )
        body = {"adjustments": {currency: -cost}, "reference": "import:" + operation}
        request = Request(
            url,
            data=json.dumps(body).encode(),
            headers={
                "Authorization": "Bearer " + self.secret,
                "Content-Type": "application/json",
                "Idempotency-Key": key,
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=15) as response:
                return response.status
        except HTTPError as error:
            error.close()
            return error.code


class SpendingService:
    def __init__(self, database, project, currency, cost, revenuecat):
        self.project = project
        self.currency = currency
        self.cost = cost
        self.revenuecat = revenuecat
        self.db = sqlite3.connect(database, isolation_level=None)
        self.db.execute(
            """CREATE TABLE IF NOT EXISTS imports (
                key TEXT PRIMARY KEY, currency TEXT NOT NULL, cost INTEGER NOT NULL,
                status INTEGER, response TEXT
            )"""
        )
        self.db.execute(
            """CREATE TABLE IF NOT EXISTS daily_rewards (
                customer TEXT NOT NULL, claim_date TEXT NOT NULL,
                claimed_at TEXT NOT NULL, PRIMARY KEY (customer, claim_date)
            )"""
        )

    @staticmethod
    def _customer(body):
        if not isinstance(body, dict) or set(body) != {"app_user_id"}:
            return None
        customer = body["app_user_id"]
        if not isinstance(customer, str) or not customer.strip() or len(customer) > 1500:
            return None
        return customer

    @staticmethod
    def _reward_window(now=None):
        now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        tomorrow = datetime.combine(
            now.date() + timedelta(days=1), datetime.min.time(), timezone.utc
        )
        return now, now.date().isoformat(), tomorrow.isoformat().replace("+00:00", "Z")

    def daily_reward_status(self, body, now=None):
        customer = self._customer(body)
        if customer is None:
            return 400, {"error": "expected_app_user_id"}
        _, claim_date, next_claim_at = self._reward_window(now)
        claimed = self.db.execute(
            "SELECT 1 FROM daily_rewards WHERE customer = ? AND claim_date = ?",
            (customer, claim_date),
        ).fetchone()
        return 200, {"claimable": claimed is None, "next_claim_at": next_claim_at}

    def claim_daily_reward(self, body, now=None):
        customer = self._customer(body)
        if customer is None:
            return 400, {"error": "expected_app_user_id"}
        current, claim_date, next_claim_at = self._reward_window(now)
        cursor = self.db.execute(
            "INSERT OR IGNORE INTO daily_rewards VALUES (?, ?, ?)",
            (customer, claim_date, current.isoformat().replace("+00:00", "Z")),
        )
        return 200, {
            "recorded": cursor.rowcount == 1,
            "claimable": False,
            "next_claim_at": next_claim_at,
        }

    def spend(self, body):
        if not isinstance(body, dict) or set(body) != {"app_user_id", "operation_id"}:
            return 400, {"error": "expected_app_user_id_and_operation_id"}
        customer = body["app_user_id"]
        operation = body["operation_id"]
        if not isinstance(customer, str) or not customer.strip() or len(customer) > 1500:
            return 400, {"error": "invalid_app_user_id"}
        try:
            operation = str(UUID(operation))
        except (ValueError, TypeError, AttributeError):
            return 400, {"error": "operation_id_must_be_uuid"}

        key = hashlib.sha256(
            json.dumps([self.project, customer, operation], ensure_ascii=True).encode()
        ).hexdigest()
        self.db.execute(
            "INSERT OR IGNORE INTO imports VALUES (?, ?, ?, NULL, NULL)",
            (key, self.currency, self.cost),
        )
        currency, cost, status, response = self.db.execute(
            "SELECT currency, cost, status, response FROM imports WHERE key = ?", (key,)
        ).fetchone()
        if status is not None:
            return status, json.loads(response)

        try:
            upstream = self.revenuecat.spend(customer, operation, currency, cost, key)
        except (URLError, TimeoutError, OSError):
            return 503, {"error": "revenuecat_unavailable", "retry_same_operation": True}

        if upstream == 200:
            status, response = 200, {
                "operation_id": operation,
                "currency_code": currency,
                "spent": cost,
            }
        elif upstream == 422:
            status, response = 422, {
                "error": "insufficient_balance",
                "currency_code": currency,
                "required": cost,
            }
        else:
            return 503, {
                "error": "revenuecat_request_failed",
                "upstream_status": upstream,
                "retry_same_operation": True,
            }
        self.db.execute(
            "UPDATE imports SET status = ?, response = ? WHERE key = ?",
            (status, json.dumps(response), key),
        )
        return status, response


def handler_for(service):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(20)

        def reply(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                self.reply(
                    200,
                    {
                        "status": "ok",
                        "currency_code": service.currency,
                        "import_cost": service.cost,
                    },
                )
            else:
                self.reply(404, {"error": "not_found"})

        def do_POST(self):
            routes = {
                "/imports/spend": service.spend,
                "/rewards/daily/status": service.daily_reward_status,
                "/rewards/daily/claim": service.claim_daily_reward,
            }
            action = routes.get(self.path)
            if action is None:
                return self.reply(404, {"error": "not_found"})
            if self.headers.get("Origin"):
                return self.reply(403, {"error": "browser_requests_not_supported"})
            if self.headers.get_content_type() != "application/json":
                return self.reply(415, {"error": "expected_json"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 8192:
                    raise ValueError()
                body = json.loads(self.rfile.read(length))
            except (ValueError, UnicodeDecodeError):
                return self.reply(400, {"error": "invalid_json_body"})
            self.reply(*action(body))

        def log_message(self, format, *args):
            pass

    return Handler


def main():
    try:
        values, currency, cost = configuration()
        port = int(values.get("PORT", "8787"))
        if not 1 <= port <= 65535:
            raise ValueError("PORT must be between 1 and 65535")
    except ValueError as error:
        raise SystemExit(str(error)) from None

    state = ROOT / ".state"
    state.mkdir(exist_ok=True)
    service = SpendingService(
        state / "imports.sqlite3",
        values["REVENUECAT_PROJECT_ID"],
        currency,
        cost,
        RevenueCat(values["REVENUECAT_SECRET_KEY"], values["REVENUECAT_PROJECT_ID"]),
    )
    with HTTPServer(("127.0.0.1", port), handler_for(service)) as server:
        print(f"Spending service: http://127.0.0.1:{port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            service.db.close()


if __name__ == "__main__":
    main()
