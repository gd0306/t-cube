# Desktop practicality improvements

**Goal:** Implement the requested five optimization areas on the existing macOS feature branch, verify, merge to master and push. Include the previously approved content library in integration.

**Architecture:** Preserve backwards-compatible launcher configuration; independent files for desktop display preferences, backups and content data; native AppKit interaction and ServiceManagement; standard Sparkle integration for signed updates. UI additions in separate settings tabs.

**Scope:** Current macOS implementation. Existing Windows client remains separately versioned. User authorized current-branch implementation, merge and push; no new Release publication requested.

## Tasks
- [x] Hover: configurable short entry delay; immediate exit/drag/modifier handling, bounded enlarged frame, visible click feedback. Add display-specific normalized resting positions, retain disconnected display memory and recover to visible screen without erasing it. Temporary screens in tests.
- [x] Maintenance: validated import/export of configuration and content library, automatic pre-import backups, backup export/restore via user choice, missing launcher discovery and explicit slot relinking. Never silently replace corrupt or unsupported files; rollback multi-file restores on failure.
- [x] Lifecycle: login item toggle using SMAppService reflecting actual system status; signed-update check/settings using standard update framework, documented public-key/feed requirements; Developer ID/notarization support in packaging with explicit local fallback. Do not invent a distribution identity or commit secrets.
- [x] Rendering: adaptive cadence and actual RealityKit pause while hidden/occluded or static; wake on input/config/show, stop offscreen animation work, retain slime/idle dynamics and Reduce Motion behavior.
- [x] Integration: settings/menu wiring, targeted regressions and complete native tests, bundle/signature verification and local installed UI check. Document manual multi-monitor/performance/update-server/signing limitations.
- [x] Commit on current branch, review, fast-forward or non-destructively merge to master, push remote, verify remote HEAD and triggered checks.

## Validation
Run meaningful regression cases before implementations where practical. Run GUI-dependent suites only once at a time. One final full `swift test --scratch-path .build/tests`, release/debug bundle builds as appropriate, `git diff --check`, inspect native settings. Preserve user's real configuration; all fixtures in temporary stores. Updates must authenticate archives; missing signing configuration must be visible and never downgrade update verification.

Validation and release-credential limitations: docs/verification/2026-10-28-desktop-practicality.md. Signed production update activation is intentionally gated; no credentials created.
