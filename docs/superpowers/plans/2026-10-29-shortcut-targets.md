# Extended shortcut targets

**Goal:** Support apps, folders, files, HTTP(S) websites and selected system-settings pages on macOS and Windows; publish 0.17.0 installers and install locally.

**Architecture:** Retain existing URL/path storage and four slots per face. Add file, website and systemSettings kinds. Validate web URLs and restrict settings targets to a built-in platform catalog; launch via the native default application/browser/settings handler. Preserve ordinary app/folder decoding, backup and missing-target repair. Use local or bundled icons without network favicon requests.

**Authorized:** User requested implementation, verification, remote push and Release publication; standing instruction requires local installation and verification. No additional approval needed for those steps.

- [x] macOS core/model, launcher, icons, add/replace UI, maintenance, regression tests.
- [x] Windows schema, native host, renderer, icons, maintenance, regressions and native smoke.
- [x] Review both implementations, run full tests/builds, increment versions to 0.17.0, document behavior.
- [ ] Commit/push, run Windows CI/installer workflow, build and verify macOS DMG, publish matching source and installers with hashes.
- [ ] Back up installed app, install release build, verify native UI and preserve user data; record results.

Validation must reject unsafe schemes and incorrect kind/target combinations. Tests capture launch callbacks and use temporary stores; never open external apps from unit tests. System settings are selected from a fixed catalog, not arbitrary URI input. New targets must survive save/load and configuration backup/import. Windows native smoke uses isolated userData. Native manual tests must be distinguished from automated checks.
