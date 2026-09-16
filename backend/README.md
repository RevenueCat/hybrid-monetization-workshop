# Local spending service

This simulator-only service supports the Scenario D Spoons economy. It runs on
the Mac at `http://127.0.0.1:8787`, binds only to loopback, and trusts the
RevenueCat App User ID supplied by the app. Do not deploy it or expose it
through a tunnel. A production service needs authenticated customers and HTTPS.

## Configure

Create a participant-owned RevenueCat project with a Test Store app, the
`SPOON` in-app currency, and the products described in the repository README.
Then create the ignored local configuration:

```sh
cp backend/.env.example backend/.env
```

Set `REVENUECAT_SECRET_KEY` to a RevenueCat API v2 secret key that can read and
write customer purchases, and set `REVENUECAT_PROJECT_ID` to that project's ID.
Never put this key in the iOS app, an xcconfig file, logs, chat, or source
control.

Start the service from the repository root:

```sh
python3 backend/server.py
curl http://127.0.0.1:8787/health
```

Stop it with Control-C. Configuration changes require a restart.

## Import contract

`POST /imports/spend` accepts:

```json
{
  "app_user_id": "$RCAnonymousID:example",
  "operation_id": "ebf5fb88-c8cc-49ec-8bc7-7c3c8105035d"
}
```

The app supplies neither an amount nor a currency. The service deducts the
configured import cost, currently 25 `SPOON`, through RevenueCat.

- `200`: the debit succeeded, or this operation already succeeded. Finish the
  prepared import and refresh the SDK balance.
- `422`: the customer has insufficient Spoons. After acquiring currency, retry
  with a new operation ID.
- `503`: the result is uncertain or RevenueCat rejected the request. Preserve
  the pending import and retry with the same operation ID.
- `400`/`415`: the request is invalid and must be corrected before retrying.

Successful receipts and insufficient-balance results are stored under the
ignored `backend/.state/` directory. RevenueCat also receives a stable
`Idempotency-Key`, so a response lost after a debit cannot cause a second
charge.

## Daily reward eligibility

`POST /rewards/daily/status` and `POST /rewards/daily/claim` accept only the
RevenueCat App User ID:

```json
{
  "app_user_id": "$RCAnonymousID:example"
}
```

The service keeps a once-per-UTC-day eligibility record. It does not grant
currency or verify ads. AdMob sends its SSV callback to RevenueCat, RevenueCat
grants the Spoons, and the app records the daily claim here only after
verification succeeds. A production system should enforce eligibility in a
remotely reachable verification flow rather than trusting this local workshop
client.

## Test without RevenueCat

```sh
python3 -m unittest discover -s backend -v
```

The tests use a fake RevenueCat client. They do not contact RevenueCat or prove
that a real Test Store purchase or debit works.
