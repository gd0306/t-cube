# Ctrl 一秒长按本机试用

> 本文为 build `48` 的本机试用记录。后续正式版 build `49` 保留一秒并解决 Ctrl 归属冲突，见[0.22.6 验收记录](2026-11-10-0.22.6-ctrl-context.md)。

- 按维护者要求仅做本机 macOS 试用：`0.22.6` build `48`。公开下载与 Windows 仍为 `0.22.5`，使用两秒长按。本轮未推送源码、打包公开安装包或改动已有 Release。
- 仅将 macOS Ctrl 长按阈值从 2 秒缩短到 1 秒，同步面板提示和测试示例；保留真实按下时刻计时、隐藏面板预热、键鼠取消、启动／唤醒需释放及每次按住只触发一次。没有添加双击手势。
- 先改一秒边界测试，旧实现确认失败（原生 8 个 issue、核心 7 个 issue），再将阈值改为一秒。聚焦回归 19 项原生与 8 项核心测试通过，包括未满一秒不触发、满一秒触发、首次采样延迟 0.8 秒只等待剩余 0.2 秒、超过一秒首次读立即触发和取消／重置回归。

```bash
env TCUBE_CLIPBOARD_PREVIEWS=1 swift test --scratch-path .build/tests --no-parallel --filter 'ControlHoldGestureTests|ControlHoldMonitorTests|ClipboardQuickPanelTests|ClipboardQuickPreviewTests'
bash scripts/build-app.sh
git diff --check
```

- 正式 release 配置构建并严格签名验证通过；正常退出旧应用，备份旧应用、5 个用户 JSON 和 UserDefaults 到忽略目录 `build/install-backups/0.22.6-local-1s/20261110-233349/`，再安装并从 `/Applications/T-Cube.app` 启动。备份含私人数据，不可提交或发布。
- 构建与安装可执行文件 SHA-256 均为 `1d280dd9b4fa93e2e997029499515f677455f18e347907f9cc98ecdf687ed7c0`。版本／build、签名、运行路径及安装／启动前后 5 个用户 JSON 字节一致已核对。没有更改登录项选择。
- 桌面自动化仍返回 `Sky Computer Use native pipe startup failed` 和 `The browser access host is unavailable`，因此没有测得本机物理按键到窗口可见的端到端耗时；一秒是触发阈值，不是对系统调度与首帧显示零耗时的承诺。体感由维护者试用确认。
