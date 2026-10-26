# T-Cube

[English](README.md) | **简体中文**

把常用 App 和文件夹放进一颗悬浮在桌面的玻璃立方体。滚动切换六个面，悬停显示图标，点击打开入口。

**macOS 15+ · Swift 6 · AppKit / SwiftUI / RealityKit · 无第三方依赖**

## 效果预览

<p align="center">
  <img src="docs/images/cube-hover.png" width="760" alt="深石墨色背景下的 T-Cube，三个透明玻璃面展示应用图标">
</p>

<table>
  <tr>
    <td align="center"><strong>安静的静置状态</strong><br><img src="docs/images/cube-idle.png" width="370" alt="静置时隐藏图标，保留细玻璃棱边与轻微内部光丝"></td>
    <td align="center"><strong>极光流体</strong><br><img src="docs/images/cube-aurora.png" width="370" alt="极光流体材质，背景、视角和比例与其他预览一致"></td>
  </tr>
</table>

<details>
<summary>查看悬停与流光动效</summary>
<p align="center"><img src="docs/images/cube-motion.gif" width="760" alt="悬停时显示应用图标，玻璃高光持续流动"></p>
</details>

以上为应用自身的原生渲染，使用系统示例图标并放大展示细节。所有预览统一使用深石墨色背景、相机角度和画面尺寸。

## 主要功能

- **六面入口，每面四个快捷方式**：支持本地 App 和文件夹，空位留白。
- **自由旋转与移动**：双向滚动旋转，滚哪停哪；左右键均可拖动位置。
- **悬停放大**：移入自动放大、移出恢复，倍率可调为 1.1×～4×。
- **两种打开方式**：先展开面板选择图标，或直接点击立方体面上的图标打开。
- **个性化玻璃**：九种预设、自定义双色渐变、玻璃材质，以及 10 秒／20 秒主题轮换。
- **状态栏常驻**：设置、显示、隐藏与退出集中管理，不占 Dock；光效支持系统「减少动态效果」。

## 安装与运行

当前版本为 **0.9.0**，使用 **master** 分支。

运行需要 macOS 15+；源码构建需要完整 Xcode、Swift 6 和 **macOS 27 SDK**。当前本地打包产物面向 Apple Silicon，使用 ad-hoc 签名，尚未公证。

```bash
git clone --branch master https://github.com/gd0306/t-cube.git
cd t-cube
bash scripts/build-app.sh
open build/T-Cube.app
```

需要拖拽安装时，运行 `bash scripts/build-dmg.sh`，打开 `build/T-Cube-0.9.0.dmg`，将应用拖入 **Applications**。更新前先退出旧版，保留原配置。构建产物不随源码提交；系统安全授权由用户确认。

### 让 agent 帮忙安装

复制这段提示词给支持终端操作的 agent：

```text
帮我安装 T-Cube：https://github.com/gd0306/t-cube，使用 master 分支。按 README 构建、安装到 /Applications 并打开。先退出旧版并保留配置；缺少 Xcode/SDK 或需要系统安全授权时告诉我。
```

## 配置与操作

首次运行会打开设置，也可右键单击立方体或从状态栏进入。

1. 在「立方体入口」为六个面添加应用或文件夹，也可从 Finder 拖入。
2. 在「外观」选择主题、材质、轮换与悬停大小，点击「应用设置」保存。
3. 想直接打开图标：在「打开方式」关闭「点击面展开放大」。空白和空槽不触发操作。

| 操作 | 效果 |
| --- | --- |
| 触控板双指左右／上下滑动 | 沿对应方向旋转，停止后保持姿态 |
| 鼠标滚轮／Shift＋滚轮 | 上下／左右旋转 |
| 左键或右键拖动 | 移动悬浮位置并保存 |
| 鼠标在立方体内时按住 Ctrl | 临时恢复静置大小 |
| Ctrl＋左键拖动 | 按原大小移动，中途松开 Ctrl 也不跳变 |
| 展开后点击外部区域／Esc | 收起图标面板 |
| 右键单击 | 打开设置 |

展开面板只显示四个图标；macOS 26+ 使用 Clear Liquid Glass，旧系统使用毛玻璃。设置页底部或状态栏菜单均可彻底退出应用。

## 本地数据

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
env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter GlassRenderPreviewTests
```

输出位于 `.build/glass-previews/`，使用独立临时配置，不改动用户数据。多背景验证图与 README 展示图分别生成。

`Sources/CubeCore` 管理配置、几何与命中逻辑；`Sources/TCube` 管理窗口、渲染与原生界面。贡献约定见 [AGENTS.md](AGENTS.md)，检查结果与限制见 [验证记录](docs/verification/)。
