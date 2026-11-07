# 输入源菜单与设置帮助集成安装验收

## 集成与本机安装

2026-11-07 将已批准的 `6db2060`（移除独立菜单帮助行）和 `947173b`（设置模态内即时打开帮助）从 `a1fa2d9` 快进集成到维护者主工作区。未增加产品或测试修改。此记录对应任务 #d4437f24。

使用 `bash scripts/build-app.sh` 构建 release，并安装到 `/Applications/T-Cube.app`。版本元数据仍为 `0.22.3` / build `45`，所以版本号本身不能区分旧安装和本次源代码构建；本次安装源提交为 `947173baed01d972887b9b47e6ea80854ef4d6dc`，未发布安装包。

构建、暂存和安装可执行文件 SHA-256 一致：

```text
74289c5a697444348381cfd266ca0531d6adef61bf9a7b3ca21f2b91e3240c4a
```

暂存及安装应用通过 `codesign --verify --deep --strict`。正常启动后，`NSWorkspace` 确认进程 `48934` 的可执行路径为 `/Applications/T-Cube.app/Contents/MacOS/TCube`；这属于进程启动核对，不代表逐项桌面点击验收。

## 旧应用与用户数据保护

通过 `NSRunningApplication.terminate()` 请求旧应用正常退出，确认进程消失后再替换应用。旧应用复制件和原安装目录，以及递归发现的全部 5 份用户 JSON 的退出前、退出后快照，保存在忽略目录：

```text
build/install-backups/input-help-947173b/20261107-195044/
```

5 份 JSON 在正常退出前后、安装前后、启动后及最终验收时均与退出后快照的 SHA-256 一致，没有用样本覆盖用户配置。`installation-result.json` 记录实际安装结果；`acceptance-progress.json` 是安装前状态快照。备份包含用户数据，不提交到仓库。

## 锁屏失败与解锁后回归

首次组合检查和单独帮助交互检查均出现 key-window 断言失败。直接读取系统会话发现 `CGSSessionScreenIsLocked=1`，前台应用为 `loginwindow`；当时窗口可见与嵌套模态断言通过，但不能验收前台焦点。未修改产品或降低断言，失败日志、截图和事件记录保留在备份目录的 `locked-session-tests/`。

维护者要求继续后，重新读取状态确认 `screenLocked=false`、前台为 `Agent Teams AI`，随后执行：

```bash
env TCUBE_HELP_INTERACTION_PREVIEWS=1 swift test --scratch-path .build/tests --no-parallel --filter DisplayInputHelpInteractionTests
env TCUBE_INPUT_PREVIEWS=1 swift test --scratch-path .build/tests --no-parallel --filter 'DisplayInput.*Menu|DisplayBrightnessMenu|BrightnessMenuTracking'
git diff --check
```

两条测试命令均退出 `0`：帮助原生交互 2 项通过；菜单与亮度检查中同步 XCTest 2 项通过、Swift Testing 7 项通过、1 项亮度专用导出跳过。空白检查通过。

帮助交互实际经过生产 `NSMenu` 设置动作、帮助按钮和嵌套模态循环。两次帮助往返覆盖立即显示、原设置保持可见、帮助获得 key focus、关闭后返回同一设置及焦点、未保存的样本值 `23/24` 保留，以及取消保留原映射、保存才持久化新映射、无积压帮助和零硬件写入。样本值不代表实际端口建议。

新事件记录三阶段均为 `activeWindowKey=true`；帮助阶段 `setupVisible=true`、`modalIsSetup=false`，返回阶段 `modalIsSetup=true`。已目视检查本轮导出的帮助、返回设置及原生菜单：独立菜单帮助行消失，输入源区后保留正常单条分隔，亮度与后续命令排列完整，返回设置仍显示样本值。相关实现与长期示例见[帮助模态验证记录](2026-11-07-display-input-help-modal.md)。

本轮新日志、原生截图与事件 JSON 归档在同一备份目录的 `unlocked-session-tests/`，其中 `help-interaction/` 保存三阶段窗口，`input-previews/input-native-menu-{light,dark}.png` 保存真实 NSMenu。它们使用临时配置和样本硬件，属于生产组件的自动化原生证据。

## 验收范围

本运行环境没有电脑操作工具，且 CLI 检测 `AXTrusted=false`。未执行已安装应用状态栏菜单的鼠标点击及设置→帮助→返回的手工桌面流程；自动化样本截图不作为该流程的替代证据。上述 AX 状态仅说明外部桌面操作能力限制，不用于解释 AppKit 自身焦点。

未主动切换实体显示器输入，未新增硬件兼容性结论，未验证 Intel Mac 或其他显示器型号，也未发布安装包。
