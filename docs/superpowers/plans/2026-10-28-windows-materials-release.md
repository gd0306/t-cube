# Windows Material Parity and Desktop Release Plan

**Goal:** Match the native Mac's independent glass/slime materials on Windows, push verified source, and publish native macOS and Windows installers in GitHub Releases.

**Architecture:** Keep the existing nine themes shared. Persist `appearance.material` independently and port the native spring/deformation model into the Windows core. Stream a deformable shell buffer while icon geometry and hit testing remain stable. Build a native Windows x64 NSIS installer in Windows CI and a native macOS ARM64 DMG locally from the same release commit.

**Tech stack:** Swift 6, Electron, Three.js, TypeScript, Node.js 22, NSIS, GitHub Actions and Releases.

**Requirements:** User-approved scope in this conversation, including approval to publish installers to Releases instead of Packages.

## Constraints

- Default material stays glass; legacy configuration without `material` loads as glass. Do not replace user configuration with fixtures.
- All nine existing themes/custom colors/automatic cycling support both materials. Theme changes preserve material and live deformation; material changes reset the shell.
- Preserve native movement/rotation, Ctrl resize/drag, icon launching, six groups and four slots, installed app discovery, placement and Reduce Motion behavior.
- Windows installer targets Windows 10 22H2/11 x64, per-user, preserves AppData, includes runtime/native dependencies, and requires no Node installation for end users.
- Release version is 0.15.0 on both platforms. Clearly identify macOS ARM64 and Windows x64 artifacts and existing signing/notarization status.
- Publish only installers built from the verified release commit, with SHA-256 checksums.

## Task 1: Windows schema and motion

- [x] Add `Material = 'glass' | 'slime'` and required `Appearance.material`; normalize missing legacy fields and validate present values.
- [x] Preserve material in `resolveAppearance` and keep palette entries independent of it.
- [x] Port `SlimeMotion`/`SlimeDeformation` from Swift with bounded time, contact lag, damping, release overshoot and analytic normal deformation.
- [x] Run focused tests using Node 22: `node --import tsx --test tests/configuration.test.ts tests/slime.test.ts` from `windows`.

## Task 2: Windows rendering and settings

- [x] Add a reusable deformable shell wrapper with stable topology/UVs and geometry regression tests that first fail without the implementation.
- [x] Use the original shell for glass and the cloned streaming shell for slime. Update optical layers and wet tint without changing icon geometry.
- [x] Track native pointer screen position, reproject after hover resizing/rotation, release during drag/exit, and honor Reduce Motion.
- [x] Add a separate always-available material selector; theme selection and cycling retain material.
- [x] Extend installed runtime smoke checks for real material controls, pointer deformation, release/reset, theme independence and rendered coverage on light/dark backgrounds.

## Task 3: Windows installer pipeline

- [x] Add a pinned electron-builder dependency and NSIS per-user configuration including Koffi binaries.
- [x] Add packaging commands and a Windows workflow that checks/types/tests/builds, installs the actual generated executable silently to an isolated directory, and runs the existing smoke suite against that installed runtime.
- [x] Upload installer, checksum and smoke diagnostics as workflow artifacts; no automatic publication before validation.

## Task 4: Same-commit verification and packages

- [x] Run Windows tests/typecheck/build locally and native Mac tests.
- [x] Review changes, update both versions/docs, commit and push master.
- [x] Run Windows CI checks on both supported Windows runners and build/install/smoke-check the packaged x64 installer.
- [x] Build and mount/verify the release Mac DMG; retain generated packages under ignored `build/`.

## Task 5: Publish Release

- [x] Confirm artifact commit/version matches verified source, collect checksums and release notes with precise architecture/signing information.
- [x] Create a draft release for v0.15.0, upload both installers/checksum manifest, verify assets, then publish it.
- [x] Return release/download links and a concise verification summary.

Completed release: [v0.15.0](https://github.com/gd0306/t-cube/releases/tag/v0.15.0). Both installers use source `7b02bf8d612687777a685ffa9541e5a110b762cd`; see [verification record](../../verification/2026-10-28-v0.15.0-release.md).
