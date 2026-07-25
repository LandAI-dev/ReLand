# Contributing to ReLand

## Setup

```sh
brew install xcodegen tmux
cp Config/Local.xcconfig.example Config/Local.xcconfig
./Scripts/bootstrap
./Scripts/test-unit
```

Set your Apple team ID only in ignored `Config/Local.xcconfig`.

## Generated project

`ReLand.xcodeproj` is generated and ignored. Edit `project.yml`; do not commit
generated project changes.

## Source boundaries

- `Apps/ReLandClient` — iOS/iPadOS UI and state.
- `Apps/ReLandHost` — macOS UI and host composition.
- `Packages/ReLandCore/Sources/ReLandCore` — shared transport, protocol,
  security, and models.
- `Packages/ReLandCore/Sources/ReLandHostCore` — host capture, input,
  terminal, file, and server services.
- `Tests/ReLandE2EHost` / `Tests/ReLandUITests` — deterministic UI tests.

Keep dependencies directed from apps to packages and from `ReLandHostCore` to
`ReLandCore`.

## Change workflow

1. Add a focused failing test.
2. Run it and confirm the intended RED result.
3. Implement the smallest correct change.
4. Run the targeted test and relevant integration/E2E suite.
5. Refactor only while tests remain green.

Do not add broad catches, silent fallbacks, unsafe force-casts, or destructive
cleanup that can cross an app-owned boundary.

## Review and merge

- Submit changes through a pull request; contributors cannot push to `main`.
- External workflow runs require maintainer approval.
- Resolve every review conversation and keep the required `verify` check green.
- Security-sensitive areas listed in `.github/CODEOWNERS` request maintainer
  review automatically.
- ReLand uses squash-only merges so `main` receives one verified signed commit.
- Never ask a maintainer to bypass a failed or missing required check.

When a second trusted maintainer is added, the repository will require one
independent code-owner approval and approval of the latest push.

## Protocol changes

Before adding a wire message:

- update `docs/PROTOCOL.md`;
- assign the message in the correct domain range;
- define typed request/response models;
- add codec and integration tests;
- preserve compatibility or bump the protocol deliberately;
- add a stable structured error code where applicable.

## UI changes

- support loading, empty, error, and retry states;
- use 44-point minimum targets;
- verify VoiceOver, Dynamic Type, light/dark mode, Reduce Motion, iPhone, and
  iPad layouts;
- avoid user-visible strings in test-only fixtures;
- capture only redacted screenshots.

## Security and privacy

Never commit:

- credentials, tokens, private keys, pairing payloads, or signing files;
- personal screenshots or recordings;
- private hostnames, addresses, paths, or terminal output;
- production diagnostics without redaction.

Security-sensitive reports belong in the private security reporting flow.
