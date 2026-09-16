import json
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import HTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from unittest.mock import patch

from server import RevenueCat, SpendingService, handler_for


OPERATION = "ebf5fb88-c8cc-49ec-8bc7-7c3c8105035d"


class FakeRevenueCat:
    def __init__(self):
        self.balance = 50
        self.receipts = {}
        self.calls = []
        self.lose_response = False
        self.status = None

    def spend(self, customer, operation, currency, cost, key):
        self.calls.append((customer, operation, currency, cost, key))
        if self.status:
            return self.status
        if key not in self.receipts:
            status = 200 if self.balance >= cost else 422
            if status == 200:
                self.balance -= cost
            self.receipts[key] = status
        if self.lose_response:
            self.lose_response = False
            raise URLError("Response lost after debit")
        return self.receipts[key]


class SpendingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "state.sqlite3"
        self.rc = FakeRevenueCat()
        self.service = SpendingService(self.path, "project", "SPOON", 25, self.rc)
        self.body = {"app_user_id": "$RCAnonymousID:customer", "operation_id": OPERATION}

    def tearDown(self):
        self.service.db.close()
        self.directory.cleanup()

    def restart(self, cost=25):
        self.service.db.close()
        self.service = SpendingService(self.path, "project", "SPOON", cost, self.rc)

    def test_success_and_repeat_after_restart_charge_once(self):
        result = self.service.spend(self.body)
        self.assertEqual(
            result,
            (200, {"operation_id": OPERATION, "currency_code": "SPOON", "spent": 25}),
        )
        self.restart()
        self.assertEqual(self.service.spend(self.body), result)
        self.assertEqual(self.rc.balance, 25)
        self.assertEqual(len(self.rc.calls), 1)

    def test_lost_response_retry_keeps_key_and_original_cost(self):
        self.rc.lose_response = True
        self.assertEqual(self.service.spend(self.body)[0], 503)
        self.restart(cost=100)
        self.assertEqual(self.service.spend(self.body)[0], 200)
        self.assertEqual(self.rc.balance, 25)
        self.assertEqual(self.rc.calls[0], self.rc.calls[1])

    def test_insufficient_balance_needs_new_operation_after_top_up(self):
        self.rc.balance = 0
        self.assertEqual(self.service.spend(self.body)[0], 422)
        self.rc.balance = 25
        self.assertEqual(self.service.spend(self.body)[0], 422)
        self.body["operation_id"] = "7ad38751-23a1-4146-8d99-2ea5f980c914"
        self.assertEqual(self.service.spend(self.body)[0], 200)
        self.assertEqual(self.rc.balance, 0)

    def test_invalid_requests_never_contact_revenuecat(self):
        for body in (
            [],
            {},
            dict(self.body, amount=1),
            dict(self.body, app_user_id=""),
            dict(self.body, operation_id=23),
        ):
            with self.subTest(body=body):
                self.assertEqual(self.service.spend(body)[0], 400)
        self.assertEqual(self.rc.calls, [])

    def test_upstream_failures_retry_with_the_same_key(self):
        for status in (401, 403, 404, 409, 429, 500):
            self.rc.status = status
            result = self.service.spend(self.body)
            self.assertEqual(result[0], 503)
            self.assertEqual(result[1]["upstream_status"], status)
        self.rc.status = None
        self.assertEqual(self.service.spend(self.body)[0], 200)
        self.assertEqual(len({call[-1] for call in self.rc.calls}), 1)

    def test_daily_reward_is_available_once_per_utc_day(self):
        body = {"app_user_id": "daily-customer"}
        first_day = datetime(2026, 9, 16, 23, 59, tzinfo=timezone.utc)
        next_day = datetime(2026, 9, 17, 0, 1, tzinfo=timezone.utc)
        self.assertEqual(
            self.service.daily_reward_status(body, first_day),
            (200, {"claimable": True, "next_claim_at": "2026-09-17T00:00:00Z"}),
        )
        claimed = self.service.claim_daily_reward(body, first_day)
        self.assertEqual(claimed[0], 200)
        self.assertTrue(claimed[1]["recorded"])
        self.assertFalse(self.service.claim_daily_reward(body, first_day)[1]["recorded"])
        self.assertFalse(self.service.daily_reward_status(body, first_day)[1]["claimable"])
        self.assertTrue(self.service.daily_reward_status(body, next_day)[1]["claimable"])

    def test_daily_reward_rejects_invalid_customer(self):
        for body in ({}, {"app_user_id": "", "extra": True}, {"app_user_id": 42}):
            with self.subTest(body=body):
                self.assertEqual(self.service.daily_reward_status(body)[0], 400)
                self.assertEqual(self.service.claim_daily_reward(body)[0], 400)


class AdapterTests(unittest.TestCase):
    def test_api_request_escapes_ids_and_sets_fixed_debit_and_idempotency(self):
        with patch("server.urlopen") as send:
            send.return_value.__enter__.return_value.status = 200
            result = RevenueCat("test-secret", "project/id").spend(
                "$RCAnonymousID:a/b", OPERATION, "SPOON", 25, "stable-key"
            )
        self.assertEqual(result, 200)
        request = send.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://api.revenuecat.com/v2/projects/project%2Fid/customers/"
            "%24RCAnonymousID%3Aa%2Fb/virtual_currencies/transactions",
        )
        self.assertEqual(
            json.loads(request.data),
            {"adjustments": {"SPOON": -25}, "reference": "import:" + OPERATION},
        )
        self.assertEqual(request.get_header("Idempotency-key"), "stable-key")
        self.assertEqual(request.get_header("Authorization"), "Bearer test-secret")

    def test_http_error_is_returned_without_provider_body(self):
        with patch("server.urlopen", side_effect=HTTPError("url", 422, "error", {}, None)):
            self.assertEqual(
                RevenueCat("test", "project").spend(
                    "customer", OPERATION, "SPOON", 25, "key"
                ),
                422,
            )


class HTTPTests(unittest.TestCase):
    def test_health_spending_and_bad_input(self):
        ready = threading.Event()
        servers = []

        def serve():
            service = SpendingService(":memory:", "test", "SPOON", 25, FakeRevenueCat())
            with HTTPServer(("127.0.0.1", 0), handler_for(service)) as server:
                servers.append(server)
                ready.set()
                server.serve_forever()
            service.db.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        self.assertTrue(ready.wait(5))
        base = "http://127.0.0.1:" + str(servers[0].server_port)
        try:
            with urlopen(base + "/health") as response:
                self.assertEqual(json.load(response)["import_cost"], 25)
            daily = Request(
                base + "/rewards/daily/status",
                data=json.dumps({"app_user_id": "test"}).encode(),
                headers={"Content-Type": "application/json"},
            )
            with urlopen(daily) as response:
                self.assertTrue(json.load(response)["claimable"])
            body = json.dumps(
                {"app_user_id": "test", "operation_id": OPERATION}
            ).encode()
            request = Request(
                base + "/imports/spend",
                data=body,
                headers={"Content-Type": "application/json"},
            )
            with urlopen(request) as response:
                self.assertEqual(json.load(response)["spent"], 25)
            request = Request(
                base + "/imports/spend",
                data=b"not json",
                headers={"Content-Type": "application/json"},
            )
            with self.assertRaises(HTTPError) as error:
                urlopen(request)
            self.assertEqual(error.exception.code, 400)
            error.exception.close()
        finally:
            servers[0].shutdown()
            thread.join(5)


if __name__ == "__main__":
    unittest.main()
