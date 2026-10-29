# Extended shortcut targets / 0.17.0

Apps and folders are joined by local files, HTTP(S) websites and curated system-settings pages. The configuration schema retains old app/folder data. Files use bookmarks on macOS and the default handler on each platform. Website credentials/unsafe schemes and unlisted settings URIs are rejected again at launch. Remote targets skip local missing-target and icon extraction. macOS duplicate matching normalizes host/scheme/root path/default ports and keeps path case; broken local repair preserves target type.

## Local automated verification

- `swift test --parallel --num-workers 1 --scratch-path .build/tests`: passed, 88 native tests plus 106 core tests. Includes archive roundtrip, local file classification, equivalent/distinct URL keys, remote bookmark handling, captured launch handlers and settings handler/icon availability.
- Windows Node 22.19.0: `npm run typecheck`, `npm test` (155 passed, one native Windows skip), `npm run build`: passed.
- `bash scripts/build-app.sh`: release arm64 app built successfully.
- Windows shortcut-dialog smoke helper also passed in real Chrome against the production host and temporary stores. Full Electron macOS preview failed during runtime startup; it is not counted as a native Windows pass.
- Independent code review completed; both requested macOS fixes have regression coverage.
- `git diff --check`: passed.

Windows settings URIs were checked against [Microsoft's settings URI reference](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings). Some pages depend on installed hardware, notably Wi-Fi. macOS destinations were verified against locally installed settings extension identifiers and the system URI handler.

Final CI, packaging, local installation and published artifact hashes: [0.17.0 release verification](2026-10-30-v0.17.0-release.md).
