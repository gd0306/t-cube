# Windows source client verification

Date: 2026-10-27. Windows client version: 0.13.0. Target: Windows 10 22H2 (19045+) and Windows 11, x64.

## Executed checks

- Local Node 22: `npm test` — 57 passed, one Windows-only native test skipped; `npm run typecheck`, `npm run build`, and `git diff --check` passed.
- [Windows CI run 40453360356](https://github.com/gd0306/t-cube/actions/runs/40453360356), commit `dd26ed8`: both `windows-2022` and `windows-2025` jobs passed. Each ran locked dependency installation, all 58 tests (no skips), strict type checking, bundling, PowerShell source installation into a temporary per-user directory, and the installed runtime's Electron smoke test.
- The native test loaded real Win32 DLLs, queried input/animation preferences, and extracted a high-resolution Explorer shell icon through `IShellItemImageFactory`.
- Smoke exercised an isolated six-group/24-icon configuration, native cursor hover from 164 to 656 DIP, inactive-window Ctrl shrinking, Ctrl-left movement with Ctrl released mid-drag, native mouse-up and saved position. It edited a group name and verified a single subsequent tab click, changed launch mode/hover/theme settings, saved bottom-right placement, and opened/dismissed a four-icon panel with Escape. No widget JavaScript exception occurred.
- Corrected Windows captures were downloaded and inspected: transparent curved body and icon decals, readable light settings, and an icon-only translucent expansion. Checked-in Windows screenshots come from this run; only transparent views use a capture backdrop.
- Source review covered configuration corruption/backup, atomic serialized updates, native-release ordering, cancellation, deferred I/O, sender/frame IPC authorization, install/runtime layout and renderer state. All task reviews and the whole-branch review approved the implementation.

## Coverage distinctions

Direct target dispatch, both-button drag/cancellation ordering, absent-renderer release fallback, two-axis rotation without snapping, reduced-motion behavior, geometry picking, rapid preference edits, and corrupt-file preservation have focused behavior tests. Launch tests capture the host launch callback; smoke changes direct-launch mode without opening external applications. No unrelated user applications were launched.

CI uses Windows Server runner images, rather than physical Windows 10/11 desktops. Mixed-DPI monitors, physical trackpad direction, real user shortcuts/UWP links, and Windows 10/11 hardware acceptance remain manual checks. Windows ARM64 is outside the initial validation scope. Windows glass uses the shared translucent rendering; Apple's Clear Liquid Glass and an optional Windows 11 native backdrop are not part of this client.

The macOS Swift test baseline passed before the port; no native Swift, package or resource metadata was changed. An Electron preview attempt on this Mac hung during graphics/debug startup and was terminated. The completed desktop evidence above comes from installed Windows runtimes, not that preview.

## Installation and data

Follow [windows/README.md](../../windows/README.md) or its short local-agent prompt using `master`. `windows/scripts/install.ps1` builds and copies a standalone runtime, creates shortcuts and preserves `%APPDATA%/T-Cube/configuration.json`. There is no installer artifact. Tests use explicit temporary data directories, and the native Mac configuration remains separate.
