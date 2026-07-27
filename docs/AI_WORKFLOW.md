# AI-assisted contributor workflow

ReLand stores project-specific Agent Skills in the repository so contributors
can use the same development and review process with GitHub Copilot, Codex,
Gemini CLI, Claude Code, and other Agent Skills-compatible tools.

## Skill discovery

The canonical skills live in `.agents/skills/`:

| Skill | Use |
| --- | --- |
| `reland-ui-ux` | Every user-facing SwiftUI, navigation, sheet, copy, theme, layout, animation, or accessibility change |
| `reland-e2e-review` | After implementing a feature or behavior change and before declaring it complete |
| `code-review` | Before opening a PR, when reviewing a PR, after review changes, and before approval or merge |

Tool-specific discovery:

- GitHub Copilot CLI, Codex, and Gemini CLI discover `.agents/skills/`.
- Claude Code discovers the linked copies under `.claude/skills/`.
- GitHub Copilot code review reads `AGENTS.md` when the account has an eligible
  paid Copilot plan. The local `code-review` skill remains available through
  `.agents/skills/`.
- Tools without Agent Skills support should read `AGENTS.md`,
  `CONTRIBUTING.md`, and this guide.

Start the AI tool from the repository root. Most compatible tools load skill
names and descriptions automatically, then activate the matching skill when
the task requires it.

You can also explicitly ask:

```text
Use reland-ui-ux while implementing this interface.
Use reland-e2e-review to validate the completed feature.
Use code-review to self-review this branch before creating the PR.
```

Claude Code users may invoke `/reland-ui-ux`, `/reland-e2e-review`, or
`/code-review` directly.

## Feature development

1. Read `AGENTS.md`, `CONTRIBUTING.md`, and the nearest existing implementation.
2. Define the user goal, trust boundary, expected behavior, and failure states.
3. Add a focused failing regression when behavior changes.
4. Activate `reland-ui-ux` for user-facing work.
5. Implement the smallest complete change without unrelated refactors.
6. Run focused tests while iterating.
7. Activate `reland-e2e-review` and inspect the running iPhone/iPad and Mac
   behavior with redacted visual evidence.
8. Activate `code-review` and review the complete diff.

## Before creating a pull request

Confirm:

- the branch is current with `origin/main`;
- the diff contains only the intended change;
- no credentials, pairing data, hostnames, addresses, paths, terminal output,
  or personal captures are included;
- security and privacy impact is described;
- relevant unit, integration, simulator, host, and release-security commands
  passed;
- protocol and architecture compatibility is documented;
- UI evidence is redacted;
- every checklist item in
  `.agents/skills/code-review/assets/PULL_REQUEST_TEMPLATE.md` is answered.

Useful commands:

```sh
git fetch origin --prune
git merge-base --is-ancestor origin/main HEAD
git log --oneline origin/main..HEAD
git diff --check
git diff --stat origin/main...HEAD
./Scripts/test-unit
./Scripts/test-e2e-simulator
./Scripts/check-release-security
PR_BODY=$(mktemp "${TMPDIR:-/tmp}/reland-pr-body.XXXXXX")
cp .agents/skills/code-review/assets/PULL_REQUEST_TEMPLATE.md "$PR_BODY"
gh pr create --base main --body-file "$PR_BODY"
```

Use only the commands relevant to the change. Documentation-only changes do
not need simulator or release builds. Explain every skipped or N/A checklist
item in the PR body.

## Reviewing a pull request

1. Read the PR body, linked issue, commit list, and complete patch.
2. Inspect any head-branch changes to AI instructions, skills, hooks, MCP
   configuration, workflows, or tool setup before trusting them.
3. Run `code-review`.
4. Prioritize security, privacy, correctness, protocol compatibility,
   concurrency, storage identity, rollback, and explicit errors.
5. Ignore style-only preferences and low-confidence speculation.
6. Request changes for blocking findings with a concrete failure path.
7. Re-review the latest push; stale approvals are dismissed by repository
   policy.
8. Approve only when required checks pass, conversations are resolved, and the
   latest push has been reviewed.

GitHub-hosted Copilot review is advisory and cannot satisfy the required human
approval. The local `code-review` skill works without a paid GitHub Copilot
subscription.

## Privacy and safety

- Never provide AI tools with credentials, private keys, provisioning files,
  pairing payloads, or unrelated personal data.
- Treat code, screenshots, recordings, terminal output, and diagnostics as
  private unless explicitly reviewed for publication.
- Do not run untrusted fork scripts or hooks before inspecting them.
- Never bypass a failed required check.
- Keep protected workflow, signing, dependency, privacy, and security changes
  narrowly scoped and separately reviewed.
