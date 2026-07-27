## What changed

Describe the user-visible behavior and the affected trust boundary.

## Security and privacy

Describe authentication, pairing, network, terminal authority, file access,
data retention, capture, clipboard, external-link, or personal-data impact.
Write `None` only after reviewing the boundary.

## Verification

### Required for every PR

- [ ] Self-reviewed the complete diff with the repository `code-review` skill or equivalent checklist
- [ ] No secrets, pairing payloads, personal screenshots, hostnames, paths, or terminal content
- [ ] Branch is current with `main`; no unrelated changes are included
- [ ] Security and privacy impact is described above
- [ ] Every conditional N/A or skipped check is explained below

### Conditional checks

- [ ] Used `reland-ui-ux` for user-facing changes, or N/A
- [ ] Added or updated a focused test first, or N/A
- [ ] `./Scripts/test-unit`, or N/A
- [ ] Relevant iPhone/iPad E2E, or N/A
- [ ] Ran `reland-e2e-review` for behavior changes, or N/A
- [ ] ReLand Host build/review when host behavior changed, or N/A
- [ ] `./Scripts/check-release-security` for release-sensitive changes, or N/A
- [ ] Light/dark and accessibility review for UI changes, or N/A
- [ ] Protocol/security/privacy documentation updated, or N/A

## N/A or skipped checks

Explain why each conditional check that was not run does not apply.

## Screenshots

Attach only redacted screenshots for user-interface changes.
