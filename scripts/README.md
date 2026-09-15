# Workshop preflight

From the repository root, run:

```sh
./scripts/workshop-check
```

This optional helper is implemented in Python and therefore requires Python 3 from the command line; the iOS app itself does not depend on Python. It also requires a Git clone and Xcode. The command checks Xcode, an available iOS 18+ iPhone simulator, and whether local configuration is ignored by Git. It selects the only booted iPhone, or the only available iPhone if none is booted. If that is ambiguous, supply `--simulator` with the exact name or UDID. It does not boot or create a simulator. A downloaded ZIP is unsupported because it has no Git metadata or workshop branches.

For a RevenueCat exercise:

```sh
./scripts/workshop-check --revenuecat
```

The RevenueCat AI Toolkit plugin and the RevenueCat CLI are separate installations. Install and authenticate the CLI before running this check:

```sh
brew install RevenueCat/tap/rc
rc auth login
```

See RevenueCat's [CLI setup guide](https://www.revenuecat.com/docs/tools/cli/setup) for npm and direct-download alternatives. With no `REVENUECAT_PROJECT_ID` configured, the check verifies authentication by listing accessible projects (an empty list is valid), reports catalog checks as skipped, and succeeds. It does not create or choose a project. Once a project is configured, inability to access it is a failure. It uses the CLI's existing credentials; it never requests or prints a secret key. To check an existing project and its catalog, set these literal values in ignored `ios/Workshop.local.xcconfig` (or environment variables, which take precedence):

```xcconfig
REVENUECAT_PROJECT_ID =
REVENUECAT_TEST_APP_ID =
REVENUECAT_TEST_API_KEY =
```

Use your dedicated workshop project, Test Store app, and public Test Store SDK key. The command does not use a CLI default project. It reads that project's apps, products, entitlements, and offerings and reports counts. An empty catalog can be valid before an exercise creates it.

Optionally specify comma-separated expected product store identifiers, entitlement lookup keys, and offering lookup keys:

```xcconfig
PREFLIGHT_PRODUCT_IDS =
PREFLIGHT_ENTITLEMENTS =
PREFLIGHT_OFFERINGS =
```

When populated, missing expected resources fail the check. Without expectations, the command reports inventory only. It does not verify SDK key ownership, product prices, trials, package/entitlement associations, or runtime purchases. Large paginated catalogs fail explicitly rather than being reported as complete. This is a small workshop-project check, not a full configuration audit.

The local parser supports simple literal assignments and comments, not xcconfig includes or variable expansion. This checks setup presence; the build remains the authority for effective app configuration. Account and resource identifiers are never included in the report. Simulator names, simulator UDIDs, and the selected Xcode path are displayed so you can identify the build destination.

Add `--build` for an optional Debug simulator build:

```sh
./scripts/workshop-check --revenuecat --build
```

This writes to `ios/DerivedData` and may download Swift packages. It does not install, launch, run tests, or make a purchase. Without `--build`, only inspection commands run. No mode changes local configuration, authenticates interactively, or creates remote resources. Subprocess output is captured and discarded to avoid exposing configuration values; failures report an exit code or timeout. Run the relevant tool separately to investigate detailed failures.

Exit codes: `0` means the requested checks passed; `1` means a check failed; `2` means invalid command arguments. `PASS`, `FAIL`, and `SKIP` lines make the scope explicit. In restricted agent environments, CoreSimulator or CLI credential access may require tool approval; the command reports failure instead of bypassing restrictions.

## Troubleshooting

### Simulator check fails

Open Xcode once and complete any first-launch setup, then check that Xcode → Settings → Components contains an installed iOS 18+ runtime. List available devices with:

```sh
xcrun simctl list devices available
```

If several iPhones are available, boot the intended simulator or pass its exact name or UDID to `--simulator`. If `simctl` itself fails, restart Xcode and Simulator; restricted coding-agent environments may also require permission to access CoreSimulator.

### Xcode check fails

Select the full Xcode installation and complete its license/setup prompts:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```

These commands may require administrator approval. Run the preflight again afterward.

### RevenueCat check fails

Confirm `rc auth status` succeeds and that the authenticated account can access the project stored in ignored local configuration. The project ID is not inferred from the CLI's default project. If you are using the predefined workshop project, omit `--revenuecat`; participants do not need shared-project access.

### Build check fails

Open the project in Xcode and let Swift Package Manager finish resolving dependencies. Then retry with the same simulator selected by preflight. Run `xcodebuild` directly when detailed compiler or package output is needed; the preflight intentionally suppresses subprocess output so configuration values cannot leak.

Run the script's offline checks with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
```
