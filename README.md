# T-Cube

**English** | [简体中文](README-CN.md)

A transparent glass launcher that floats on your desktop. Keep favorite apps, files and web links in one softly rounded shape. Scroll to turn it, hover to reveal your icons, and click to launch.

**macOS 15+ (native Swift) · Windows 10/11 (Electron + Three.js)**

## Download installers

macOS **0.20.1** · Windows **0.20.1**: [macOS Apple Silicon (.dmg)](https://github.com/gd0306/t-cube/releases/download/v0.20.1/T-Cube-0.20.1-macos-arm64.dmg) · [Windows x64 installer (.exe)](https://github.com/gd0306/t-cube/releases/download/v0.20.1/T-Cube-0.20.1-windows-x64-setup.exe) · [Release notes and SHA-256 checksums](https://github.com/gd0306/t-cube/releases/tag/v0.20.1).

The Windows installer includes its runtime and needs no Node.js installation. Quit an existing T-Cube before updating; shortcut configuration is preserved. These builds are unsigned/ad-hoc signed, not notarized or Developer ID/Authenticode signed.

## Preview

A lighter glass shell lets the desktop show through. Hover to reveal icons that follow its curved surface.

<p align="center">
  <img src="docs/images/cube-hover.png" width="760" alt="T-Cube showing app icons around a softly rounded glass body against a graphite background">
</p>

<table>
  <tr>
    <td align="center"><strong>Quiet at rest</strong><br><img src="docs/images/cube-idle.png" width="370" alt="Idle glass body with hidden icons, a continuous curved silhouette, and a subtle inner glow"></td>
    <td align="center"><strong>Aurora Flow</strong><br><img src="docs/images/cube-aurora.png" width="370" alt="Aurora Flow glass material with the same background, camera, and scale"></td>
  </tr>
</table>

<details>
<summary>Watch idle rotation pause on hover</summary>
<p align="center"><img src="docs/images/cube-motion.gif" width="760" alt="The cube rotates at rest, pauses and reveals icons on hover, then resumes when the pointer leaves"></p>
</details>

Native app renders with sample system icons, enlarged for detail. All previews share the same graphite background, camera, and viewport.

## Features

- **Light, transparent glass.** Soft corners, shallow curved faces, subtle reflections, and crisp icons that wrap around the surface.
- **Six groups, four shortcuts each.** Add apps, folders, files, websites or settings pages; empty slots stay blank. Click areas follow the curved icons.
- **Free rotation and positioning.** Scroll in either direction; the cube stays where you stop while hovered. Left drag moves it; right drag rotates it.
- **Quick placement.** Put the cube in any corner or the center of its screen from the menu bar or Appearance settings. Positions save immediately, with room for system bars.
- **Wandering idle rotation.** Slowly drift through changing directions; hover to stop instantly and leave to resume. Disable it under **Appearance → Dynamic rotation (动态旋转)**. Reduce Motion pauses it automatically.
- **Hover to enlarge.** Return to the resting size when the pointer leaves; zoom is adjustable from 1.1× to 4×.
- **Two launch modes.** Expand a face before choosing an icon, or launch directly from icons on the cube.
- **Personalized glass.** Color presets, custom two-color gradients, glass materials, and automatic theme cycling every 10 or 20 seconds.
- **Glass or Slime material on both platforms.** Use any theme with either material. Slime follows the pointer and springs back while icons stay stable; glass remains the default.
- **Menu-bar or tray access.** Configure, show, hide, or quit from system controls. Motion respects system animation preferences.

## Memory and resource improvements (0.17.1)

Unchanged launcher textures are reused, empty faces allocate no atlas, and theme transitions reuse prepared image resources. Windows app-picker icon retention is bounded. See the [controlled memory workload and verification](docs/verification/2026-10-30-memory-resources.md) for measured results and limits.

## Extended shortcuts

Add apps, folders, individual files, HTTP/HTTPS websites and selected system-settings pages from the shortcut editor. Files use their default application, websites use the default browser, and settings pages are chosen from a built-in list. Existing shortcuts and configuration are retained.

## System appearance edge glass (0.20.1)

The collapsed handle follows OS light/dark appearance: white frosted glass or deep space black, with a quiet internal shimmer. Its 10×56 hit region and reveal behavior stay unchanged; cube themes are unaffected. Shimmer runs only while visible, stops while hidden and becomes static for reduced motion/transparency (and macOS Low Power Mode). macOS uses native background material; Windows provides frosted styling rather than desktop backdrop blur. Small compositor layers animate without waking 3D rendering or adding a JavaScript/Swift frame loop.

## Desktop auto-hide and clipboard tools (0.20.0)

Appearance settings offer independent, default-off edge collapse and fullscreen hiding. Near an outer left/right display edge, leaving the cube for about 0.8 seconds shows a narrow reveal handle. Hovering restores the cube without changing its saved resting position. Active dragging, expanded entries and settings are protected. Fullscreen hiding is display-local; manually hidden cubes stay hidden. Collapsed/hidden cubes pause 3D rendering.

Clipboard history has separate text/image categories, defaults to paused each launch and records only new clipboard changes after explicit enable/resume. History is session-only, cleared on exit, excluded from backups and never uploaded. Text retains100 entries,64 KiB per entry and2 MiB total. Select multiple items, preview newline-joined output, optionally trim each line and collapse repeated blank lines, then copy/paste or explicitly save a snippet. Merged output also caps at64 KiB; original entries stay unchanged.

Image history retains at most10 recent images,8 MiB encoded PNG each,32 MiB total and16 megapixels each, evicting oldest images as needed. It supports thumbnails, bounded selected previews, deduplication, copy and focus-checked paste. macOS PNG/TIFF source input also caps at8 MiB, so larger TIFF screenshots are skipped with a status. Processing is serial; full decoded images are not retained in the list. Limits bound admitted/retained data, not total application RSS or unavoidable transient native clipboard materialization. Privacy/file exclusions remain best-effort. No persistence or cloud sync is included.

## Release reminders (0.19.0)

Settings → 启动与更新 offers manual checks and opt-in automatic release reminders. Automatic checks default to off; enabling them reads the latest stable GitHub release anonymously every six hours and prompts once per newer version, with limits preserved across restarts. Manual checks have a one-minute cooldown. No signing certificate, public key or token is needed; GitHub API connectivity is required. Network errors and rate limits show a retry status. Reminders open the release page for manual download and installation.

## Website titles (0.18.1)

Website entries display the title you supplied beneath the icon on the cube and expanded face. Long names use a single line with an ellipsis; hover for the full title. Title clicks follow the same launch/expand setting as the icon. Names are drawn locally into the existing face artwork, with no favicon requests or configuration migration.

<img src="docs/images/website-titles-expanded.png" width="220" alt="Website titles beneath the icons: short Chinese names, a truncated long title and Emoji">

## Content templates

Enable “作为模板使用” when editing a library item, then add placeholders such as `{{客户姓名}}` in its body or fields. Fill each variable once and preview the result before copying or pasting. Existing items remain ordinary text by default.

## Office and performance features (0.17.1)

Both platforms include a common-content library (menu bar/tray, or `Command+Shift+Space` on macOS / `Ctrl+Shift+Space` on Windows) with groups, favorites, search, full-text/field copy and focus-checked paste after Accessibility authorization. Settings include validated import/export, pre-import backups, manual backup/restore and explicit broken-launcher relinking. Hover delay is configurable; per-display positions survive disconnects. Idle power saving defaults to on for macOS and off for Windows: rotation and flowing light pause until interaction. Disable it in Performance settings for continuous animation. Windows glass has deeper tint and contours for light desktop visibility. Theme changes blend over 0.4 seconds without exposing preparation frames; the cube has no content-library button.

Login at startup uses the system login-item service and changes only when enabled by the user. Sparkle authenticated updates and Developer ID/notarization packaging are integrated; production activation requires the release owner's EdDSA key configuration and signing credentials. Builds without a public key disable in-app download/install and use lightweight release reminders instead. See the [release guide](docs/updates/RELEASE-GUIDE.md). Windows also supports login settings; see [Windows signing and updates](docs/windows-signing-updates.md).

## Windows source installation

Windows 10 22H2 / Windows 11 (x64) have a separate client with the same six shortcut groups, curved icons, shared glass/slime materials and themes, hover zoom, dragging, rotation and tray controls. Choose installed applications from a searchable name-and-icon list; portable apps can be added by file. Use the installer above or follow the source installation in the [Windows guide](windows/README.md). The previews above show the native macOS client.

Give a local AI agent this prompt:

```text
Install https://github.com/gd0306/t-cube (master) on Windows. Follow windows/README.md, prepare Node.js 22 LTS, and run windows/scripts/install.ps1. Quit the old app first, preserve settings, create shortcuts, launch, and report test results.
```

## macOS install and run

Current source version: **0.20.1** on **master**. Published installer versions are listed above.

Running requires macOS 15+. Building requires full Xcode with Swift 6 and the **macOS 27 SDK**. Current local packages target Apple Silicon and use ad-hoc signing; they are not notarized.

```bash
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
bash scripts/build-app.sh
open build/T-Cube.app
```

For a drag-to-install disk image, run `bash scripts/build-dmg.sh`, open `build/T-Cube-0.20.1.dmg`, and drag the app into **Applications**. Quit an existing version before updating and keep its configuration. Build artifacts are distributed through Releases; macOS security approvals remain with the user.

### Let an agent install it

Copy this prompt to an agent with terminal access:

```text
Install T-Cube from https://github.com/gd0306/t-cube (master). Follow the README to build, install to /Applications, and launch it. Quit the old version first and preserve its configuration. Tell me if Xcode/SDK requirements or macOS security approvals need attention.
```

## Configure and use on macOS

Settings open on first launch. Reopen them by right-clicking the cube or using its menu-bar icon.

1. In **Cube entries (立方体入口)**, assign apps or folders to each face. Finder drag-and-drop is also supported.
2. In **Appearance (外观)**, choose themes, materials, cycling, and hover size. Click **Apply settings (应用设置)** to save.
3. To launch directly, disable **Expand faces on click (点击面展开放大)** under **Launch behavior (打开方式)**, then click **Apply settings (应用设置)**. Blank areas and empty slots do nothing.
4. Use **Quick placement (快捷位置)** in the menu bar or Appearance to move to a corner or the screen center. Placement applies and saves immediately.

For the gel effect, choose **Appearance → Material (材质) → Slime (史莱姆)** and click **Apply settings**. Themes, custom colors and automatic theme cycling work with both materials. Changing themes preserves the selected material; choose **Glass (玻璃)** to restore the original rigid shell.

| Action | Result |
| --- | --- |
| Hover / leave | Reveal / hide icons; pause / resume idle rotation when enabled |
| Two-finger horizontal / vertical scroll | Rotate along the corresponding axis; stop without snapping |
| Mouse wheel / Shift + wheel | Rotate vertically / horizontally |
| Left-button drag | Move and save the floating position |
| Right-button drag | Rotate the cube freely; release to keep the current angle |
| Hold Ctrl over the cube | Temporarily restore the resting size |
| Ctrl + left-button drag | Move at resting size, even if Ctrl is released mid-drag |
| Click outside an expanded face / Esc | Dismiss the icon panel |
| Right-click | Open settings |

Expanded faces contain only four icons. macOS 26+ uses Clear Liquid Glass; earlier supported systems use frosted glass. Quit from the settings footer or menu-bar menu.

## macOS local data

Configuration lives at `~/Library/Application Support/T-Cube/configuration.json`. It stores shortcuts, appearance, interaction preferences, and window position. Removing a shortcut does not delete its target. Corrupt configuration is preserved rather than overwritten with defaults.

## macOS development

```bash
swift test --scratch-path .build/tests
bash scripts/build-app.sh --debug
bash scripts/verify-dmg.sh  # After building the DMG
git diff --check
```

Regenerate the native previews, including the matching `readme-*` gallery:

```bash
env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter 'GlassRenderPreviewTests|IconEdgeRenderingTests'
```

Files are written to `.build/glass-previews/` using an isolated temporary configuration. Multi-background transparency checks and icon-edge checks are generated separately from the README gallery.

`Sources/CubeCore` owns configuration, geometry, and hit testing; `Sources/TCube` owns windows, rendering, and native UI. See [AGENTS.md](AGENTS.md) for contribution guidelines and [verification records](docs/verification/) for checks and limitations.
