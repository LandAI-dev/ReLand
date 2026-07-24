# Privacy

ReLand is designed to operate without a ReLand account or ReLand-operated
cloud service.

## Data ReLand processes

- screen or selected-window frames;
- pointer, keyboard, and gesture input;
- terminal input and output;
- session artifact metadata and downloaded files;
- approved-folder file metadata and downloaded files;
- device names, private addresses, pairing credentials, and connection state.

This data is exchanged directly between your paired devices over your private
network. ReLand does not intentionally send it to Land AI LLC.

## Local storage

- Pairing keys are stored in Apple Keychain.
- Device/session preferences are stored in local app preferences.
- Host session data is stored under
  `~/Library/Application Support/ReLand`.
- Downloaded previews are cached locally on the iPhone/iPad.
- Approved folders are represented by macOS security-scoped bookmarks.

## Permissions

- **Local Network:** connect to ReLand Host.
- **Camera:** scan a one-time pairing QR.
- **Screen Recording (Mac):** stream the display or selected app.
- **Accessibility (Mac):** send pointer and keyboard input.

ReLand cannot approve these permissions for you.

The iOS privacy manifest declares no tracking or collected-data categories.
It declares UserDefaults access with Apple's `CA92.1` reason for app-only
preferences and state.

## Tailscale

If you use Tailscale, Tailscale independently processes network and account
data under its own privacy policy. ReLand does not inspect your Tailscale plan
or billing state.

## Diagnostics

Do not share pairing payloads, keys, terminal output, screenshots, hostnames,
private addresses, or file paths in public bug reports. ReLand release
diagnostics must redact these fields.
