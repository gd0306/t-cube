# Theme Cycle and Hover Enlargement Implementation Plan

> **For agentic workers:** Use executing-plans to implement these tasks inline; check each task against the user's requested behavior before continuing.

**Goal:** Add configurable 10/20-second multi-theme cycling and automatic cube enlargement while the pointer is over the cube.

**Architecture:** Persist cycle and hover preferences with backward-compatible defaults. Keep the active rotating appearance and enlarged window frame transient. A window controller owns hover geometry, pointer tracking, and conversion of an enlarged drag position back into the resting position.

**Tech Stack:** Swift 6, CubeCore, AppKit, SwiftUI, RealityKit; no dependencies.

**Spec:** User request on 2026-10-25: select multiple color themes and cycle every 10 or 20 seconds; idle cube remains small; pointer entry enlarges it without clicking; pointer exit restores its size. Latest 0.6.1 steering doubles the preceding hover effect, setting default enlargement to 4× (width and height relative to idle), adjustable in Appearance. Existing transparent icon-only faces and immediate face launcher remain.

## Global Constraints

- macOS 15 minimum, native transparent Liquid Glass on macOS 26+.
- Preserve existing apps, folders, appearance, resting scale, and position when loading old configuration.
- Hover transitions never write a temporary enlarged position to disk; no position drift across repeated entry/exit.
- Hover resizing is held during a pointer gesture so dragging and clicking use stable coordinates.
- Theme ticks update only the displayed aura; they do not rewrite configuration every 10/20 seconds.
- No remote push is part of this development request.

## Task 1: Persisted preferences and deterministic theme selection

Files: `Sources/CubeCore/CubeThemeCycle.swift`, `Sources/CubeCore/CubeHoverSettings.swift`, `Sources/CubeCore/Core.swift`, `Tests/CubeCoreTests/ThemeCycleHoverTests.swift`.

Interfaces: `CubeThemePreset` provides six named gradient pairs and `appearance(glowIntensity:)`; `CubeThemeCycle` stores `isEnabled`, ordered `themes`, `intervalSeconds` and `next(after:)`; `CubeHoverSettings` stores `isEnabled`, `multiplier`; `CubeConfiguration` owns `themeCycle` and `hover` with `decodeIfPresent` defaults.

- [x] Add tests for round-trip and legacy decoding, valid 10/20 intervals, at least two unique enabled themes, finite hover multiplier 1.1...4.0, and cyclic order.
- [x] Run `swift test --scratch-path .build/tests --filter ThemeCycleHoverTests` and observe absent-feature failures.
- [x] Implement the named interfaces and strict validation before atomic saving.
- [x] Run the targeted tests and confirm existing appearance persistence remains green.

## Task 2: Runtime cycle and Appearance controls

Files: `Sources/TCube/AppModel.swift`, `Sources/TCube/EditorView.swift`, `Sources/TCube/CubeView.swift`, `Tests/TCubeTests/ThemeCycleRuntimeTests.swift`.

Interfaces: `AppModel.displayedAppearance`, `activeTheme`, `advanceTheme()`, and `onAppearanceChange`; `CubeView.refreshAppearance()` changes aura without rebuilding six icon textures.

- [x] Verify that cycling changes appearance in configured order, preserves glow, does not change saved bytes on a tick, and stops/restores manual colors when disabled.
- [x] Start one cancellable task when cycling configuration changes, sleeping the configured 10/20 seconds between calls to `advanceTheme()`.
- [x] Replace private preset definitions with the shared six-theme catalog. Add cycle toggle, checkboxes, interval picker, hover toggle/multiplier, and resting-size wording. Apply all preferences atomically through the existing button.
- [x] Confirm invalid selections disable Apply and existing custom colors still work with cycling disabled.

## Task 3: Hover window behavior and stable dragging

Files: `Sources/TCube/CubeHoverController.swift`, `Sources/TCube/TCubeApp.swift`, `Sources/TCube/CubeSurfaceView.swift`, `Sources/TCube/CubeView.swift`, `Tests/TCubeTests/CubeHoverTests.swift`.

Interfaces: `CubeHoverController.configure(baseSize:settings:)`, `pointerChanged(to:)`, `setInteractionActive(_:)`, `commitMovedFrame(_:)`, `onHoverChange`, and `onRestingPositionChange`.

- [x] Test entry enlargement, exit restoration, repeated edge entry/exit without drift, no saves on hover, frozen geometry during gestures, and enlarged-drag persistence as a resting frame.
- [x] Resize around the resting center, clamp to attached screens, and keep resting frame separate from current presentation.
- [x] Connect tracking areas and local/global pointer motion monitors without toggling window input off. Route hover visibility through the controller and suspend resizing from mouse-down until release.
- [x] Replace delegate resizing with controller configuration after initial restoration. Route completed drags through `commitMovedFrame`.
- [x] Confirm existing right/primary drag and immediate-launch tests still pass.

## Task 4: Delivery

Files: `Resources/Info.plist`, `README.md`, `docs/verification/2026-10-25-theme-cycle-hover.md`.

- [x] Mark version 0.6.0/build 11, update instructions for the new controls.
- [x] Run full `swift test --scratch-path .build/tests`, independent focused review, and `git diff --check`.
- [x] Build with `bash scripts/build-dmg.sh` and verify with `bash scripts/verify-dmg.sh`.
- [x] Launch the release, inspect settings, verify a real 10-second color change and hover input behavior where the desktop tool supports pointer movement. Restore the user's existing theme preferences after temporary QA changes.
- [x] Record exact automated/desktop evidence and provide the DMG.
