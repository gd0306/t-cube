# T-Cube macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a locally runnable floating cube launcher with six editable groups, real app/folder launchers, drag rotation, and persistent settings.

**Architecture:** A Swift Package separates testable `CubeCore` from the native `TCube` executable. AppKit owns the transparent panel and pointer events, RealityKit owns six textured faces, and SwiftUI owns the editor. A build script assembles a local application bundle.

**Tech Stack:** Swift 6, macOS 15+, AppKit, SwiftUI, RealityKit, Swift Testing, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-23-macos-cube-design.md`

## Global Constraints

- 最低 macOS 15，无第三方运行依赖。
- 六面六分组，每面四个入口，支持本地应用和文件夹，不移动、复制或删除用户文件。
- 拖动旋转、松手吸附、Option＋拖动移动；拖动后不得触发点击。
- 默认深灰磨砂，集中管理主题；海洋、星空、花海为后续功能。
- 自动保存分组、入口、尺寸和位置；损坏配置不静默覆盖。
- 不包含 App Store 发布、公证、开机启动、全局快捷键、主题切换和多立方体。

## File responsibilities

`Package.swift` declares the core library, executable, and tests. `Sources/CubeCore/` contains models, persistence, quaternion geometry and pointer decisions. `Tests/CubeCoreTests/` exercises real state transitions, geometry and disk I/O. `Sources/TCube/` contains application lifecycle, window control, scene drawing, local file integration, theme tokens and editor. `scripts/build-app.sh` assembles `build/T-Cube.app`. `Resources/Info.plist` identifies the app. `README.md` explains building and operation.

### Task 1: Core state, persistence and rotation

**Files:** `Package.swift`, `Sources/CubeCore/*.swift`, `Tests/CubeCoreTests/*.swift`.

**Interfaces:** Produce public Codable/Sendable models for six faces and four optional item slots, configuration edits that reject duplicate/full/invalid operations, a versioned atomic disk store, quaternion functions for drag/nearest-face/upright snapping, and a drag classifier that remembers threshold crossings. Expose AppKit-independent interfaces and document exact names in the task report for Task 2.

- [x] Write behavior tests before production code. Include full group refusing a fifth item without mutation; same-group duplicates refusing insertion; reorder preserving all entries; application and folder Codable round trips; persisted position and scale round trips; corrupt JSON throwing without replacing bytes; six hand-checked face normal/orientation fixtures; and drag-out-then-back remaining a drag.
- [x] Run `swift test --scratch-path .build/tests` and capture the expected missing-feature failures before implementing. Derive assertions from literal expected values, not the implementation's geometry helpers.
- [x] Implement the smallest public interfaces supporting these tests. Use `simd_quatf` for geometry, atomic Foundation JSON writes, and validated fixed-size face groups. Snap orientation must keep labels upright and may retain a small consistent display tilt.
- [x] Run `swift test --scratch-path .build/tests`; inspect all failures and fix the implementation. Record test counts and interface names in the report.

Core consumer example (names may be finalized in Task 1 report):

```swift
var configuration = CubeConfiguration()
let folder = LauncherItem(url: URL(fileURLWithPath: "/tmp"), name: "临时文件", kind: .folder)
try configuration.add(folder, to: .front)
try ConfigurationStore(url: temporaryURL).save(configuration)
```

### Task 2: Native floating cube and content editor

**Files:** `Sources/TCube/*.swift`, app boundary tests when deterministic AppKit-independent behavior is introduced.

**Interfaces:** Consume the exact public API from Task 1. Produce a macOS executable entry point, persistent shared application model, status menu and transparent panel, six-face RealityKit renderer, file/URL launcher service, and editor window.

- [x] Read Task 1 report and the SDK RealityKit interfaces before wiring the scene. Test any new nontrivial deterministic behavior (slot hit mapping, restore-position clamping, file type validation) before implementing it; use real temporary directories and `.app` fixtures where possible.
- [x] Build the application entry point with `NSApplication`, accessory activation policy, `NSStatusItem`, and nonactivating borderless `NSPanel`. Set floating level and keep visible across normal app switches. Clamp restored window origin to an attached screen.
- [x] Build a RealityKit view with transparent environment, a perspective camera, rounded graphite cube body, six oriented face textures, and collision geometry. Draw system icons, labels, group title and empty slots into textures. Centralize colors/material parameters in `CubeTheme`.
- [x] Route mouse down/drag/up through the core drag classifier. Drag updates the root quaternion, mouse up animates to upright nearest-face orientation, and completed drag cannot launch. Option dragging moves the panel. Idle front-face hit selection opens an item or a file picker for an empty slot.
- [x] Accept Finder file URL drops for apps/folders into the active group. Report duplicates, unsupported files and capacity failures without replacing entries. Resolve bookmarks before opening targets with `NSWorkspace` and surface failures.
- [x] Add native editor with six selectable groups, editable title, four slots, add/remove and reorder controls; provide display/hide, editor, size and quit menu actions. Save edits and window settings atomically. Preserve corrupted configuration and show recovery feedback.
- [x] Run `swift test --scratch-path .build/tests` and `swift build --scratch-path .build/app`. Fix compile errors against the installed SDK and inspect warnings.

### Task 3: Bundle, runtime validation and documentation

**Files:** `Resources/Info.plist`, `scripts/build-app.sh`, `README.md`, verification notes and plan checkboxes.

**Interfaces:** Consume the `TCube` executable; produce `build/T-Cube.app` with bundle ID `local.tcube.launcher`, version `0.1.0`, `LSUIElement=true`, minimum macOS 15 and high resolution support.

- [x] Write a build script using `set -euo pipefail`, Swift build product lookup, `mkdir -p` and `cp` to assemble the bundle without deleting unrelated files. Support release by default and a debug option. Ad-hoc sign the local app if supported by the environment.
- [x] Run `bash scripts/build-app.sh`; inspect bundle metadata and executable architecture. Run the full test suite and `git diff --check`.
- [x] Launch the built app using a supported native UI surface or approved `open` command. Inspect the real window, rotation, menu and editor where automation is available, capturing a screenshot when possible. Record any unverified interactions honestly.
- [x] Write README in Chinese with build/run commands, all mouse gestures, configuration location, missing-target handling, current scope and future theme extension points. Update plan checkboxes from actual evidence.
- [x] Request a final code review covering data preservation, drag/click ambiguity, face orientation, file handling and window lifecycle. Fix material findings, rerun affected checks, and summarize delivery with exact app location and verification limits.

## Execution outcome

All implementation and available automated checks completed on 2026-10-23. Final suite: 20 tests passed. Final release bundle rebuilt, signed, launched and screenshot inspected. Two final-review findings were corrected and passed scoped rereview. Native click/drag automation is unavailable for the nonactivating panel; manual interaction acceptance remains pending as detailed in `docs/verification/2026-10-23-macos-alpha.md`. Checkboxes record completed implementation/available checks, not full manual acceptance. Source remains uncommitted on `feat/macos-cube`.
