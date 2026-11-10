# Repository Guidelines

T-Cube is a macOS 15+ launcher built with Swift 6, AppKit, SwiftUI, and RealityKit.

## Project Structure & Module Organization

- `Sources/CubeCore/`: configuration, persistence, face geometry, icon picking, rotation, and theme models. Keep reusable logic independent of UI frameworks.
- `Sources/TCube/`: application lifecycle, floating windows, native input, RealityKit rendering, settings, and launch services.
- `Tests/CubeCoreTests/` and `Tests/TCubeTests/`: core behavior and native application tests, respectively.
- `Resources/`: bundle metadata and installation instructions. `scripts/` contains app, icon, and DMG tooling.
- `docs/`: design notes, implementation plans, and verification records. Generated apps and disk images belong in ignored `build/`; caches and previews belong in `.build/`.

## Build, Test, and Development Commands

Install full Xcode and select its developer directory before building.

- `swift build --scratch-path .build/app`: compile the package.
- `swift test --scratch-path .build/tests --no-parallel`: run core and native tests.
- `bash scripts/build-app.sh --debug`: create a locally signed debug app; omit `--debug` for release.
- `open build/T-Cube.app`: run the bundled menu-bar application locally.
- `bash scripts/build-dmg.sh`: build the app and package an installer.
- `bash scripts/verify-dmg.sh`: mount and verify the current DMG, signature, files, and installation links.
- `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter GlassRenderPreviewTests`: export native PNG/GIF previews.
- `git diff --check`: detect whitespace errors.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Follow existing Swift formatting; no formatter or linter configuration is checked in. Mark AppKit/UI state with `@MainActor`. Share layout definitions between drawing and hit testing. Preserve backward-compatible decoding when adding settings.

## Testing Guidelines

Use Swift Testing (`@Test`, `#expect`) for behavior and synchronous XCTest for nested AppKit event queues. Name tests after observable outcomes. No numerical coverage threshold is configured; add focused regression cases for changed behavior. Run GUI-dependent tests in a logged-in macOS session. Use temporary configuration stores and capture launch callbacks instead of opening external apps.

## Commit & Pull Request Guidelines

History is sparse and mixed; follow the descriptive `feat: add ...` example rather than generic messages such as `save`. Keep commits focused. PRs should explain behavior, link relevant issues, list verification commands, and include native screenshots or GIFs for visual changes. Distinguish automated checks from manual desktop testing.

## README & Documentation Style

The maintainer-approved baseline is the bilingual README layout introduced in `e2427c2`. Preserve this structure and presentation in future project updates; update the relevant sections in place rather than appending a new top-level section for every release or feature.

- Keep `README.md` in English and `README-CN.md` in Simplified Chinese, with matching section order, feature coverage, version information, commands, images, and reciprocal language links. Use natural wording in each language while preserving the same facts. Keep Windows-specific implementation and troubleshooting details in `windows/README.md` and link to it from both root READMEs.
- Preserve the centered HTML brand block: 96 × 96 app icon, centered project name, a short bold product description and two supporting lines, the release/platform/rendering/license/stars badge row, and the language switcher. Keep existing badge styles, destinations, and descriptive alt text consistent.
- Keep the main reading order: **Download Installers → Preview → Core Features → Controls & Gestures → Getting Started & Configuration → Build from Source → Local Data & Privacy → Development & Verification**, with horizontal rules between major sections. Preserve the corresponding Chinese headings and hierarchy.
- Present downloads as a table with platform, published version, installer filename/link, architecture, and requirements/notes. Keep release/checksum links and upgrade notes in a GitHub `NOTE` callout. Distinguish published installer versions from newer source versions; do not point downloads at an unpublished release or assume both platforms share the same version.
- Keep the preview presentation: centered 760px main image, paired 370px idle/material images in an HTML table, and a 760px motion GIF inside `<details>`. The website-title example uses 220px. Keep assets under `docs/images/`, provide useful alt text, and retain the note about native renders, sample icons, consistent backdrop/camera/viewport, and enlargement. Use real current captures when behavior or visuals change.
- Organize core features under the existing five emoji-led groups: material/motion; six-face launchers; desktop/display controls; clipboard/reusable content; performance/power saving. Use concise bullets with bold feature names and concrete behavior. Preserve relevant limits, units, defaults, timing, platform support, fallbacks, permission requirements, and privacy boundaries; check these against the implementation when they change rather than treating old prose as a permanent factual guarantee.
- Keep gesture mappings in a two-column table and initial configuration in a short numbered list. Menu paths and button names must follow the current platform UI, including which settings apply immediately and which need an explicit Apply action.
- Keep source-build instructions split into macOS and Windows, each with runtime/build/architecture requirements and copyable `bash` or `powershell` blocks. Keep each platform's local-agent installation prompt in its own `<details>` block with a `text` fence. Include quitting the old version, preserving configuration, and reporting prerequisite or approval failures.
- Use inline code for versions, paths, commands, shortcuts, flags, and template placeholders. Keep deeper engineering/verification detail in `docs/` and link it from the README. When a feature or release changes, synchronize affected bilingual prose, download metadata, screenshots, commands, and platform notes without replacing the established layout.

## Configuration & Data Safety

User data lives at `~/Library/Application Support/T-Cube/configuration.json`. Never overwrite it with fixtures or silently replace corrupt configuration. Build scripts use ad-hoc signing; Developer ID signing and notarization are separate release tasks.

## Local Version Acceptance

When working on the maintainer's Mac, install each completed new version into `/Applications/T-Cube.app` and verify it locally before reporting completion. Quit the running app normally, preserve the previous application under ignored `build/`, and back up the existing user JSON files alongside it without replacing them with fixtures. Verify the installed executable matches the built version and distinguish manual desktop checks from automated tests.

## Release Acceptance

When delivering a maintainer-requested published version, a source push and local installation are intermediate steps. Do not report the release complete until both platform installers have been built from the same full commit SHA, the actual packaged apps have been verified, GitHub latest points to the new stable release, and both root READMEs plus `windows/README.md` link to the published files. Verify remote asset sizes and SHA-256 values, `SOURCE_COMMIT.txt`, the release tag, and unauthenticated public downloads. Preserve prior releases and report any incomplete platform or verification limit explicitly. Follow [docs/releasing.md](docs/releasing.md).
