# T-Cube

**English** | [简体中文](README-CN.md)

A transparent glass launcher that floats on your desktop. Keep favorite apps and folders in one softly rounded shape. Scroll to turn it, hover to reveal your icons, and click to launch.

**macOS 15+ (native Swift) · Windows 10/11 (Electron + Three.js)**

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
- **Six groups, four shortcuts each.** Add local apps or folders; empty slots stay blank. Click areas follow the curved icons.
- **Free rotation and positioning.** Scroll in either direction; the cube stays where you stop while hovered. Drag with either mouse button to move it.
- **Quick placement.** Put the cube in any corner or the center of its screen from the menu bar or Appearance settings. Positions save immediately, with room for system bars.
- **Wandering idle rotation.** Slowly drift through changing directions; hover to stop instantly and leave to resume. Disable it under **Appearance → Dynamic rotation (动态旋转)**. Reduce Motion pauses it automatically.
- **Hover to enlarge.** Return to the resting size when the pointer leaves; zoom is adjustable from 1.1× to 4×.
- **Two launch modes.** Expand a face before choosing an icon, or launch directly from icons on the cube.
- **Personalized glass.** Nine presets, custom two-color gradients, glass materials, and automatic theme cycling every 10 or 20 seconds.
- **Menu-bar or tray access.** Configure, show, hide, or quit from system controls. Motion respects system animation preferences.

## Windows source installation

Windows 10 22H2 / Windows 11 (x64) have a separate client with the same six shortcut groups, curved icons, theme cycling, hover zoom, dragging, rotation and tray controls. Choose installed applications from a searchable name-and-icon list; portable apps can be added by file. No installer download is needed; see the [Windows guide](windows/README.md). The previews above show the native macOS client.

Give a local AI agent this prompt:

```text
Install https://github.com/gd0306/t-cube (master) on Windows. Follow windows/README.md, prepare Node.js 22 LTS, and run windows/scripts/install.ps1. Quit the old app first, preserve settings, create shortcuts, launch, and report test results.
```

## macOS install and run

Current version: **0.12.3**. Use the **master** branch.

Running requires macOS 15+. Building requires full Xcode with Swift 6 and the **macOS 27 SDK**. Current local packages target Apple Silicon and use ad-hoc signing; they are not notarized.

```bash
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
bash scripts/build-app.sh
open build/T-Cube.app
```

For a drag-to-install disk image, run `bash scripts/build-dmg.sh`, open `build/T-Cube-0.12.3.dmg`, and drag the app into **Applications**. Quit an existing version before updating and keep its configuration. Build artifacts are not included in the repository; macOS security approvals remain with the user.

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

| Action | Result |
| --- | --- |
| Hover / leave | Reveal / hide icons; pause / resume idle rotation when enabled |
| Two-finger horizontal / vertical scroll | Rotate along the corresponding axis; stop without snapping |
| Mouse wheel / Shift + wheel | Rotate vertically / horizontally |
| Left- or right-button drag | Move and save the floating position |
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
