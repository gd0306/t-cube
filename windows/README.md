# T-Cube for Windows

Windows 10 22H2 / Windows 11, x64. This client uses Electron and Three.js; the repository's macOS client remains native Swift. No installer download is required.

## Let a local agent install it

```text
Install T-Cube from https://github.com/gd0306/t-cube (master) on this Windows PC. Read windows/README.md, install Node.js 22 LTS if needed, and run windows/scripts/install.ps1. Quit the old T-Cube first, preserve its configuration, create shortcuts, and launch it. Report any failed checks.
```

中文提示词：

```text
在这台 Windows 上安装 https://github.com/gd0306/t-cube 的 master 分支。按 windows/README.md 准备 Node.js 22 LTS，执行 windows/scripts/install.ps1。先退出旧版、保留配置，创建快捷方式并启动；检查失败时告诉我原因。
```

## Source installation

Install Git and Node.js **22.12 or newer**. Open a new PowerShell terminal after installing prerequisites. Run as your normal user:

```powershell
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
powershell -NoProfile -ExecutionPolicy Bypass -File windows/scripts/install.ps1
```

The execution-policy override applies only to that PowerShell process. The script installs locked dependencies, type-checks, tests, builds, and copies a standalone Electron runtime to `%LOCALAPPDATA%\T-Cube`. It creates desktop and Start menu shortcuts. Administrator privileges are unnecessary. Keep internet access available for the first npm/Electron download.

Quit T-Cube from its tray or settings before updating. Pull `master` and rerun the script. Configuration remains in `%APPDATA%\T-Cube\configuration.json`; removing shortcuts never deletes their targets. To remove the app, quit it and delete the installation directory and shortcuts. Keep the configuration unless you explicitly want a reset.

Optional script flags: `-InstallDirectory <path>`, `-NoLaunch`, `-NoShortcut`. `TCUBE_USER_DATA_DIR` isolates development/test configuration. Development on macOS uses `T-Cube-Windows-Preview`, separate from the native Mac app.

## Controls

Hover to show icons and enlarge; leave to shrink and resume optional idle rotation. Wheel/trackpad scroll turns both axes without snapping (Shift + wheel turns horizontally). Either mouse button drags the widget. Ctrl temporarily restores its resting size; Ctrl + left drag moves it at that size, including when Ctrl is released mid-drag. Right-click without dragging opens settings.

Each of six groups holds four applications (`.exe`, `.lnk`) or folders. Assign them in settings using the application/folder picker or Explorer drag-and-drop. Choose face expansion (four icons, outside click/Escape to dismiss) or direct icon launching. Nine themes, custom two-color glass, 10/20-second cycling, hover multiplier, idle rotation, resting size and five screen placements are configurable. Tray controls include show/hide, settings, placement and quit.

Windows uses its own translucent glass rendering; Apple's Clear Liquid Glass is specific to macOS. Windows animation preferences pause idle motion. Windows 10 and 11 use the same features and configuration schema. Windows ARM64 is outside the initial x64 validation scope.

## Development

```powershell
cd windows
npm ci
npm test
npm run typecheck
npm run build
npm start
```

`npm run smoke` launches the real Electron app with a temporary store. CI exercises source installation on Windows runners and saves screenshots/logs. See `docs/verification/` at the repository root for executed checks and remaining hardware validation. No installer is built or published.

`src/core/` contains reusable behavior and curved geometry, `src/main/` owns native windows and IPC, `src/native/` wraps Win32 input and shell icons, and `src/renderer/` contains widget/settings UI. The sandboxed preload exposes a narrow typed API; renderers cannot execute shell commands or read arbitrary files.
