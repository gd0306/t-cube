# macOS Ctrl 长按事件计数延迟修复

- 本机环境：macOS `27.2.1`（`26B131`）。此为 `0.22.9` 的本机修复构建，未发布新安装包。
- 原因：实测 `CGEventSource.flagsState` 的 Ctrl 状态先更新，`counterForEventType` 与 `secondsSinceLastEventType` 随后才更新。例如首次观察到按下时计数仍为 `122`，约半秒后变为 `123`。旧实现要求首次按下采样同时出现恰好一次计数变化，并要求事件时间晚于上一采样；因此正常长按会被取消。未验证重启本身是该系统行为的原因。
- 修复：暂存首次观察到的按下时间，等待恰好一次修饰键计数确认；等待期间出现输入、其他修饰键、立方体占用或采样中断仍取消。若计数已更新但事件时间早于上一释放采样，则从观察到的按下时间计时，避免提前触发。保留启动、唤醒和会话切换后必须先释放的门禁。
- 新回归测试在旧实现上先失败，再应用修复；最终聚焦测试 `35` 项原生与 `8` 项核心测试通过，涵盖延迟确认、未确认不打开、组合输入取消、pending 释放／停止／会话重置、旧事件时间回退及现有剪贴板面板行为。

```bash
swift test --scratch-path .build/tests --no-parallel --filter 'ControlHold|ClipboardQuick'
bash scripts/build-app.sh
git diff --check
```

- Release 构建与严格深度签名验证通过。正常退出旧应用后，将旧应用、5 份用户 JSON 和 UserDefaults 备份到忽略目录 `build/install-backups/ctrl-hold-fix/20261114-153607/`；安装前后 5 份 JSON 字节一致。
- 构建与 `/Applications/T-Cube.app` 已安装可执行文件 SHA-256 一致：`820533e8acdbe4af33e4aea873c4d7e303f7c80a0a70f856df13afa5e0d11361`。应用已从安装目录启动。
- 通过系统发送 Ctrl 按键事件，使用系统窗口列表和辅助功能窗口标题确认已安装应用出现 `T-Cube · 剪贴板快捷历史`。补充系统事件验证：短按 `0.3` 秒不打开、`Ctrl+Shift` 持续 `1.6` 秒不打开，释放后单独 Ctrl 持续 `1.5` 秒能打开，随后 Esc 收起。该检查属于本机自动化，不代表实体键盘手动检查或再次重启后的验证；未读取剪贴板内容。
- 独立只读代码评审未发现阻塞问题。未运行完整 macOS 测试套件；未修改 Windows 实现或公开下载链接。
