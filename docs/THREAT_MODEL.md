# Threat model

## Protected assets

- pairing and device credentials;
- screen/window frames;
- keyboard and pointer input;
- terminal content and shell authority;
- session artifacts;
- approved files;
- private host identity and address.

## Trust boundaries

1. Unpaired network peer -> ReLand Host listener.
2. Paired client -> authenticated remote-control session.
3. Network parser -> capture/input/terminal/file executors.
4. ReLand Host -> macOS TCC-protected capabilities.
5. ReLand storage -> user-approved external folders.
6. Raw terminal/AI output -> iOS UI, clipboard, and external links.

## Defenses

- private-network destination policy;
- TLS-PSK and challenge authentication;
- expiring, single-use QR pairing;
- explicit pairing confirmation;
- Keychain storage;
- packet and file size limits;
- path normalization, hidden-path rejection, and symlink rejection;
- read-only approved-folder browsing;
- TCC permission gates;
- DEBUG-only deterministic test credentials.

## Important risks

- A paired device has powerful terminal and input authority.
- ReLand Host is not App-Sandboxed.
- A compromised network-facing host process could reach high-authority local
  executors; XPC isolation is planned future hardening.
- App Mode may raise a hidden/off-Space window and change the visible Mac
  Space.
- A locked Mac can be captured in limited cases but cannot be interacted with
  or unlocked.
- Tailscale is an independent trust and infrastructure dependency when used.

## Non-goals

- bypassing macOS login, TCC, or app permissions;
- exposing ReLand Host to the public internet;
- multi-tenant or untrusted-device terminal access;
- guaranteeing secrecy after a user intentionally exports an artifact;
- remotely approving a first pairing without physical Mac access in v0.1.
