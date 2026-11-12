# macOS 设置界面

本次按维护者提供的侧栏设置参考图改造 macOS 设置窗口；Windows 实现与发布记录见 [0.22.8 验证记录](../verification/2026-11-12-settings-release.md)。

- 左侧固定分类导航，保留现有五类功能；右侧使用统一页面标题、说明及原生控件。
- 窗口默认 1020 × 728，最小 960 × 628；内容遵守标题栏安全区域。
- 侧栏使用 `NSVisualEffectView.Material.sidebar`，内容使用 `underWindowBackground`，以 `behindWindow` 混合；透明标题栏共享背景。
- 材质跟随系统深浅色及窗口激活状态；减少透明度时提供系统窗口背景色回退。
- 原生分组表单隐藏滚动背景；备份分组与恢复预览使用 SwiftUI 原生 material。
- 导航页保持挂载，保留编辑及展开状态；隐藏页禁用命中、键盘操作和辅助功能访问。
- 外观页的材质、主题、尺寸、轮换及交互修改立即保存，通过现有 `AppModel.change` 更新运行效果。
- “恢复默认外观”仅重置外观页字段，不修改六面入口、窗口位置和独立内容库。
- 开启轮换时至少保留两种主题；关闭时可以预选主题，少于两种时无法启用轮换。
- 导入或恢复配置后同步外观页，防止陈旧控件覆盖已恢复的配置。

首次 macOS 本机预览未更改发布版本；随后与 Windows 设置和托盘图标优化统一发布为 `0.22.8`，根 README 已同步两平台的即时保存行为。

## 初版本机验证记录（正式发布前）

- `bash scripts/build-app.sh --debug` 构建成功；`codesign --verify --deep --strict /Applications/T-Cube.app` 通过。
- 已正常退出旧应用，旧 app 和用户 JSON 备份至 `build/install-backups/glass-settings/20261112-221120/` 后安装新 app。
- 安装包与构建目录可执行文件 SHA-256 一致：`ac739d8821a8d78b1e392f767a490eb19bf39e9527cfa2b49fb7f8d31bd94027`。
- 实际打开检查侧栏、入口、外观、桌面与性能、配置与备份、启动与更新；标题栏已与材质背景统一。
- 手动切换材质至史莱姆，直接读取用户配置确认立即持久化；随后通过界面切回原玻璃材质。六面入口按 face 规范化后与备份一致，外观字段与备份一致；运行期间窗口位置有所更新。
- 为保护实际用户设置，没有点击“恢复默认外观”；其字段范围和持久化行为由独立临时配置的两项回归测试验证。
- `swift test --scratch-path .build/tests --no-parallel`：Swift Testing 的 226 项应用测试及 143 项核心测试通过；XCTest 共 16 项、2 项跳过，`EdgeDockAnimationTests.testCompletedTransitionsDetachTheRendererAndReuseOneOverlay` 有 6 个断言失败，整条命令退出 1。
- 随后单独执行 `swift test --scratch-path .build/tests --no-parallel --filter 'EdgeDockAnimationTests|AppearanceSettingsValuesTests'`：6 项 XCTest（1 项跳过）及新增 2 项外观回归均通过。单独通过不能替代完整测试通过结论。
- 更早一轮测试与桌面操作并行时，显示器帮助焦点测试曾失败；最新完整测试中该组已通过。
- `git diff --check` 通过；设计检测器对修改的 SwiftUI 文件输出空列表。
- 未逐项手动验证浅色模式、减少透明度切换及不同桌面背景的模糊效果；当时 Windows 尚未改动、未发布远程安装包；最终发布验收以关联的 `0.22.8` 记录为准。
