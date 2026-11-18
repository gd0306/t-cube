# 后台主题轮换内存增长诊断

## 现场证据

- 用户报告活动监视器中 T-Cube 占用 `5.19 GB`，主要为后台运行，基本无手动操作。
- 保留原进程 `25925`，未退出、重启、覆盖安装或更改用户设置。进程自 `2026-11-14 15:36:09` 运行，本机 macOS `27.2.1`（`26B131`）。
- `vmmap` 与 `footprint` 确认历史物理占用峰值约 `6.7 GiB`；首次采样时已回落到约 `473 MiB`。后续约三分钟内，图形资源分类从约 `213 MiB` 增至 `234 MiB`，普通堆分类约 `209 MiB`，基本不变。现场数值回落不能视为修复。
- 用户配置启用了每 `10` 秒自动轮换主题，且开启空闲省电。只读取相关配置与偏好，未更改。
- `leaks --noContent` 未发现不可达泄漏；这不能排除仍被框架持有的资源累积。堆快照中也有大量 SwiftUI Observation 跟踪对象，但本轮未证明它们是 GB 级增长的来源。

## 隔离复现

使用临时配置和临时窗口，不接入系统剪贴板，不实例化 Ctrl 监视器。先预热，再隐藏窗口，按 `.prism`、`.moonstone`、`.auroraFlow` 轮换 `180` 次。每次之间等待 `50 ms`，实际运行约 `42.5` 秒。此为加速诊断，并非日常运行时长基准。

```bash
env TCUBE_BACKGROUND_MEMORY_PROBE=1 \
  TCUBE_MEMORY_PROFILE_OUTPUT=/absolute/background-themes.json \
  swift test --scratch-path .build/tests --no-parallel \
  --filter BackgroundThemeMemoryProbeTests
```

| 隐藏后主题切换次数 | 物理占用 MiB |
| --- | ---: |
| 0 | 86.6 |
| 30 | 128.7 |
| 60 | 170.5 |
| 90 | 212.8 |
| 120 | 254.3 |
| 150 | 297.1 |
| 180 | 339.0 |
| 停止切换后再等 2 秒 | 338.0 |

另运行已有 `MemoryResourceBenchmarkTests`，常规短时刷新、修改、缩放、四次主题切换与隐藏的工作负载通过，峰值约 `299 MiB`；该短工作负载无法排除长时间后台增长。

## 定位与限制

`AppModel` 的主题轮换在隐藏时继续运行。`CubeSurfaceView.prepareAppearance` 的不可见分支立即执行外观更新；`CubeAura.update` 随主题变化重新生成光学 `TextureResource`。隔离实验确认：渲染器已隐藏、没有输入操作时，这条更新路径仍伴随持续的图形内存增长。旧资源在 RealityKit／Metal 内部的具体保留与回收时机尚未定位，未把所有历史峰值归因于单一内部对象。

本轮仅完成诊断与增加显式启用的复现探针，未修改产品实现、安装应用或宣布修复。原始内存分布、堆统计、采样和实验 JSON 保存在忽略目录 `.build/memory-diagnostic-20261118/`。
