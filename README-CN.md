# T-Cube

[English](README.md) | **简体中文**

把常用 App 和文件夹放进一个悬浮在桌面的通透玻璃体。滚动切换六组入口，悬停显示图标，点击打开。

**macOS 15+（原生 Swift） · Windows 10/11（Electron + Three.js）**

## 效果预览

玻璃外壳、反光与光晕更轻，让桌面背景清晰透出。悬停后，图标沿曲面显示。

<p align="center">
  <img src="docs/images/cube-hover.png" width="760" alt="深石墨色背景下的 T-Cube，圆润透明玻璃体周围展示应用图标">
</p>

<table>
  <tr>
    <td align="center"><strong>安静的静置状态</strong><br><img src="docs/images/cube-idle.png" width="370" alt="静置时隐藏图标，保留连续弧面轮廓与轻微内部光丝"></td>
    <td align="center"><strong>极光流体</strong><br><img src="docs/images/cube-aurora.png" width="370" alt="极光流体材质，背景、视角和比例与其他预览一致"></td>
  </tr>
</table>

<details>
<summary>查看自动旋转与悬停暂停</summary>
<p align="center"><img src="docs/images/cube-motion.gif" width="760" alt="静置时自动旋转，悬停暂停并显示图标，移出后继续旋转"></p>
</details>

以上为应用自身的原生渲染，使用系统示例图标并放大展示细节。所有预览统一使用深石墨色背景、相机角度和画面尺寸。

## 主要功能

- **轻薄通透的玻璃外观**：圆角、平缓弧面和柔和反光，图标清晰地贴合表面。
- **六组入口，每组四个快捷方式**：支持本地 App 和文件夹，空位留白，点击区域与曲面图标一致。
- **自由旋转与移动**：双向滚动旋转，悬停时滚哪停哪；左键拖动位置，右键拖动旋转。
- **快捷放置**：从状态栏菜单或「外观 → 快捷位置」一键移到所在屏幕四角或正中央，立即保存，避开菜单栏、Dock 或任务栏。
- **空闲自动旋转**：缓慢、平滑地变换方向；移入立即停转，移出继续。在「外观 → 动态旋转」可关闭；系统开启「减少动态效果」时自动暂停。
- **悬停放大**：移入自动放大、移出恢复，倍率可调为 1.1×～4×。
- **两种打开方式**：先展开面板选择图标，或直接点击立方体面上的图标打开。
- **个性化玻璃**：主题预设、自定义双色渐变、玻璃材质，以及 10 秒／20 秒主题轮换。
- **macOS 玻璃／史莱姆材质**：所有主题都能搭配任一材质。史莱姆随鼠标牵引并弹性回弹，图标保持稳定；默认仍为玻璃。
- **状态栏常驻**：设置、显示、隐藏与退出集中管理，不占 Dock；光效支持系统「减少动态效果」。

## Windows 源码安装

Windows 10 22H2 / Windows 11（x64）使用独立客户端，支持同样的六组入口、曲面图标、主题轮换、悬停放大、拖动、旋转与托盘设置。添加应用时可直接搜索、选择已安装应用，便携程序可浏览文件添加。无需下载安装包，具体步骤见 [Windows 指南](windows/README.md)。上面的效果图来自 macOS 原生版。

给本地 AI agent 的简短提示词：

```text
在 Windows 上安装 https://github.com/gd0306/t-cube 的 master 分支。按 windows/README.md 准备 Node.js 22 LTS，运行 windows/scripts/install.ps1。先退出旧版、保留配置，创建快捷方式并启动；报告自测结果。
```

## macOS 安装与运行

当前版本为 **0.12.4**，使用 **master** 分支。

运行需要 macOS 15+；源码构建需要完整 Xcode、Swift 6 和 **macOS 27 SDK**。当前本地打包产物面向 Apple Silicon，使用 ad-hoc 签名，尚未公证。

```bash
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
bash scripts/build-app.sh
open build/T-Cube.app
```

需要拖拽安装时，运行 `bash scripts/build-dmg.sh`，打开 `build/T-Cube-0.12.4.dmg`，将应用拖入 **Applications**。更新前先退出旧版，保留原配置。构建产物不随源码提交；系统安全授权由用户确认。

### 让 agent 帮忙安装

复制这段提示词给支持终端操作的 agent：

```text
帮我安装 T-Cube：https://github.com/gd0306/t-cube，使用 master 分支。按 README 构建、安装到 /Applications 并打开。先退出旧版并保留配置；缺少 Xcode/SDK 或需要系统安全授权时告诉我。
```

## macOS 配置与操作

首次运行会打开设置，也可右键单击立方体或从状态栏进入。

1. 在「立方体入口」为六个面添加应用或文件夹，也可从 Finder 拖入。
2. 在「外观」选择主题、材质、轮换与悬停大小，点击「应用设置」保存。
3. 想直接打开图标：在「打开方式」关闭「点击面展开放大」，再点击「应用设置」保存。空白和空槽不触发操作。
4. 从状态栏菜单或「外观 → 快捷位置」选择四角或正中央，立即生效并保存。

体验果冻效果：在「外观 → 材质」选择「史莱姆」，再点击「应用设置」。主题、自定义配色与自动轮换同时适用于两种材质；切换主题不会改变所选材质。选择「玻璃」可恢复原来的刚性外壳。

| 操作 | 效果 |
| --- | --- |
| 鼠标移入／移出 | 显示／隐藏图标；自动旋转开启时暂停／继续旋转 |
| 触控板双指左右／上下滑动 | 沿对应方向旋转，停止后保持姿态 |
| 鼠标滚轮／Shift＋滚轮 | 上下／左右旋转 |
| 左键拖动 | 移动悬浮位置并保存 |
| 右键拖动 | 自由旋转立方体，松手保留当前角度 |
| 鼠标在立方体内时按住 Ctrl | 临时恢复静置大小 |
| Ctrl＋左键拖动 | 按原大小移动，中途松开 Ctrl 也不跳变 |
| 展开后点击外部区域／Esc | 收起图标面板 |
| 右键单击 | 打开设置 |

展开面板只显示四个图标；macOS 26+ 使用 Clear Liquid Glass，旧系统使用毛玻璃。设置页底部或状态栏菜单均可彻底退出应用。

## macOS 本地数据

配置保存在 `~/Library/Application Support/T-Cube/configuration.json`，包含入口、外观、交互偏好和窗口位置。移除快捷方式不会删除目标应用或文件夹；配置损坏时会保留原文件，避免默认配置覆盖数据。

## 开发与验证

```bash
swift test --scratch-path .build/tests
bash scripts/build-app.sh --debug
bash scripts/verify-dmg.sh  # 构建 DMG 后执行
git diff --check
```

重新生成原生效果图，包括统一风格的 `readme-*` 图集：

```bash
env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter 'GlassRenderPreviewTests|IconEdgeRenderingTests'
```

输出位于 `.build/glass-previews/`，使用独立临时配置，不改动用户数据。多背景透明度验证、图标边缘检查与 README 展示图分别生成。

`Sources/CubeCore` 管理配置、几何与命中逻辑；`Sources/TCube` 管理窗口、渲染与原生界面。贡献约定见 [AGENTS.md](AGENTS.md)，检查结果与限制见 [验证记录](docs/verification/)。
