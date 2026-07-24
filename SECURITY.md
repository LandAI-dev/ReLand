# Security policy

## Reporting a vulnerability

Do not disclose suspected vulnerabilities in a public issue.

After the public repository is available, use GitHub's private vulnerability
reporting or open a private draft security advisory for `LandAI-dev/ReLand`.
Include:

- affected version/commit;
- reproducible steps;
- realistic impact;
- logs or screenshots with credentials, addresses, paths, and personal data
  removed;
- a suggested mitigation, if known.

## Supported versions

During pre-release development, only the latest `main` revision is supported.
Published beta support will be documented in release notes.

## Security boundaries

- Pairing is explicit, local, one-time, and QR-based.
- Transport uses Network.framework TLS-PSK.
- Client and host reject public network destinations.
- Screen capture and input require macOS TCC consent.
- Remote files are limited to ReLand storage and folders approved on the Mac.
- Hidden paths, traversal, and symlinks are rejected server-side.
- Terminal access is intentionally powerful and should be granted only to
  devices you control.

See [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) for limitations and
non-goals.
