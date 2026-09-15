# Hybrid Monetization Workshop

Kitchen Table is an iOS cooking companion used to explore subscription and ad-supported monetization. Participants work in a local clone and start from the base branch for a scenario. Each final branch shows one example solution; participants can choose and implement a different approach to the same monetization challenge. The exercises can be completed directly or with a coding agent.

## Start here

You need:

- A Mac with Xcode, an iOS 18 or newer SDK, and an installed iPhone simulator.
- Git.

Clone the repository rather than downloading a ZIP. The workshop uses Git branches as checkpoints:

```sh
git clone https://github.com/RevenueCat/hybrid-monetization-workshop.git
cd hybrid-monetization-workshop
git switch scenarios/A-base
```

Open `ios/KitchenTable.xcodeproj`, select the KitchenTable scheme and an iPhone simulator, then build once so Xcode resolves the pinned Swift packages. The project includes RevenueCat Purchases, RevenueCatUI, and the RevenueCat AdMob adapter where the selected checkpoint needs them.

## Workshop checkpoints

Choose the base branch for the exercise you are doing when one is available. Final branches contain example solutions, not required outcomes or starting points.

| Checkpoint | Branch | Purpose |
| --- | --- | --- |
| Original app | `free-baseline` | App with all themes free and no monetization integration |
| Scenario A start | `scenarios/A-base` | Starting point for subscriptions and paid access |
| Scenario A example | `scenarios/A-final` | One final subscription solution |
| Scenario B start | `scenarios/B-base` | Subscription solution, ready to add an ad-supported free tier |
| Scenario B example | `scenarios/B-final` | One final ad-supported solution |
| Scenario C start | `scenarios/C-base` | Ad-supported solution, ready to add temporary premium-feature rewards |
| Scenario C example | `scenarios/C-final` | One final rewarded-feature solution |
| Scenario D start | Not available | No prepared base for the in-app currency exercise yet |
| Scenario D example | Not available | No final rewarded-currency solution yet |

## RevenueCat workshop configuration

Debug simulator builds use the public SDK key for the predefined workshop Test Store app. Participants can build, make test purchases, restore, and check entitlements without local configuration. Attendees with View Only dashboard access can also browse the project, catalog, and paywalls.

The predefined catalog and paywalls are shared by every participant, so participant access is read-only and these resources cannot be modified. To experiment with different configurations, [use a RevenueCat project you control](#use-a-different-revenuecat-project).

The tracked key is intentionally limited to RevenueCat Test Store. It must never be used for an App Store build.

### Use a different RevenueCat project

If preferred, use a dedicated RevenueCat project with its own Test Store app. Recreate the selected scenario's products, entitlements, offerings, packages, and RevenueCatUI paywall using the lookup keys below, then create the ignored local configuration:

```sh
cp ios/Workshop.example.xcconfig ios/Workshop.local.xcconfig
```

Set the project ID, Test Store app ID, and public Test Store SDK key in `ios/Workshop.local.xcconfig`:

```xcconfig
REVENUECAT_PROJECT_ID =
REVENUECAT_TEST_APP_ID =
REVENUECAT_TEST_API_KEY =
```

The example file also contains Scenario B offering and entitlement overrides. Keep account-specific values in this ignored file, never use a RevenueCat secret API key, and complete a Test Store purchase to verify the alternative configuration.

## Scenario A: RevenueCat subscriptions

Start from `scenarios/A-base`. Use the predefined subscription catalog and RevenueCatUI paywall to integrate the SDK, gate paid features, and verify a Test Store purchase. If you are using a participant-owned project, recreate the catalog and paywall first using the identifiers below. `scenarios/A-final` is available afterward as one example of how the scenario can be solved.

The implementation is intentionally open-ended. You may work in Kitchen Table or apply the exercise to your own app, choose different premium features, and design a different upgrade journey. The final branch demonstrates one possible solution rather than a required design.

Suggested steps:

1. **Choose the premium value.** Decide what remains free and which features are worth subscribing for. Keep the free experience useful.
2. **Model access.** Review how the predefined products, packages, offering, and entitlements work together. Gate features with entitlements, not product identifiers.
3. **Set up the catalog and paywall.** Create or adapt the resources for your chosen access model. (Only when not using the predefined RevenueCat project.)
4. **Provide the SDK key.** Add the public SDK key for your Test Store app to the local configuration. (Only when not using the predefined RevenueCat project.)
5. **Configure RevenueCat.** Initialize the SDK once, early in the app lifecycle, using the available public SDK key.
6. **Track access.** Keep shared app state in sync with the customer's active entitlements and react to changes.
7. **Design the upgrade journey.** Present the dismissible RevenueCatUI paywall where it feels useful, such as at a premium feature or in settings.
8. **Show the current plan.** Let free users upgrade or restore purchases, and give subscribers a way to view and manage their plan.
9. **Test both experiences.** Confirm dismissal preserves the free experience and a Test Store purchase immediately unlocks the expected access.
10. **Verify restoration.** On a fresh install with the same Test Store customer, restore access without purchasing again.

| Resource | Lookup key or identifier | Purpose |
| --- | --- | --- |
| Offering | `plus_features` | Subscription packages and associated paywall |
| Entitlement | `plus` | Recipe import and starting a recipe |
| Entitlement | `premium_themes` | Themes other than Original |
| Monthly package | `$rc_monthly` | Monthly subscription package |
| Annual package | `$rc_annual` | Yearly subscription package |
| Monthly product | `kitchen_table_plus_monthly` | Test Store monthly subscription |
| Yearly product | `kitchen_table_plus_yearly` | Test Store yearly subscription |

## Scenario B: Ad-supported free tier

Start from `scenarios/B-base`. This checkpoint already includes the subscription experience. Extend the useful free experience with ads while keeping subscriptions ad-free. You may choose placements and formats that suit the app; `scenarios/B-final` demonstrates one possible solution.

Suggested steps:

1. **Choose the ad-supported value.** Decide which experiences free users can access in exchange for seeing ads and what remains a subscriber benefit.
2. **Define the access rules.** Use active entitlements to decide who sees ads, without coupling the logic to a specific subscription product.
3. **Set up the RevenueCat resources.** Add or adapt the offering, entitlements, and ad placements for your model. (Only when not using the predefined RevenueCat project.)
4. **Configure test ads.** Add Google Mobile Ads, the RevenueCat AdMob adapter, and test-only app and ad-unit identifiers. (Only when not using the predefined RevenueCat project.)
5. **Manage ad readiness.** Centralize the state of ad formats that load asynchronously. (When using interstitials, preload one before it is needed and prepare the next one after each result.)
6. **Place ads thoughtfully.** Show interstitials at natural transitions and place banner or native ads where they do not disrupt content or controls.
7. **Keep subscribers ad-free.** Suppress every ad format and remove empty ad space as soon as the subscription entitlement becomes active.
8. **Verify the complete flow.** Confirm free actions continue after an ad closes or fails, subscribers see no ads, and RevenueCat receives the available ad events.

Scenario B reuses the Scenario A products and entitlements and adds an offering tailored to the ad-free upgrade:

| Resource | Lookup key or identifier | Purpose |
| --- | --- | --- |
| Offering | `plus_ad_free` | Plus packages and associated ad-free paywall |
| Entitlement | `plus` | Removes ads |
| Entitlement | `premium_themes` | Unlocks themes other than Original |
| Interstitial placement | `recipe_action` | Import or Start Recipe interstitial events |
| Banner placement | `recipe_book_banner` | Bottom Recipe Book collapsible-banner events |

The Scenario B checkpoints use Google's official iOS demo identifiers, so no AdMob account or additional ad configuration is required. The example uses the interstitial and collapsible-banner units; demo identifiers for other suggested formats are included for experimentation:

| AdMob resource | Test identifier |
| --- | --- |
| Application | `ca-app-pub-3940256099942544~1458002511` |
| Interstitial ad unit | `ca-app-pub-3940256099942544/4411468910` |
| Anchored or inline adaptive banner unit | `ca-app-pub-3940256099942544/2435281174` |
| Fixed-size banner unit | `ca-app-pub-3940256099942544/2934735716` |
| Collapsible banner unit used by the example | `ca-app-pub-3940256099942544/8388050270` |
| Native ad unit | `ca-app-pub-3940256099942544/3986624511` |

Use test ads only. Replace every demo identifier before distributing a production build.

## Scenario C: Rewarding ads with premium features

Start from `scenarios/C-base`. This checkpoint already includes the ad-supported experience and shared rewarded-ad configuration. Let free users choose to watch an ad for temporary access to a premium feature. You may choose a different feature or presentation; `scenarios/C-final` demonstrates a 30-minute premium-theme reward as one possible solution.

Suggested steps:

1. **Choose the reward.** Pick a premium experience that is useful to try temporarily and decide how long access should last.
2. **Model temporary access.** Use an entitlement that can represent both permanent subscriber access and a time-limited rewarded grant.
3. **Configure the verified reward.** Connect an SSV-enabled rewarded ad unit to the temporary entitlement grant in RevenueCat. (Only when not using the predefined RevenueCat project.)
4. **Override the AdMob configuration.** Set `ADMOB_APP_ID` and `ADMOB_REWARDED_AD_UNIT_ID` in the local configuration to the application and SSV-enabled rewarded unit from your AdMob account. (Only when not using the predefined RevenueCat project.)
5. **Prepare the ad.** Preload the rewarded ad and expose the option only when an ad is ready to show.
6. **Offer a clear choice.** Let eligible users subscribe or watch an ad, and explain the reward and its duration before playback.
7. **Confirm access through RevenueCat.** Unlock the feature only after the verified grant appears in the customer's active entitlements; do not rely on a local timer or grant.
8. **Handle expiration.** Refresh access when the grant expires and return the user to an available free experience.
9. **Test the outcomes.** Verify successful reward, cancellation, failure, expiration, and the subscriber path with test traffic only.

Scenario C reuses the existing subscription catalog and paywall. The predefined RevenueCat project maps the rewarded ad unit to a 30-minute grant of the existing `premium_themes` entitlement.

| Resource | Lookup key or identifier | Purpose |
| --- | --- | --- |
| Offering | `plus_ad_free` | Existing Plus packages and associated ad-free paywall |
| Entitlement | `premium_themes` | Subscription or temporary rewarded access to premium themes |
| Rewarded placement | `premium_theme_trial` | Theme trial rewarded-ad events |
| AdMob application | `ca-app-pub-8714904180834987~6755567849` | Preconfigured workshop application |
| Rewarded ad unit | `ca-app-pub-8714904180834987/2209818177` | SSV-enabled 30-minute theme reward |

The owned rewarded unit is required because Google's demo rewarded unit cannot be configured for server-side verification. iOS simulators request test ads automatically. Do not run this workshop unit on an unregistered physical test device or use it to generate production traffic.

## Scenario D: Rewarding ads with in-app currency

This scenario does not yet have a prepared base branch or final example solution. It assumes the app already has an in-app currency. Designing that economy can be part of the exercise, but makes the scenario more involved.

Add rewarded ads as another way to earn the existing currency. This lets users choose between money and attention to obtain the same currency, then decide when to spend it. The reward and its availability should complement purchases, subscription grants, and other earning sources without devaluing them.

Suggested steps:

1. **Understand the economy.** Identify how users currently earn and spend the currency and what its value represents.
2. **Choose the reward.** Set an amount and availability that feels worthwhile without overwhelming other currency sources.
3. **Configure a verified grant.** Connect the rewarded ad to the existing in-app currency and credit it through RevenueCat after successful verification.
4. **Present the exchange clearly.** Tell users how much currency they will receive before they choose to watch.
5. **Handle ad readiness.** Preload the rewarded ad and provide clear unavailable, cancellation, and failure states.
6. **Verify the balance.** Confirm successful grants, repeated rewards, and spending behave consistently with purchases and subscription grants.

## Build and test

Build from the repository root:

```sh
xcodebuild -project ios/KitchenTable.xcodeproj -scheme KitchenTable -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/DerivedData CODE_SIGN_IDENTITY=- build
```

Use Product → Test for the existing model and UI tests. On Apple Silicon, command-line builds and tests should pass `ARCHS=arm64`. Physical-device signing is outside the default workshop path and requires your own development team and unique bundle identifier in `ios/Workshop.local.xcconfig`.

## About the sample app

Recipe imports use a five-recipe mock selection; sharing a webpage does not convert it into a new recipe. Bundled recipe JSON and photos live in [ios/Resources/Recipes](ios/Resources/Recipes/).

See [DESIGN_GUIDELINES.md](DESIGN_GUIDELINES.md) for adaptable interface guidance. The Classic theme uses Special Elite; retain its [font license](ios/Resources/Fonts/LICENSE-Special-Elite.txt).
