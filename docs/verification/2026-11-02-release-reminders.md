# Release reminders / 0.19.0 (34)

Unsigned builds now offer a metadata-only reminder in Settings → 启动与更新. Automatic checks default to off. Enabling them schedules a check every six hours, persists attempt time and the highest automatically notified version, and shows a dialog offering the validated project release page. Manual checks work without signing credentials and have a one-minute cooldown. No assets are downloaded or installed. Existing signed Sparkle/electron-updater activation gates remain intact.

## Automated and visual verification

- Red regressions reproduced disabled manual checks in unsigned Mac builds, inherited HTTP credentials, clock rollback suppressing checks, conflicting rate-limit headers and incorrect restart status. They passed after implementation. Windows regressions additionally cover disabling during an asynchronous preference write and distant retry timers without Node timer overflow.
- `swift test --no-parallel --scratch-path .build/tests` passed: 6 XCTest, 129 native Swift Testing and 116 core cases registered; 244 executed/passed, seven opt-in diagnostic/live/render cases skipped.
- Separate `TCUBE_LIVE_RELEASE_CHECK=1 TCUBE_REMINDER_PREVIEW=1` focused native tests passed, including an actual anonymous metadata request reporting the then-current public stable version 0.18.1. No credentials, installer requests or user settings were used. Inspected the [native settings preview](../images/release-reminder-settings.png), using owned 0.20.0 metadata and an isolated in-memory store.
- Node 22 typecheck, build and 204 local tests passed: 203 executed/passed, one Win32-only case skipped on macOS. Actual renderer UI tests run in headless Chrome with a fake bridge and check default-off state, manual checks, version text and release-page actions without invoking installation or login registration.
- Tests cover corrupt settings preservation, failed writes, request cancellation, duplicate checks, restart cooldown, no newer stable version, malformed metadata, exact repository URLs, redirects, bounded responses and rate-limit backoff. Requests time out after 15 seconds and cap response data at 512 KiB; startup with reminders disabled makes no requests or timers.
- Release app build, mounted DMG checksum/files/signature/Applications-link verification and `git diff --check` passed.
- Independent read-only review identified and verified fixes for cached Mac results being presented as fresh, future check timestamps, inherited HTTP credentials, startup fallback and the Windows disable/write race. No important unresolved findings remained.

## Local acceptance

Installed `/Applications/T-Cube.app` version 0.19.0 build34 and verified its running executable path. The maintainer quit 0.18.1 normally. Previous app copies and all four existing recursive JSON files were backed up before and after quitting under ignored `build/install-backups/0.19.0/20261102-164345/`. JSON bytes matched the post-quit backup after replacement. Real launcher/user data was never replaced by fixtures.

Installed and built executable SHA-256: `e5e68285915eeb534a6b4a64dc154dd930a360c0ef8d3ce142e67e9dc3ddb6ca`. Deep/strict code-signature verification passed. The computer-use native service failed to connect, so installed desktop interactions could not be manually exercised. Native settings rendering, actual anonymous networking, injected dialog callbacks and UI behavior were verified separately through tests. Real automatic reminders remain off by default.

## Remote acceptance

[Windows source installation CI](https://github.com/gd0306/t-cube/actions/runs/41415492076) passed on Windows 2022 and 2025 at `b706db4c45bbe47a7e4f86b04e3412231c94a27a`. Each target-platform suite passed 203 tests with one macOS Chrome-only UI fixture skipped. Native installed UI assertions verify the reminder mode, default-off checkbox, enabled manual checks and hidden installer action. Existing native input, clipboard, backup, website titles and rendering checks passed using isolated fixtures.

[Actual NSIS installation verification](https://github.com/gd0306/t-cube/actions/runs/41415526250) passed on the first attempt. Downloaded both native diagnostic artifacts and checked their 24 successful desktop results. Installer `SOURCE_COMMIT.txt` exactly matches the source commit above; the downloaded executable matches its build-provided checksum.

Existing local macOS signing and unsigned Windows distribution remain unchanged.


Published [0.19.0](https://github.com/gd0306/t-cube/releases/tag/v0.19.0) as the latest stable release. The remote tag and installer source record match the verified feature commit. All three remote asset digests match local files; the publicly downloaded checksum manifest is byte-identical.

| Asset | SHA-256 |
| --- | --- |
| T-Cube-0.19.0-macos-arm64.dmg | 43103f5b9450946d5f261d2e90c6c0fcef6573bf19bc0cee4f342cf9191ae0df |
| T-Cube-0.19.0-windows-x64-setup.exe | 294374415272b3a99cf028f01ed772f843913ed07864797a86c4152c22d17a17 |
| SHA256SUMS.txt | f1a709081a9a583dfe8a4371e13dd7a0ffa608a194620eb386ba3eabd2bace0e |
