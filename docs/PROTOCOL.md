# ReLand wire protocol

## Framing

Each packet is:

```text
uint32 bodyLength (big endian)
uint8  messageKind
bytes  payload
```

`bodyLength` includes the kind byte. JSON encodes typed payloads. Video and
terminal bytes use their defined binary payload fields.

## Authentication

- TLS-PSK transport.
- Random challenge.
- HMAC-SHA256 response.
- Constant-time authentication-code comparison.
- Pairing credentials are expiring and one-time.

## Compatibility negotiation

The current supported range is `7...7`.

The host challenge advertises:

- its supported protocol range;
- available feature capabilities.

The client chooses the highest common version and returns the capability
intersection in its authentication response. The host echoes the negotiated
version and capabilities in `SessionReady`. A connection fails before session
activation when no common version exists.

An authenticated client may set `requestsControllerTakeover` only after
explicit user confirmation. The host revokes the current controller with the
`sessionTakenOver` error before activating the replacement.

Current capabilities are screen, input, terminal, artifacts, approved files,
and capture-target selection.

## Message ranges

- `1...12` — authentication/session/heartbeat/error.
- `13...24` — terminal lifecycle and I/O.
- `25...28` — terminal artifacts.
- `29...32` — approved remote files.
- `33...36` — capture-target listing and selection.
- `37...38` — host permission/lock status.
- `39...127` — reserved for future core protocol messages; unknown values are
  rejected.
- `128...255` — optional extension messages; an older decoder skips the
  complete framed body when it does not recognize the kind.

Do not reuse an assigned value. Add request/response models and integration
tests with every new message.

## Limits

- Maximum packet: 8 MiB.
- Artifact chunk: 256 KiB.
- Maximum artifact: 512 MiB.

The host must reject malformed lengths, oversized payloads, invalid offsets,
unsafe paths, and unauthenticated active-session messages.
