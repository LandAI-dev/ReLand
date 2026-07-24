# Changelog

All notable user-visible changes will be documented here.

## Unreleased

- Renamed the product, applications, modules, storage, and protocol service
  from LandRemote to ReLand.
- Added ReLand AI (`reland-ai`) with a `landai` developer alias.
- New terminal sessions start in their app-owned ReLand workspace.
- Removed the separate AI File Setup sheet; empty Artifacts now offers
  explicit Send to AI and Copy prompt actions.
- Added three-finger horizontal App Mode switching with tested MRU ordering,
  haptic feedback, and a transient native window strip.
- Added first-run purpose/prerequisite onboarding and real iOS/macOS Settings
  surfaces for controls, privacy, network guidance, and bounded cleanup.
- Added the original navy/teal ReLand portal and return-path icon.
- Added live Mac Screen Recording, Accessibility, and lock-state recovery with
  Open Mac Screen and Retry actions.
- Fixed Screen Mode absolute pointer mapping so the physical bottom edge can
  reveal the auto-hidden macOS Dock.
- Replaced the hidden horizontal remote-control scroller with a fixed labeled
  action dock, a More menu, gesture guide, and disconnect confirmation.
- Added secure project-folder selection for new terminals. Only ReLand storage
  and folders approved in ReLand Host can become a tmux working directory.
- Added explicitly named ReLand AI launch profiles. Permission-bypass flags
  remain off unless the user selects a named risky profile.
- Replaced secret-bearing pairing links with expiring, one-time QR payloads
  that require explicit confirmation.
- Added client-side private-network enforcement.
- Removed release access to deterministic E2E credentials.
