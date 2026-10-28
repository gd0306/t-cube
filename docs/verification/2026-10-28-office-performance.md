# Office parity and performance verification — 0.16.0

## Implementation

- macOS and Windows default to idle power saving: stop idle rotation/light animation, keep a static cube, resume on interaction. Continuous display remains an explicit setting. Windows uses 15Hz continuous idle/30Hz interaction and 80ms resting/250ms hidden host polling; system animation preference is sampled once per second.
- Windows glass/slime tint and contour strengthened; shipping smoke checks light/dark contrast and transparent center.
- Windows adds common-content library, structured fields, native focus-checked paste, explicit clipboard capture/drop, groups/favorites/search; configurable hover delay and independent display memory; validated configuration/content backup/restore and relinking; login settings and signature-gated updater.
- Quit drains admitted content/archive and launcher mutations before closing; cancelling an unsaved library quit preserves desktop resources. Pending saves disable editor actions.

## Local evidence

- `swift test --scratch-path .build/tests --no-parallel`: 4 XCTest + 74 native Swift Testing + 98 core Swift Testing passed. Concurrent desktop run had one ARView snapshot contention failure; isolated lifecycle tests and complete serial run passed.
- Node22 `npm --prefix windows run typecheck`, `npm --prefix windows test`, `npm --prefix windows run build`: passed; 127 tests passed, one non-Windows native test skipped.
- macOS debug app built and installed on this device. Short idle CPU samples (`top`, 2-second intervals): previous app 19.8%/26.7%; updated default power saving 0.0%/0.0%/0.0%. These are short samples in this desktop scenario, not a cross-hardware benchmark.
- User configuration/content was not replaced with fixtures; automated Windows smoke uses `TCUBE_USER_DATA_DIR` and an owned WinForms paste receiver.

## Release verification

Windows 2022/2025 source runtime checks and actual installed NSIS checks are required before publication; exact-source artifact IDs and checksum verification are recorded after completion. Current builds have no Developer ID/notarization or Authenticode production signature; application update replacement stays disabled until the documented signing configuration exists.
