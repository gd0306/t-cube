# T-Cube

**English** | [简体中文](README-CN.md)

A floating glass cube for your favorite Mac apps and folders. Scroll to turn it, hover to reveal your icons, and click to launch.

**macOS 15+ · Swift 6 · AppKit / SwiftUI / RealityKit · No third-party dependencies**

## Preview

<p align="center">
  <img src="docs/images/cube-hover.png" width="760" alt="T-Cube showing app icons on three transparent glass faces against a graphite background">
</p>

<table>
  <tr>
    <td align="center"><strong>Quiet at rest</strong><br><img src="docs/images/cube-idle.png" width="370" alt="Idle cube with hidden icons, thin glass edges, and a subtle inner glow"></td>
    <td align="center"><strong>Aurora Flow</strong><br><img src="docs/images/cube-aurora.png" width="370" alt="Aurora Flow glass material with the same background, camera, and scale"></td>
  </tr>
</table>

<details>
<summary>Watch the hover and light animation</summary>
<p align="center"><img src="docs/images/cube-motion.gif" width="760" alt="Icons appear on hover while the glass highlights keep moving"></p>
</details>

Native app renders with sample system icons, enlarged for detail. All previews share the same graphite background, camera, and viewport.

## Features

- **Six faces, four shortcuts each.** Add local apps or folders; empty slots stay blank.
- **Free rotation and positioning.** Scroll in either direction; the cube stays where you stop while hovered. Drag with either mouse button to move it.
- **Wandering idle rotation.** Slowly drift through changing directions; hover to stop instantly and leave to resume. Disable it under **Appearance → Dynamic rotation (动态旋转)**. Reduce Motion pauses it automatically.
- **Hover to enlarge.** Return to the resting size when the pointer leaves; zoom is adjustable from 1.1× to 4×.
- **Two launch modes.** Expand a face before choosing an icon, or launch directly from icons on the cube.
- **Personalized glass.** Nine presets, custom two-color gradients, glass materials, and automatic theme cycling every 10 or 20 seconds.
- **Menu-bar access.** Configure, show, hide, or quit without a Dock icon. Motion respects macOS Reduce Motion.

## Install and run

Current version: **0.10.0**. Use the **master** branch.

Running requires macOS 15+. Building requires full Xcode with Swift 6 and the **macOS 27 SDK**. Current local packages target Apple Silicon and use ad-hoc signing; they are not notarized.

```bash
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
bash scripts/build-app.sh
open build/T-Cube.app
```

For a drag-to-install disk image, run `bash scripts/build-dmg.sh`, open `build/T-Cube-0.10.0.dmg`, and drag the app into **Applications**. Quit an existing version before updating and keep its configuration. Build artifacts are not included in the repository; macOS security approvals remain with the user.

### Let an agent install it

Copy this prompt to an agent with terminal access:

```text
Install T-Cube from https://github.com/gd0306/t-cube (master). Follow the README to build, install to /Applications, and launch it. Quit the old version first and preserve its configuration. Tell me if Xcode/SDK requirements or macOS security approvals need attention.
```

## Configure and use

Settings open on first launch. Reopen them by right-clicking the cube or using its menu-bar icon.

1. In **Cube entries (立方体入口)**, assign apps or folders to each face. Finder drag-and-drop is also supported.
2. In **Appearance (外观)**, choose themes, materials, cycling, and hover size. Click **Apply settings (应用设置)** to save.
3. To launch directly, disable **Expand faces on click (点击面展开放大)** under **Launch behavior (打开方式)**. Blank areas and empty slots do nothing.

| Action | Result |
| --- | --- |
| Two-finger horizontal / vertical scroll | Rotate along the corresponding axis; stop without snapping |
| Mouse wheel / Shift + wheel | Rotate vertically / horizontally |
| Left- or right-button drag | Move and save the floating position |
| Hold Ctrl over the cube | Temporarily restore the resting size |
| Ctrl + left-button drag | Move at resting size, even if Ctrl is released mid-drag |
| Click outside an expanded face / Esc | Dismiss the icon panel |
| Right-click | Open settings |

Expanded faces contain only four icons. macOS 26+ uses Clear Liquid Glass; earlier supported systems use frosted glass. Quit from the settings footer or menu-bar menu.

## Local data

Configuration lives at `~/Library/Application Support/T-Cube/configuration.json`. It stores shortcuts, appearance, interaction preferences, and window position. Removing a shortcut does not delete its target. Corrupt configuration is preserved rather than overwritten with defaults.

## Development

```bash
swift test --scratch-path .build/tests
bash scripts/build-app.sh --debug
bash scripts/verify-dmg.sh  # After building the DMG
git diff --check
```

Regenerate the native previews, including the matching `readme-*` gallery:

```bash
env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter GlassRenderPreviewTests
```

Files are written to `.build/glass-previews/` using an isolated temporary configuration. Multi-background QA captures are generated separately from the README gallery.

`Sources/CubeCore` owns configuration, geometry, and hit testing; `Sources/TCube` owns windows, rendering, and native UI. See [AGENTS.md](AGENTS.md) for contribution guidelines and [verification records](docs/verification/) for checks and limitations.
