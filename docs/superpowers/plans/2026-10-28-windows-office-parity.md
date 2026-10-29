# Windows office parity and installer

**Goal:** Bring current macOS practicality/content-library features to Windows, publish verified Windows 0.16.0 installer and push the integrated source.

**Architecture:** Keep Electron's sandbox and role-authorized IPC. Independent validated stores for content library, display positions and preferences. Main-process services own dialogs/files/clipboard/login/updater; renderer owns app-native controls. Host retains existing gesture/launch behavior.

## Tasks
- [x] Hover-delay migration and bounds, normalized per-display memory with display-add/remove/metrics handling, topology fallback without erasing disconnected memory.
- [x] Common content library: explicit capture/drop review, add/edit/delete, grouping/favorites/search/stable ordering, full/field copy and focus-checked paste, global shortcut/tray/widget entry.
- [x] Validated config+library import/export, automatic pre-import and manual backups, rollback/corrupt and path-alias protections, explicit broken-launcher relink.
- [x] Login toggle with actual OS state and signed updater integration; unsigned builds visibly gated, Authenticode packaging environment documented. Do not fabricate keys/certificates or weaken signature verification.
- [x] Default idle saver stops rendering, optional continuous idle 15 Hz, interaction 30 Hz, hidden/static stop, immediate wake, click feedback. Low-rate host polling while hidden/resting preserves hover responsiveness.
- [x] Bounded, role-authorized IPC and main-frame enforcement for new services. Local Node22 tests/typecheck/build, Windows 2022/2025 source runtime checks, actual NSIS install regression.
- [ ] Review/fix, push verified source to master, download exact-source installer, compare checksums, publish Windows 0.16.0 Release and verify remote assets/tag. macOS and Windows artifacts share version 0.16.0.

**Constraints:** Preserve existing configurations, default glass, shared themes, native drag/Ctrl/rotation, application discovery and icon behavior. Tests use isolated directories. Common content and backups stay local. Native Win32 paste must validate original target/focus and avoid submitting forms. No sensitive clipboard history monitoring. Production signing/updater activation depends on owner-provided certificate credentials.
