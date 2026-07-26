# ReLand agent instructions

Follow `CONTRIBUTING.md` for repository workflow, security, testing, and source
boundaries.

Project Agent Skills are canonical under `.agents/skills/`:

- Activate `reland-ui-ux` for every user-facing SwiftUI, navigation, sheet,
  control, copy, theme, layout, animation, or accessibility change.
- Activate `reland-e2e-review` after implementing a feature or behavior change
  and before declaring it complete.

Claude Code discovery links live under `.claude/skills/`; edit the canonical
`.agents/skills/` files rather than duplicating their content.

The UI/UX skill defines the product design contract. The E2E review skill makes
running the simulator and Mac host, plus redacted screenshots or recordings,
part of feature completion.

Do not bypass either skill because a build or unit test passes. Do not modify
protected workflows, scripts, signing configuration, vendored dependencies,
package manifests, privacy manifests, or security policy unless the task
explicitly requires it and repository policy permits it.
