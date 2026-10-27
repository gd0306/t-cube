# Mouse drag mapping verification

Versions: macOS **0.12.4** (build 24), Windows **0.14.1**.

## Behavior

- Left-button drag moves and saves the floating window position.
- Right-button drag rotates the cube from its starting orientation using total screen displacement. It does not move the window or save a position; releasing keeps the resulting pose.
- The five-point drag threshold suppresses accidental launches, face expansion and settings after dragging. Right-click without dragging still opens settings.
- Ctrl restores resting size, and Ctrl-left drag remains a move-only gesture. Existing wheel and trackpad rotation handlers are unchanged.

## Regression evidence

Before implementation, the changed macOS native event-queue and view tests failed because right dragging moved/saved the window and left its orientation unchanged. Windows host tests also failed because right dragging saved a new window position instead of publishing rotation displacement.

After implementation:

- `swift test --scratch-path .build/tests`: 4 XCTest cases plus Swift Testing runs reporting 44 native and 66 core cases, with no failures. The optional GPU fringe check and render export were skipped.
- `bash scripts/build-app.sh --debug`: built and signed `build/T-Cube.app` successfully.
- Windows local tests: 67 passed, one Windows-only test skipped; type checking and renderer/host builds passed.
- [Windows workflow 40523108281](https://github.com/gd0306/t-cube/actions/runs/40523108281), commit `fa23e33`: both `windows-2022` and `windows-2025` completed successfully. All 68 tests passed on each runner, followed by source installation and GUI smoke verification against the installed Electron application.

The Windows smoke uses native mouse input to verify ordinary left dragging, Ctrl-left dragging and release outside original bounds, horizontal/vertical right rotation outside window bounds, unchanged position during rotation, saved left-drag position, and no face expansion after dragging. Existing application-picker, glass visibility, settings, theme, popup and placement checks also passed. Tests use isolated configuration and owned temporary application fixtures.

Code review found no blocking issues. Cloud runners verify Windows native APIs and the installed client; this is not a separate physical Windows 10/11 hardware acceptance test.
