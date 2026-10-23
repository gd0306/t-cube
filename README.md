# T-Cube

一个悬浮在桌面上的原生 macOS 立方体启动器。旋转六个面，在六组应用和文件夹入口之间切换。

默认窗口为 164×164 点，每面保留四个入口，始终置于普通应用窗口上方。空闲时隐藏所有入口和面填充，只保留透明轮廓与渐变光晕；鼠标移入后显示各面的图标。项目使用 Swift、AppKit、SwiftUI 和 RealityKit，无第三方依赖，最低支持 macOS 15。

## 安装与配置

打开 `build/T-Cube-0.4.0.dmg`，将 **T-Cube.app** 拖入旁边的 **Applications** 文件夹，再从“应用程序”打开 T-Cube。

应用常驻 macOS 状态栏，不显示 Dock 图标。点击状态栏的立方体图标，选择“设置…”：

- “立方体入口”：切换六个面，配置各自的应用或文件夹、修改分组名称、排序和移除入口。
- “外观”：选择极光、海洋、晚霞配色，或自定义渐变的主色与辅助色；调整光晕强度和尺寸后点击“应用外观”。

首次运行会打开设置。当前安装包为 Apple Silicon 本地开发签名构建，尚未进行 Developer ID 公证。

## 构建与运行

需要安装 Xcode，并使 `xcode-select` 指向完整 Xcode 开发目录。

```bash
bash scripts/build-app.sh
open build/T-Cube.app
```

构建产物位于 `build/T-Cube.app`，也可在 Finder 双击打开。应用常驻菜单栏，不显示 Dock 图标。构建脚本只进行本地 ad-hoc 签名；发布所需的开发者签名和公证不在本次范围内。

构建 DMG 安装包：

```bash
bash scripts/build-dmg.sh
```

调试构建：

```bash
bash scripts/build-app.sh --debug
```

在 Xcode 中打开 `Package.swift` 可以浏览和调试源码。

## 操作

| 操作 | 效果 |
|---|---|
| 双指左右滑动 | 立方体沿水平方向跟随手势旋转 |
| 双指上下滑动 | 立方体沿垂直方向跟随手势旋转，停下后自动转正 |
| 普通鼠标滚轮 | 上下旋转；按住 Shift 时左右旋转 |
| 按住右键拖动立方体 | 自由移动悬浮位置，松开后保存 |
| 单击正面图标 | 启动应用或在 Finder 打开文件夹 |
| 单击空位置 | 选择应用或文件夹添加 |
| 从 Finder 拖入应用或文件夹 | 加入当前正面的空位 |
| 右键单击后松开 | 打开分组编辑窗口；拖动不会误触编辑 |
| 鼠标移入／移出 | 显示／隐藏各面入口 |
| 状态栏立方体图标 | 设置、显示／隐藏、调整大小、退出 |

编辑窗口可以切换六个分组、修改名称、调整入口顺序、移除入口。同一个分组不允许重复入口，已满的分组不会覆盖现有内容。移除入口只会删除快捷方式，不会删除本地应用或文件夹。

## 本地数据

配置自动保存在：

```text
~/Library/Application Support/T-Cube/configuration.json
```

配置包含分组、入口、窗口尺寸与位置。入口保存本地 URL 和 bookmark，以便重新解析目标。文件夹或应用不存在、失去访问权限或启动失败时会提示错误；在编辑窗口的入口菜单中选择“重新选择目标…”可以更换目标，也可以移除后重新添加。

配置损坏时会保留原文件，并阻止默认配置覆盖原数据。启动时可以选择“备份并新建”，程序将原文件改名为 `configuration-preserved-<UUID>.json` 后创建空配置；也可以选择退出，手动备份和修复原文件。

## 开发与验证

```bash
swift test --scratch-path .build/tests
swift build --scratch-path .build/app
git diff --check
```

`Sources/CubeCore` 管理配置、分组编辑、旋转几何与拖动判定；`Sources/TCube` 管理系统窗口、3D 场景、本地文件与原生编辑界面。

整体设计见 [首版设计](docs/superpowers/specs/2026-10-23-macos-cube-design.md)，任务安排见 [实施计划](docs/superpowers/plans/2026-10-23-macos-cube.md)。

## 后续方向

透明轮廓、光晕和配色通过 `CubeTheme`、`CubeAura` 与持久化的 `CubeAppearance` 管理。后续可继续加入星空、花海等主题；多立方体、全局快捷键和开机启动也留待后续迭代。
