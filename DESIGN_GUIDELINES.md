# Workshop design guidance

Use these principles as a starting point when adding paywalls, subscription screens, and ad-supported experiences. Adapt them to the product, platform, and monetization approach you choose.

## Themes and typography

- When working in Kitchen Table, reuse the semantic colors, fonts, and components in [AppTheme.swift](ios/Sources/AppTheme.swift) and [PageHeading.swift](ios/Sources/PageHeading.swift). Other apps should follow their own design systems.
- Choose whether monetization UI follows the selected app theme or uses a consistent presentation of its own. Keep the result visually coherent with the surrounding experience.
- Prefer semantic roles for backgrounds, surfaces, text, borders, accents, and on-accent labels. Support the appearances offered by the app without hardcoded colors or inverted imagery.
- Keep typography, spacing, and decorative detail consistent with neighboring screens.

## Actions and choices

- Establish a clear action hierarchy so the main next step and its alternatives are easy to understand.
- Distinguish selected plans or settings from actions with an appropriate selection treatment.
- Keep close and dismissal controls discoverable when the experience can be dismissed.
- Show loading, unavailable, error, and completed states clearly. Prevent repeated submission while an action is in progress and provide a useful retry when appropriate.

## Ads

- Keep ads subordinate to the product experience. They should not cover navigation, content, or important controls, and reserved space should collapse when no ad is shown.
- Place full-screen ads at natural transitions and preserve the user's intended action across presentation, dismissal, failure, and access changes.
- If a subscription promises an ad-free experience, remove every enabled ad format without leaving empty layout space or briefly flashing an ad while access is resolving.
- Use clearly recognizable test ads during development. Never generate workshop traffic with production ads.

## Copy

- Use short, direct labels and explanations. State what the user receives and what the action costs or requires.
- Keep purchase, access, reward, and ad-removal messages accurate to confirmed state.
- In Kitchen Table, describe mock importing as example-recipe behavior rather than claiming a shared webpage was converted.
- Avoid em dashes in user-visible copy. Use en dashes for numeric ranges such as `10–15 min`.

## Accessibility and continuity

- Respect Dynamic Type. Let text wrap and controls stack at larger sizes instead of shrinking or clipping content.
- Keep controls comfortably tappable, with meaningful accessibility labels and selection states. Do not convey meaning through color alone.
- Maintain readable contrast for secondary text, disabled controls, and errors.
- Respect Reduce Motion and Reduce Transparency. Keep transitions brief and avoid unnecessary animation.
- Opening and dismissing monetization screens or ads should preserve the user's current context and work.

## Review

Review changed interfaces in the states and environments relevant to the implementation, such as loading, dismissal, purchase, restoration, ad failure, supported themes, appearances, and accessibility settings. Choose a review scope proportional to the change and report what was actually checked.
