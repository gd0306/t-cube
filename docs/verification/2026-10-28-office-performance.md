# Office parity and performance verification — 0.16.0

## Implementation

- macOS and Windows default to idle power saving: stop idle rotation/light animation, keep a static cube, resume on interaction. Continuous display remains an explicit setting. Windows uses 15Hz continuous idle/30Hz interaction and 80ms resting/250ms hidden host polling; system animation preference is sampled once per second.
- Windows glass/slime tint and contour strengthened; shipping smoke checks light/dark contrast and transparent center.
- Windows adds common-content library, structured fields, native focus-checked paste, explicit clipboard capture/drop, groups/favorites/search; configurable hover delay and independent display memory; validated configuration/content backup/restore and relinking; login settings and signature-gated updater.
- Quit drains admitted content/archive and launcher mutations before closing; cancelling an unsaved library quit preserves desktop resources. Pending saves disable editor actions.

## Local evidence

- `swift test --scratch-path .build/tests --no-parallel`: 4 XCTest + 74 native Swift Testing + 98 core Swift Testing passed. Concurrent desktop run had one ARView snapshot contention failure; isolated lifecycle tests and complete serial run passed.
- Node22 `npm --prefix windows run typecheck`, `npm --prefix windows test`, `npm --prefix windows run build`: passed; 129 tests passed, one non-Windows native test skipped.
- macOS debug app built and installed on this device. Short idle CPU samples (`top`, 2-second intervals): previous app 19.8%/26.7%; updated default power saving 0.0%/0.0%/0.0%. These are short samples in this desktop scenario, not a cross-hardware benchmark.
- User configuration/content was not replaced with fixtures; automated Windows smoke uses `TCUBE_USER_DATA_DIR` and an owned WinForms paste receiver.

## Native Windows paste verification

The real owned WinForms receiver exposed inactive-window focus becoming NULL. Added a failing regression, then changed restoration to validate process/window identity before activation and original input focus after activation. Missing or changed focus never injects. See [Microsoft GUI-thread activation remarks](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getguithreadinfo). The smoke receiver now treats PowerShell progress separately from fatal errors; failure captures and CI steps have deadlines.

## Release verification

Windows 2022/2025 source runtime checks both passed in [run 40800696053](https://github.com/gd0306/t-cube/actions/runs/40800696053), source `2490ebab353095dd878f74aa9137a70bdd0a4023`. This includes actual copy and both native paste actions, idle stop/15Hz resume, backup preview/restore, material/theme controls, native dragging and application picking. Final installed NSIS verification and published asset checks are recorded below. Current builds have no Developer ID/notarization or Authenticode production signature; application update replacement stays disabled until the documented signing configuration exists.

## Published 0.16.0

- Installer source/tag: `f9a28d2893126fb560ac053cce82b1aaaa93678f`, [Release v0.16.0](https://github.com/gd0306/t-cube/releases/tag/v0.16.0).
- Merged-source Windows 2022/2025 checks: [40801106767](https://github.com/gd0306/t-cube/actions/runs/40801106767), both passed.
- Actual installed NSIS checks: [40801244195](https://github.com/gd0306/t-cube/actions/runs/40801244195), passed. Installer artifact `12866755649` records the exact source SHA.
- Merged macOS serial verification: 4 XCTest + 74 native + 98 core tests passed; final DMG mounted, app/executable/signature/install link verified.
- macOS release build 0.16.0 (28) installed and launched on this device. Performance settings visibly show default idle saving ON. Original configuration/content retained.
- Final installed macOS short sampling with the user's existing 10-second theme cycling enabled: seven valid two-second CPU samples were 10.1%, 0%, 0%, 0%, 0%, 11.4%, 0%. Most samples are idle; theme changes still wake rendering briefly. This is not a universal zero-CPU claim or a hardware benchmark.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| T-Cube-0.16.0-macos-arm64.dmg | 1997400 | `25ba6d64d9d4f80f5358e613cb8b86817190eb094d73619a45866a56e4b3fd7b` |
| T-Cube-0.16.0-windows-x64-setup.exe | 125211801 | `d64307a6fcb6e5e5ff62ee685450b61f168cf045e9edf80bfa38dca8a31ce65f` |

Both installer sizes/digests and SHA256SUMS.txt were matched against GitHub's uploaded asset digests before publication. Current builds remain ad-hoc/unsigned with authenticated auto-replacement disabled, as documented in the release notes.
