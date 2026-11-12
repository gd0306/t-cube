# T-Cube for Windows

Source version **0.22.9** targets Windows 10 22H2 / Windows 11, x64. This client uses Electron and Three.js; the repository's macOS client remains native Swift. The **0.22.9** installer below includes redesigned glass-style settings, immediate appearance saving, scoped default restoration and a blue/cyan tray icon, alongside existing clipboard and startup features.

## Installer

Download [T-Cube 0.22.9 for Windows x64](https://github.com/gd0306/t-cube/releases/download/v0.22.9/T-Cube-0.22.9-windows-x64-setup.exe) from [Releases](https://github.com/gd0306/t-cube/releases/tag/v0.22.9). It installs per user, includes Electron/native dependencies, creates shortcuts and an uninstall entry, and requires neither Node.js nor administrator privileges. Quit the previous version before updating. Existing `%APPDATA%\\T-Cube` configuration is retained. The installer is not Authenticode signed.

Under **外观与主题 → 材质**, choose **玻璃** or **史莱姆**. All nine themes, custom colors and automatic cycling work with either material. Glass is the default. Slime follows the mouse with lag and elastic rebound while launcher icons remain rigid; Windows animation preferences disable its motion.

Under **交互与位置**, **靠边自动收起** and **全屏应用时隐藏** are independent and default off. A cube within 32 logical pixels of an outer left/right usable screen edge becomes a slim handle after the pointer leaves for about 0.8 seconds; hovering the handle restores it. Shared monitor seams and interior positions stay unchanged. Dragging, face expansion and open settings protect it from collapse. Fullscreen hiding uses public public window metadata on the cube's display, requires no screen capture permission, and preserves manual tray hiding. Collapsed geometry is never saved. The collapsed handle follows the OS light/dark appearance: a white frosted capsule by day and dark sky-black glass by night, with a subtle 8.4-second internal shimmer while visible. Windows uses a frosted style rather than desktop backdrop blur. Reduced motion, reduced transparency and forced colors use a static fallback; hidden handles cancel their CSS animation and compositor hints. Windows may impose a wider transparent native window at some display scales; its drawing and input region are clipped to the same 10 × 56 logical-pixel handle, with the unused container passing input through.


## Display input switching

Version `0.22.0` adds **显示器输入源…** to the tray context menu; left-click still shows or hides the cube. The panel switches a DDC/CI-capable monitor between **Type-C** on the left and **HDMI** on the right through a two-segment switch. Click a port or use the keyboard arrow keys; controls lock while busy, retain the last confirmed selection during a request, and clear selection when readback is unknown. Opening or refreshing reads hardware; there is no background display polling, startup source restoration, volume control or network relay.

The input panel automatically enumerates connected displays without model-specific presets; previously saved mappings remain unchanged. Monitors that relied on the automatic preset without a saved mapping need calibration once. Select the intended monitor by name and its `DISPLAY` number. Targets with ambiguous identity, missing physical DDC transport, or unavailable input readback remain visible with switching disabled. Detection refreshes on display changes and panel reopen; a disconnected selection does not silently move to another monitor.

Open **如何获取输入代码？** in the input panel for the full procedure. Enable DDC/CI in the monitor’s physical menu if offered, connect and wake both hosts, then physically select Type-C. On the host now shown, select that monitor in T-Cube and click **刷新**; expand **设置输入源代码** and record **当前代码**. Physically select the intended HDMI port and repeat on its active host. Save the two distinct decimal values in `0–65535` on each host separately. Saving only stores the mapping; it sends no switch command. The app reads current input via VCP `0x60` (a feature number, not a port value) and does not discover all supported input values. A non-continuous VCP's reported maximum is not a valid code range.

To verify, ensure the physical menu is available for recovery, activate one mapped port, and click the other once. Check the picture and refresh on the now-active host. Lost readback means unconfirmed, even if the monitor switched. If codes remain unavailable, check DDC/CI and graphics drivers, try a direct connection instead of a dock/KVM/adapter, and refresh; these are diagnostic steps, not compatibility guarantees. Use the physical input menu when VCP `0x60` is unavailable. [Source verification and UI captures](../docs/verification/2026-11-07-display-input-discovery.md).

A monitor may stop responding on an inactive connection after switching. An accepted command followed by lost readback is shown as unconfirmed, with no automatic retry or reversal. Switch back from T-Cube on the currently active computer, or use the monitor's physical input menu. Compatibility depends on the monitor firmware, graphics driver and cable/adapter path; the software cannot guarantee control over inactive inputs.

Mappings live separately at `%APPDATA%\T-Cube\display-inputs.json` and are not included in the existing launcher configuration export. Invalid existing files remain intact and block replacement; back up and repair the file, then fully quit and restart T-Cube before refreshing the panel or saving calibration again. Native display operations execute away from Electron's main process and renderer. Only the input panel's own main frame can invoke its narrow IPC; other windows receive no display-control privilege.

## Office tools and idle performance

Website entries show their saved title below the icon on the cube and expanded face. Long titles use single-line ellipsis; hover shows the full name. Clicking the title uses the existing launch/expand preference. Rendering stays local with no favicon requests.

Clipboard history is available from the tray or the **剪贴板历史** tab. Hold **Ctrl alone for 1 second** to open a compact glass history list beside the pointer; release Ctrl to keep it open, then click a text or image entry once to copy and dismiss it. **编辑文字** opens a session draft with explicit **保存** / **取消**; deletion is also available for both text and images. Editing preserves the entry ID, timestamp and order, does not write the system clipboard, and rejects changes exceeding 64 KiB UTF-8 per entry or the 2 MiB text budget without removing other entries. The full manager retains search, merge, paste and saving common content. Every launch starts recording automatically; pause it from the full history manager for the current session. The quick list offers **启用记录** while paused. Existing history remains available while paused; enabling/resuming starts with the next copy. History stays in memory, disappears on exit and is excluded from backup/export. File drops and supported privacy exclusion markers are skipped, but unmarked sensitive content may still be recorded. No cloud sync.

Start the hold outside the cube. When the pointer is on the cube or a cube drag is active, Ctrl belongs to the cube and never opens history during that press. Entering the cube while holding Ctrl also cancels history for that whole press, even after leaving. The Ctrl hold is also cancelled for that press by any other key, mouse button or wheel input; release Ctrl before trying again. Each press opens the list at most once. Ctrl's resting-size behavior, Ctrl-drag and existing Ctrl shortcuts remain available. Raw Input observes interruption, Ctrl transitions and pointer context for cube priority, without a global keyboard hook, key logging or extra permission prompt; pointer movement outside the cube does not cancel. Startup with Ctrl already down and sleep/resume require a fresh release. If native input registration is unavailable, open the full history from the tray. The quick window follows the system light/dark theme, uses native acrylic on Windows 11 22H2+ through Electron’s background material (without a separate transparent-window mode), and uses a solid tinted fallback on Windows 10/older Windows 11 (desktop blur is unavailable there). Drag its title to move the panel; every fresh invocation returns to the history list without restoring unsaved previews. Reduced-transparency and high-contrast preferences use a solid surface. Escape, the close button or clicking another window dismisses the quick list; its unsaved draft stays available until cancelled or the app exits.

Open **常用内容** from the tray or `Ctrl+Shift+Space`. Store reusable text and structured fields, group/favorite/search them, and copy or paste whole entries or individual fields. Clipboard capture and dropped text open a draft for review. Paste restores the original input window only while its process identity/focus still match; otherwise text remains copied for manual paste.

**Per-entry text tools:** per-record text tools now open a preview before any write. Copy directly, or edit the preview before copying or explicitly saving to that session entry. Includes whitespace cleanup, case conversion, lossless JSON formatting/minification and URL component encoding/decoding. Available in the `0.22.9` installer. See [preview and verification](../docs/verification/2026-11-13-clipboard-text-tools.md).

**剪贴板历史** is session-only and starts recording on every launch; pausing lasts for the current session. Enabling or resuming starts with the next copy. Text and image tabs are separate: text retains up to 100 entries (64 KiB each, 2 MiB total), while images retain up to 10 (8 MiB normalized PNG each, 32 MiB total, 16 megapixels). PNG/JPEG clipboard representations normalize to PNG in main; file drops and supported private/history exclusion markers are skipped. Only compressed bytes and small thumbnails are retained; selected previews are bounded. A single sandboxed canvas processor performs codecs away from the Electron main thread, keeps at most one active job plus the newest pending recording and preview, and exits after 10 seconds idle or immediately on pause/clear/quit. Native DIB headers are checked before Electron materializes image bytes (16 megapixels, 65 MiB raw bound); native conversion and one active decoder can still hold a temporary uncompressed bitmap. Clear and quit release all history; it is excluded from configuration and backups.

Select text checkboxes to preview a merge in current list order, optionally trim each line and collapse repeated blank lines. Copy, paste or explicitly save the preview as ordinary content; original entries are unchanged. Merges are limited to 64 KiB UTF-8. Images support preview, copy, focus-checked paste and delete, with no OCR or automatic content conversion. Paste restores only the captured input target; unsupported or unavailable targets leave the copy available for manual paste.

**Settings** use a persistent sidebar and follow system light/dark appearance. Changes save immediately; **恢复默认外观** resets only material, colors, optical effects and theme cycling, preserving launchers and interaction settings. Settings use native Acrylic on Windows 11 22H2+; older systems, reduced-transparency and high-contrast modes use a solid fallback. The notification-area icon is a blue/cyan three-face cube with a contrasting outline and multi-resolution ICO artwork.

**配置与备份** offers validated import/export previews, automatic pre-import backups, manual restore and broken-launcher relinking. Hover delay is configurable and display positions are remembered independently across connection changes. **启动与更新** shows actual login-item state. An installed copy enables launch at login on its first run; an explicit opt-out is saved and later launches never force it back on. Windows startup restrictions are respected and registration failures are shown here. Both the NSIS installer and source installer apply this default through the app on first launch; unsigned installers offer manual checks and opt-in six-hour release reminders, defaulting to off. These anonymously read GitHub metadata, remember notified versions and open the release page for manual installation. No signing credentials or token are required. Authenticated in-app installation requires the publisher's signing setup described in [Windows signing and updates](../docs/windows-signing-updates.md).

**性能** offers opt-in idle power saving (off by default on Windows): stationary frames stop rendering until interaction. Disable it to retain 15Hz idle animation; hover/slime interaction runs at 30Hz. Hidden surfaces stop rendering, and idle/hidden native input polling slows down. Glass has deeper tint and contour for visibility on white backgrounds. Theme colors/optical layers blend over 0.4 seconds. Face expansion defaults on; explicit existing preferences are preserved. The cube has no content-library overlay button.

## Preview

Resting size on dark and light backgrounds:

<p><img src="../docs/images/windows-idle-dark.png" width="164" alt="Visible glass contour at resting size on a dark background"><img src="../docs/images/windows-idle-light.png" width="164" alt="Visible glass contour at resting size on a light background"></p>

<p><img src="../docs/images/windows-hover.png" width="400" alt="Curved icons on a very transparent glass body"><img src="../docs/images/windows-expanded.png" width="180" alt="Four-icon translucent expansion panel"></p>

<img src="../docs/images/windows-settings.png" width="760" alt="Windows client settings with six groups, four slots and quit control">

Captured from the installed source client on Windows CI. The transparent widget and expansion are composited over a graphite background for readability. Settings use their actual light background.

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

Hover to show icons and enlarge; leave to shrink and resume optional idle rotation. Wheel/trackpad scroll turns both axes without snapping (Shift + wheel turns horizontally). Left-button dragging moves and saves the widget position. Hold the right button and drag to rotate the cube along both axes; releasing keeps its angle. Ctrl temporarily restores its resting size; hold Ctrl alone for 1 second outside the cube for the clipboard quick list. Starting on or entering the cube reserves that entire press for cube controls until release. Ctrl + left drag moves it at that size, including when Ctrl is released mid-drag. Right-click without dragging opens settings.

Each of six groups holds four applications or folders. Click **添加应用** to browse installed Windows applications by name and icon, search, then select one to add it to that slot. The list reads Windows application registration, Start Menu shortcuts and App Paths; desktop and registered system/Store apps are supported. **刷新列表** reloads registrations after installations or removals. Use **浏览文件…** for an unregistered portable `.exe` or a shortcut. Folder selection and Explorer drag-and-drop remain available. Choose face expansion (four icons, outside click/Escape to dismiss) or direct icon launching. Nine themes, custom two-color glass, 10/20-second cycling, hover multiplier, idle rotation, resting size and five screen placements are configurable. Tray controls include show/hide, settings, placement and quit.

System-app launch links are kept in `%APPDATA%\T-Cube\applications` alongside configuration. Back up the whole T-Cube data folder when migrating; updates preserve it. Original desktop shortcuts keep their arguments and working directory.

Windows uses its own translucent glass rendering; Apple's Clear Liquid Glass is specific to macOS. Windows animation preferences pause idle motion. Windows 10 and 11 use the same features and configuration schema. Windows ARM64 is outside the initial x64 validation scope.

## Installed applications

<img src="../docs/images/windows-app-picker.png" width="760" alt="Searchable Windows installed application picker with names and icons">

The list covers applications registered for the current Windows user, shared Start Menu entries and registered executable paths. Unregistered portable programs can be added through **浏览文件…**. Equivalent launch aliases are deduplicated; distinct arguments or working directories are preserved.

## Development

```powershell
cd windows
npm ci
npm test
npm run typecheck
npm run build
npm start
```

`npm run smoke` launches the real Electron app with a temporary store. CI exercises source installation on Windows runners and saves screenshots/logs. `npm run package:win` builds the x64 NSIS installer after `npm run build`. The **Windows installer** workflow installs that generated package and runs the same smoke checks against its actual installed executable before retaining the installer/checksum artifacts. See the [verification record](../docs/verification/2026-10-27-windows-support.md) for the original port checks and remaining hardware validation.

`npx tsx scripts/clipboard-quick-ui.ts` exercises the production quick-list renderer against an owned in-memory recorder, including explicit enable, edit/save/cancel, rejected edits, copying, image deletion and failure recovery. `npx tsx scripts/desktop-clipboard-ui.ts` checks the full history manager. `npx tsx scripts/clipboard-quick-electron.ts` checks the real Electron window/IPC lifecycle with an isolated configuration and does not touch the system clipboard. The Windows `npm run smoke` also executes `scripts/clipboard-quick-smoke.ts` inside its owned receiver and clipboard snapshot: real `SendInput` checks short Ctrl, the one-second outside hold, hover-size arbitration and whole-press cancellation after entering/leaving the cube, release retention, quick-UI editing, copy/dismiss and self-recording suppression. This is automated desktop input, not a manual hardware check; the native helper is skipped on macOS. The standalone renderer/host scripts can run on macOS as previews; Windows Raw Input delivery, native acrylic, Windows accessibility settings and physical Ctrl/drag/shortcut behavior still require a Windows desktop session. The supported material/version behavior follows [Electron’s window API](https://www.electronjs.org/docs/latest/api/browser-window/#winsetbackgroundmaterialmaterial-windows); native material appearance remains subject to Windows desktop verification. Raw Input uses [Microsoft's background-input registration](https://learn.microsoft.com/en-us/windows/win32/inputdev/using-raw-input), without disabling the legacy input messages.

`src/core/` contains reusable behavior and curved geometry, `src/main/` owns native windows and IPC, `src/native/` wraps Win32 input and shell icons, and `src/renderer/` contains widget/settings UI. The sandboxed preload exposes a narrow typed API; renderers cannot execute shell commands or read arbitrary files.

Shortcut targets also support individual files, HTTP/HTTPS websites and the built-in Windows settings-page catalog. Websites open in the default browser; files use their associated application.
