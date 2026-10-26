# Windows support

## Scope

Add a Windows 10 22H2 and Windows 11 x64 client from source, with local agent installation. Keep the native macOS client unchanged. Preserve six groups of four applications/folders, curved glass and curved icons, nine themes and custom colors, 10/20-second theme cycling, hover enlargement, irregular idle rotation, both-axis wheel rotation without snapping, left/right dragging, Ctrl shrink and Ctrl-left dragging, optional face expansion, tray controls, settings, and five quick placements.

## Architecture

`windows/` is an Electron/TypeScript application with a bundled Three.js renderer. Pure core modules implement configuration validation, geometry, rotation, hover placement and persistence. The main process owns windows, files, launch services, tray, input polling and IPC authorization. A sandboxed preload exposes a small typed bridge. Renderer code has no filesystem or Node access. All assets ship locally.

Reuse the native client's quartic surface (`sum(component^4) = 0.5^4`), face layout and rotation algorithms. Body and icon picking use the same mesh as rendering. Transparent body opacity starts at 0.25; icons remain opaque. Do not introduce thick edge rails or flat floating icons. Empty slots have no visual placeholder on the cube or expansion panel.

## Platform behavior

Use Win32 `GetAsyncKeyState` for Ctrl and mouse buttons, respecting swapped buttons. Track movement in Electron DIP coordinates, retain dragging after leaving the window, and persist only the resting frame. Ctrl release during a drag must not enlarge the widget until release. Expanded windows close on outside interaction or Escape. Windows 11 backdrop support is optional enhancement; Windows 10 receives a translucent glass surface with identical controls.

Configuration is stored atomically in `%APPDATA%/T-Cube/configuration.json`. Corrupt files are preserved and require an explicit reset. Development on macOS uses a separate `T-Cube-Windows-Preview` directory. Test runs use `TCUBE_USER_DATA_DIR`. Only configured targets may be launched. No arbitrary renderer shell commands, remote content or remote navigation are permitted.

## Delivery and verification

Use Node behavior tests and strict TypeScript checks; build the renderer on macOS for visual checks. GitHub Actions builds and smoke-tests the source client on Windows runners. Provide a PowerShell install script and concise local-agent prompt; do not build or publish installers. Distinguish Windows CI evidence from physical Windows 10/11 hardware testing. Push the completed source to the remote repository, preserving the working macOS release.

## References

- [Electron windows](https://www.electronjs.org/docs/latest/api/browser-window)
- [Electron file icons](https://www.electronjs.org/docs/latest/api/app#appgetfileiconpath-options)
- [Koffi native calls](https://koffi.dev/)
- [NSIS packaging](https://www.electron.build/docs/nsis/)
