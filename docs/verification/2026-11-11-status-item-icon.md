# 0.22.7 macOS 菜单栏图标

## 设计与实现

- 参考已批准的应用图标，提炼三块圆角立方面与 Y 形留白；区别于用户参考图的细线框与侧面镂空。顶面、左右面使用轻微不同的遮罩透明度，保持小尺寸下的立体辨识。
- `StatusItemIcon.make()` 使用 AppKit 矢量绘制，逻辑尺寸 18 × 18 pt，`isTemplate = true`，由系统适配菜单栏颜色；没有彩色底板、图片缩小采样或外部资源依赖。
- 替换状态栏原 `cube.transparent` 系统符号；保留菜单、工具提示、辅助功能名称及状态项位置标识。

<img src="../images/status-item-icon.png" width="560" alt="新菜单栏图标的浅深色原尺寸与五倍细节预览">

这是使用生产图标工厂生成的原生矢量预览，颜色由预览画布模拟模板着色，不是菜单栏屏幕截图。

## 自动化与本机验收

- Swift 6 独立编译生产图标工厂，导出 1×／2×／3× 遮罩及浅深色预览，检查透明角落、模板属性、18pt 尺寸并查看实际原尺寸效果。此可逆视觉改动没有新增镜像绘制实现的单元测试。
- `StatusMenuLayoutTests`、`DisplayBrightnessMenuTests`、`DisplayInputMenuTests` 共 10 项通过；正式构建、签名深度／严格检查、DMG 校验及挂载内容核对通过。
- macOS `0.22.7` build `50` 正常替换到 `/Applications/T-Cube.app` 并从该位置启动；构建／安装可执行文件 SHA-256 为 `7a2b405c90cfdbcd9e98c0f4f40fa0e1b364eb79b384fc87acc34d22c21c5132`。
- 旧应用、5 个用户 JSON 和 UserDefaults 保存在忽略目录 `build/install-backups/0.22.7/20261111-174618/`。安装替换时 JSON 字节一致；启动后观察到 `configuration.json` 的 `windowPosition` 更新，其余配置内容及另外 4 个 JSON 保持不变；新旧坐标均在当前显示器可用范围。没有手动移动窗口或用测试数据覆盖入口、外观，未将旧位置回写到用户当前运行的布局。
- 桌面自动化入口仍返回 `Sky Computer Use native pipe startup failed` 和 `The browser access host is unavailable`，因此没有声称通过工具手动点击了已安装图标或验收实际菜单栏着色。

## 跨平台原生回归

- [Windows 源码 CI](https://github.com/gd0306/t-cube/actions/runs/42998436519) 在打包提交的 Windows 2022 / 2025 均通过，包括单元测试、类型检查、构建、隔离安装与真实输入烟测。
- 本版 Windows 仅同步版本元数据，不更改托盘图标或其它界面；两个平台将使用同一打包提交 `7a977a1aecffc25bc24c6fbfdb0e9da484c7ac30`。
- macOS 既有完整同进程动画顺序测试失败边界未变，见[原验证记录](2026-11-08-release-consistency.md)。本次聚焦菜单检查不能作为完整套件绿色的证明。

## 正式 Windows 安装包

- [Windows 安装包 CI](https://github.com/gd0306/t-cube/actions/runs/42998539192) 在同一打包提交成功。单元测试 280 通过、2 项跳过；x64 NSIS 制作、实际安装、显示器 worker 独立原生检查和安装应用烟测均通过。
- 诊断结果有 27 项原生验收；一秒剪贴板在正式安装版 1104 ms 显示，Ctrl 立方体归属、编辑、复制与登录项隔离检查仍通过。
- 两个平台仍采用既有 ad-hoc／未 Authenticode 签名策略，未新增公证或签名承诺。

## 公开发布核验

[v0.22.7](https://github.com/gd0306/t-cube/releases/tag/v0.22.7) 已公开为最新稳定版，四个附件如下：

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `SHA256SUMS.txt` | 198 | `1d45a3c5eb59dbd77066e4aef92179836fc62241ffe0318b01ff16c54b8242dc` |
| `SOURCE_COMMIT.txt` | 41 | `a30454eb39447c5e1f289090c3aa64fe9cdaa66f944b1c4642db9a12611fe44d` |
| `T-Cube-0.22.7-macos-arm64.dmg` | 4051416 | `90b8bdab4bd867cb4e4a77c3db05868f86fa29008cbc39c88082c5d0fb78102c` |
| `T-Cube-0.22.7-windows-x64-setup.exe` | 125807826 | `2946b982163bd5c6e974fd62fa739dc13babf8ce270e2bb4d8cd5b6c42e95dd1` |

- 草稿阶段确认全部附件完整上传，大小与 GitHub SHA-256 digest 匹配本地产物，再公开并设为 latest。
- 从无需认证的公开地址完整下载四个附件，字节数与 SHA-256 逐项匹配本地及 GitHub 元数据；安装包清单、源码提交文件、标签与 Release target 均一致。
- 根双语 README 及 Windows README 下载链接同步至 `0.22.7`；后续文档提交不改变包内源码。
