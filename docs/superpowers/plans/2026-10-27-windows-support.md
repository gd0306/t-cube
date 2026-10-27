# Windows Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Execute implementation tasks sequentially and review each task before continuing.

**Goal:** Provide a Windows 10/11 x64 source client and local installation script with the native client's feature set.
**Architecture:** Electron main/preload boundary, Three.js curved renderer, testable TypeScript core and Win32 input helpers; native macOS code remains unchanged.
**Tech Stack:** Node 22, Electron 45, TypeScript, Three.js, Koffi, esbuild, Node test runner, Playwright.
**Spec:** `docs/superpowers/specs/2026-10-27-windows-support-design.md`

## Global Constraints

- Work only in this linked worktree. Preserve `AGENTS.md` and native Swift implementation.
- Four-space indentation, named modules, strict TypeScript; no remote resources.
- Tests use isolated configuration and captured launch callbacks. Never modify personal app data.
- Controller owns dependency setup, packaging, native helpers, CI and final documentation. Implementers own only their task files. Do not spawn subagents.
- Shared types in `windows/src/shared/contracts.ts` are the interface authority; discuss changes before altering them.
- Run `npm test` and `npm run typecheck` from `windows/`. Report actual commands and outcomes. Use focused tests while iterating.

## Task 1: Core behavior and geometry

**Files:** create `windows/src/core/{configuration,geometry,rotation,hover,store}.ts`, `windows/tests/{configuration,geometry,rotation,hover,store}.test.ts`. Shared contract changes require controller agreement.

- [x] Write failing Node tests first for sparse four-slot groups, duplicate paths only within a group, defaults/backward-compatible normalization, malformed values, and corrupt-file preservation.
- [x] Implement defaults and validation matching Swift configuration. Export `defaultConfiguration()`, `normalizeConfiguration(input)`, `THEMES`, `resolveAppearance(config, elapsedSeconds)` and target/group editing helpers as needed. Theme cycling is deterministic and disabled cycling returns manual appearance.
- [x] Implement atomic serialized `ConfigurationStore` with `load()`, `snapshot`, `update(edit)`, `backupAndReset()`. A failed load must prevent accidental overwrite. Temporary test directories only.
- [x] Implement Three-compatible `createBodyGeometry()`, `createFaceGeometry(face)`, `faceQuaternion(face)`, `DISPLAY_TILT`, `iconSlotAtUV(u,v)`, and `pickCube(ray, quaternion, direct)` returning `{face,slot}` or null. Read `SoftGlassGeometry.swift`, `CurvedFaceGeometry.swift`, `CubeFacePicking.swift`, `FaceLayout` and native tests. Body has no seams; icon picking uses actual rendered triangles and nearest surface. UV rectangles must match native 1024 layout. No flat-plane approximation.
- [x] Implement `applyScrollRotation(quaternion, dx, dy, precise)` using native display-tilt-aware yaw/pitch, clamp precise deltas, no snapping; export seeded `IdleRotation` with `step(dt,paused)` and `PrismMotion` matching native easing, speed and Reduce Motion behavior. Tests verify pause/resume, normalization, two axes, no accumulated paused time.
- [x] Implement `HoverGeometry` (interface in contracts) using global DIP coordinates, resting size 164*scale, pointer-anchored Ctrl shrinking, hover multiplier, drag geometry freeze, screen work-area clamping and 24px quick placement. Read `CubeHoverController.swift` and native hover tests. Tests cover exit restoration, release-Ctrl during drag, placement while enlarged, and negative display coordinates.
- [x] Run focused and then full core tests/typecheck, self-review, commit ONLY owned files, write task report with RED/GREEN evidence.

## Task 2: Electron host and secure bridge

**Files:** create `windows/src/main/{index,application,ipc,icons}.ts`, `windows/src/preload/index.ts`, `windows/tests/{host,ipc}.test.ts`; additional small main modules allowed when responsibilities are distinct. Controller provides native helpers and build scripts.

- [x] Read contracts and Task 1 exports. Write failing behavior tests around gesture completion/late renderer release, host state updates and IPC role authorization.
- [x] Implement frameless transparent always-on-top cube, 220px four-icon expansion and settings windows, tray with show/hide/settings/placement/size/quit. Keep development data isolated on macOS; allow explicit `TCUBE_USER_DATA_DIR` for smoke tests. First launch opens settings. Preserve corrupt configuration using an explicit backup/reset dialog.
- [x] Poll controller-provided `readInputState()` and Electron cursor in DIP. Host controls hover/Ctrl and dragging beyond the window. A gesture ID guarantees one release, no launch after drag, no double dispatch when native release precedes renderer release; right-click-without-drag opens settings. Left and right drag threshold 5 DIP. Ctrl is move-only and freezes resting geometry until release. Save resting origin only.
- [x] Use pure core configuration store for serialized operations; native pickers and file drop accept local executable/shortcut files or folders. Only stored slots may launch via `shell.openPath`. Keep 4-slot positions and same-group duplicate rule. Theme rotation broadcasts actual displayed appearance; honor Reduce Motion and hidden-state animation suspension.
- [x] Cache high-resolution target icons using native helper with `app.getFileIcon` fallback and separate icon-state broadcasts. Renderer sees data URLs, never native-image objects. Native handles must be released.
- [x] Implement typed preload bridge and narrow validated IPC. Validate sender role/main frame and payload bounds, block remote navigation/new windows, enable sandbox/contextIsolation, disable Node integration. Use preload `webUtils.getPathForFile` for drop files.
- [x] Tests cover untrusted/invalid IPC, drag click suppression, configuration preservation and launch failure reporting. Run full tests/typecheck, self-review, commit only owned files and report RED/GREEN evidence.

## Task 3: Curved widget and settings renderer

**Files:** create `windows/src/renderer/{widget,settings,expanded}.ts`, corresponding `.html` and CSS, renderer utility modules and `windows/tests/renderer.test.ts` as needed.

- [x] Read contracts/core/host and existing native appearance. Build an actual usable desktop UI, not a marketing page. Use local assets and CSP; DOM text must use `textContent` for target names.
- [x] Use shared quartic body and curved face meshes, accurate UV layout, padded icon textures to prevent black outlines, opacity 0.25 for glass only. Nine theme styles, restrained dynamic iridescent light and graceful Reduce Motion. No thick edge framework, name labels or empty-slot UI on cube. Share mesh picking with core. Export a controller object exposing scene/cube/camera for smoke inspection (normal application architecture, no test-only IPC).
- [x] Render at at most 30Hz and stop while hidden. Idle rotation stops immediately on hover, wheel rotates both axes at the cursor without snapping. Bridge pointer begin/end including exact picked face/slot; never launch directly on pointerdown. Maintain gesture even when renderer misses native release.
- [x] Expanded face contains only four configured icons, no titles or close button; Escape closes. Background translucent liquid glass; use native backdrop when available.
- [x] Settings provide six named groups, four stable slots, add application/folder, drag/drop, remove/reorder, nine themes, custom colors/glow, cycle selection and 10/20s, hover enable/multiplier1.1–4, resting scale0.65–1.6, idle rotation, expansion toggle, quick placement and quit. Display errors. Settings changes persist through host.
- [x] Add focused tests for shared renderer logic where meaningful. Build/typecheck/tests and capture the actual Windows runtime using isolated data (Mac preview is optional). Self-review, commit owned files, report limitations and evidence.

## Task 4: Platform integration, source installation and delivery

**Controller-owned files:** `windows/package*.json`, `tsconfig.json`, `scripts/*`, `assets/*`, `src/native/*`, `.github/workflows/windows.yml`, `.gitignore`, `README.md`, `README-CN.md`, `docs/verification/*`.

- [x] Install exact dependencies, build main/preload as CJS and renderer as bundled local ESM; strict typecheck. Generate ICO from existing native app icon sizes; no design replacement.
- [x] Add Koffi Win32 input and Reduce Motion helpers with correct swapped-button and non-Windows fallback. Implement shell high-resolution icon extraction and resource cleanup with safe fallback.
- [x] PowerShell source install/update script using npm ci/build, per-user runtime and shortcut creation. No installer binaries. Keep version0.13.0 Windows-specific until native release changes.
- [x] Add Windows CI on windows-2022/windows-2025: npm ci, tests, typecheck, build, source installation and app smoke. Capture screenshots and upload smoke screenshots/logs. Use native input injection in smoke tests where available, isolated stores and physical/DIP conversion. Verify Ctrl hover shrink, outside drag release, quick placement, four-icon popup and direct launch behavior.
- [x] Run relevant renderer checks; push the feature branch and obtain actual Windows build results. Use public Actions reads if the connector cannot create a draft PR. Investigate/fix CI failures until passing. Never describe unexecuted hardware tests as passed.
- [x] Update English/Chinese READMEs with platform-specific install/build commands, feature parity and verified limitations; add Windows screenshots from actual app captures.
- [x] Final branch review after actual test evidence, ensure clean diff and preserve native app functionality. Provide source/commit links and concise verification summary.
