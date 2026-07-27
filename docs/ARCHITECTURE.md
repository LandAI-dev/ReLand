# Architecture

## Components

```text
ReLand client
  -> ReLandCore (TLS-PSK, wire protocol, shared models)
  -> private LAN or Tailscale
  -> ReLand Host
       -> ReLandHostCore
            -> ScreenCaptureKit
            -> Accessibility / CGEvent
            -> tmux / Terminal / AI CLIs
            -> app-owned artifacts
            -> approved read-only folders
```

## Dependency direction

```text
ReLandClient -> ReLandCore
ReLandHost -> ReLandCore + ReLandHostCore
ReLandHostCore -> ReLandCore
```

Shared code must not depend on app targets.

## Persistence

App state depends on `SettingsStoring` and `CredentialStoring`, with
UserDefaults and Keychain adapters provided by ReLandCore. App models and
device/host stores accept these dependencies through initializers so tests and
future cleanup tools do not need to mutate real user state.

## Connection lifecycle

1. The client opens a Network.framework TLS-PSK connection.
2. The host sends a random challenge and protocol version.
3. The client authenticates with HMAC-SHA256.
4. During pairing, the host accepts one expiring pairing credential and
   provisions a fresh device credential.
5. Active sessions exchange framed typed packets.
6. Heartbeats detect dead connections.

`SessionReady` also includes current Screen Recording, Accessibility, and Mac
lock state. The client can refresh this state with the host-status request and
show explicit Open Mac Screen/Retry recovery actions.

## Capture and input

- Screen Mode captures the display.
- App Mode uses a desktop-independent ScreenCaptureKit window filter.
- Absolute input is mapped to current display/window bounds.
- Accessibility focuses and raises a selected app window before input.
- App-window capture does not reliably include the macOS cursor, so the client
  renders a virtual cursor.

The selected capture target is currently host-global, so v0.1 permits one
active authenticated controller. A second controller receives `hostBusy`.
Active clients refresh a bounded host-side lease through normal traffic and
heartbeats; stale connections are evicted. A confirmed authenticated takeover
revokes the previous controller before the new one becomes active. Per-client
capture contexts are future work.

## Terminal and artifacts

ReLand Host manages `rl-*` tmux sessions. Each session receives an app-owned
workspace with Artifacts, Instructions, and helper binaries. Raw AI commands
are unmodified; ReLand AI injects tool-specific artifact instructions.
Internal session IDs are lowercase and are not reused while their retained
workspace exists, so a new terminal cannot inherit an older session's files.

## File access

Remote browsing is read-only and limited to:

- ReLand application storage;
- folders explicitly approved in ReLand Host.

Hidden components, traversal, and symlinks are rejected on the host.

Terminal working-directory requests use the same virtual approved-folder
paths. ReLand Host resolves and validates the directory before passing a local
URL to tmux; the client never supplies an arbitrary filesystem path.

## Concurrency

Several transport/service types use serial queue confinement and are marked
`@unchecked Sendable`. All mutable state in those types must remain on the
documented queue. Convert incrementally to actors only with characterization
tests.

## Distribution boundary

ReLand Host is not App-Sandboxed because it must post global input and launch
tmux, Terminal, shells, and local AI CLIs. Release hardening relies on
Hardened Runtime, notarization, TCC consent, private-network restrictions,
authenticated commands, and narrow file roots.
