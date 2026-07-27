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

## Pull request review priorities

When reviewing a pull request, report only high-confidence, actionable issues.
Prioritize findings in this order:

1. **Security:** authentication and pairing bypasses, credential exposure,
   command or path injection, unsafe terminal authority, public-network
   exposure, symlink/traversal mistakes, and weakened trust boundaries.
2. **Privacy:** screenshots, recordings, hostnames, addresses, paths, terminal
   output, prompts, files, or diagnostics leaving their intended local scope;
   unexpected data retention; and read-only file access becoming writable.
3. **Correctness:** protocol 7/8 compatibility, client/host contract drift,
   reconnect and concurrency races, stale UI state, request correlation,
   storage identity, rollback, and explicit error handling.
4. **Code quality:** type safety, reuse of established helpers, bounded
   resource use, focused tests for discovered regressions, and consistency
   with nearby ReLand architecture.

Ignore formatting-only preferences and speculative findings without a concrete
failure path. Verify that behavior changes include the relevant unit,
integration, simulator, privacy, and security coverage. Copilot review is
advisory and does not replace the repository's required human approval.

Do not bypass either skill because a build or unit test passes. Do not modify
protected workflows, scripts, signing configuration, vendored dependencies,
package manifests, privacy manifests, or security policy unless the task
explicitly requires it and repository policy permits it.
