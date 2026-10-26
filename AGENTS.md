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
- `swift test --scratch-path .build/tests`: run core and native tests.
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

## Configuration & Data Safety

User data lives at `~/Library/Application Support/T-Cube/configuration.json`. Never overwrite it with fixtures or silently replace corrupt configuration. Build scripts use ad-hoc signing; Developer ID signing and notarization are separate release tasks.
