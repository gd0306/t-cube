# macOS desktop practicality verification

Implementation branch: `feat/macos-content-library`, based on the approved common-content prototype. macOS source version 0.16.0 / build 27. This task targets macOS; Windows remains separately versioned.

## Delivered behavior

- Configurable hover-entry delay (default 0.18 seconds, 0–1.5 supported), immediate exit, canceled pending entry during drag/reset/stop; enlargement constrained to the display; a short native click-feedback ring.
- Display UUID + normalized resting-position memory in independent `desktop-positions.json`. Disconnection selects a visible fallback without erasing the disconnected display record; resolution/layout changes reproject remembered positions. User moves/quick placement commit a new preferred display.
- Validated JSON export/import of launcher settings and the common-content library, replacement preview, automatic pre-import backup, manual backup/list/reveal/restore, and explicit broken-slot relinking. Multi-file failures roll back original bytes. Export rejects live-file aliases through symlinks, hard links and case variants. Corrupt/unsupported live data blocks replacement. Restoring another scale preserves the imported position and reloads the visible content library.
- System-managed login-item toggle, actual status/approval/error display, settings link. No login registration occurs on launch or merely viewing settings.
- Official Sparkle 2.10.0, pinned by package revision/checksum; standard authenticated update UI/settings, HTTPS feed and 32-byte EdDSA public-key validation. Missing key visibly disables application updates. Packaging embeds/re-signs nested framework helpers and supports Developer ID + Hardened Runtime/timestamps and optional notarization/stapling.
- Idle animation property updates are 15 Hz rather than interactive 30 Hz; no private RealityKit frame-rate API is used. Hidden/occluded render views detach and cancel update subscriptions. With idle rotation disabled or Reduce Motion, a settled visible frame is retained as an image and the live ARView detaches; input/configuration/visibility restore it. Snapshot failure retains the live view for correctness and can miss GPU savings.

## Automated validation

`swift test --scratch-path .build/tests` passed: 4 XCTest, 73 native Swift Testing and 98 core cases. Three opt-in render export cases are skipped during this normal run. Important regressions include hover timing/cancel/bounds, simulated display disconnect/reconnect, archive rollback and alias protection, restored scale/position callbacks, live content reload, update configuration policy, and actual ARView snapshot → detach → mouse-entry reattachment. Existing drag queues, direct launches, rotation, slime and theme behavior pass.

`swift build --scratch-path .build/desktop-app`, `bash scripts/build-app.sh` (release), `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh`, plist/script lint and `git diff --check` passed. Bundle verification includes nested Sparkle code signatures. Review findings concerning export aliases, imported-position mutation and rendering/input ownership were fixed and regression-tested.

## Local desktop inspection

Installed the validation build at `/Applications/T-Cube.app`, verified its deep signature and opened settings. Confirmed four settings tabs, real launcher configuration, backup controls, broken-launcher scan, login/update status and missing-key message. Created one protective backup using the real UI; no fixture data or restore was applied to the user's live data. Previous installed app preserved under `build/backups/T-Cube-before-desktop-practicality.app`.

Manual limitations: physical monitor unplug/replug was not performed; simulated display regressions cover topology changes. No CPU/GPU/power benchmark is claimed. Login toggle remained off: this local ad-hoc build reported SMAppService `notFound`; registration, system approval and a real login cycle require user trial. Only an Apple Development identity exists locally, not Developer ID Application. Production signing/notarization and a signed update install/relaunch/tampered-archive rejection remain unverified until the owner supplies release credentials and EdDSA configuration. See `docs/updates/RELEASE-GUIDE.md`. The feed is empty and no Release is published by this task.

Integration: implementation commit `e20f0bd` (following content-library prototype `7947319`) was fast-forwarded into `master` and pushed to origin. No macOS CI workflow exists in this repository; local verification above is the validation evidence. Existing Windows workflows are path-filtered and are not evidence for these macOS changes.
