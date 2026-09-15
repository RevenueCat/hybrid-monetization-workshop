# Workshop agent instructions

## Scope

- Read [README.md](README.md) before implementation and use this checkout as the project context. Consult [DESIGN_GUIDELINES.md](DESIGN_GUIDELINES.md) for adaptable interface guidance when useful.

## RevenueCat

- Use the RevenueCat AI Toolkit’s relevant skills and its MCP tools or `rc` CLI exclusively for RevenueCat reads, writes, and configuration. Do not use a browser or UI automation to create, edit, attach, publish, or otherwise configure RevenueCat resources. Browser use is limited to opening a read-only dashboard link or preview for participant review. If the toolkit cannot perform a required console step, guide the participant through it instead of automating the dashboard. Check current official RevenueCat documentation, SDK support, and account availability; ask only for choices unavailable from the task or configuration.
- Use the configured workshop project or a dedicated test project. Reuse matching resources; do not modify unrelated projects. Separate checkouts do not isolate connected accounts.
- Assume the predefined workshop project unless the participant explicitly chooses a different RevenueCat project. With the predefined project, treat remote catalog and paywall setup as already complete and do not modify shared RevenueCat resources. With a participant-owned project, configure only its Test Store app and selected resources.
- Keep account-specific identifiers and keys in ignored local configuration; track only placeholder examples. The shared workshop project's public Test Store SDK key is the sole exception and may be tracked in `ios/Workshop.xcconfig` so simulator exercises work without manual setup. Never track a production SDK key or a RevenueCat secret key, and never expose secret values in chat, prompts, logs, or commits.
- Use Test Store purchases. Local grants and test doubles never count as confirmed RevenueCat integration results. For Scenario B, use Google's tracked demo ad identifiers unless the participant explicitly supplies other test-only configuration; never use live ads for workshop testing.

## Verification

Build and run focused checks appropriate to the implementation. Confirm RevenueCat access with a Test Store purchase and use test traffic for ads. Report the checks actually completed and any remaining failures or blockers; never imply unrun checks passed.

## Git

Do not create branches, commit, or push without explicit instruction. Before an authorized commit, verify real configuration is neither tracked nor staged.
