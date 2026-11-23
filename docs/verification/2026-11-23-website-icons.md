# 网页图标与单色标题标记（源码 0.22.12）

## 行为

网页入口在后台匿名请求站点根目录的 `/favicon.ico`；无可用图标时，解析根页面声明的 icon / apple-touch-icon，尝试有界数量的候选。请求不包含保存入口的路径查询、浏览器 Cookie、认证头或第三方 favicon 服务。保持原有默认图标直至获得可解码图像；失败不弹窗、不影响打开入口。

图标按 origin 做有界会话缓存，不改配置 JSON；移除入口后收敛缓存，并隔离取消任务、URL 替换和过期异步结果。macOS 的渲染函数只读缓存，真实 AppDelegate 显式启动后台请求；测试与预览默认不联网。网络响应、请求/跳转、时限及图片尺寸有限制。图像转为本地 PNG 后使用，SVG 等不可用格式回退到默认图标。

立方体图集和展开面板在网页标题前绘制单色线框地球标识，不把符号写入名称。长标题省略、完整名称 tooltip、可访问性名称与现有标题点击范围保留。无图标时原默认蓝色网页图标保持不变。

## 验证

- macOS：先观察新标题标记用例失败（标记区域白色像素为 0），再验证绘制通过。网站图标 fetch/cache 用例先 RED 后 GREEN；HTML 注释和 SVG 占用候选预算的问题也有独立 RED → GREEN 回归。
- `swift test --scratch-path .build/tests --no-parallel` 全量通过：TCubeTests 的 246 项 Swift Testing 用例、CubeCoreTests 的 148 项用例，及命令中的原生 XCTest 检查均以进程 exit 0 完成。后续 HTML 候选修复对应的定向回归（18 + 2 项）也通过。
- URLProtocol 受控测试验证匿名请求头、HTTP 错误、响应体/Content-Length 上限；fetcher 用例验证缺省路径、HTML 图标声明、非法来源、损坏/过大图像和缓存刷新。
- 显式联网测试分别从产品官网和维护者当前配置的网站获取并解码 PNG；后者产生 2337 字节 PNG。没有传递用户保存 URL 的查询参数。
- 原生预览显式启用联网后，第一项展示真实网站图标，其余项保留默认图标；已检查深浅背景立方体、图集和展开面板。README 使用新的真实展开面板截图。
- Windows：代理执行 `npm test`，301 项中 298 通过、3 跳过、0 失败；typecheck、build 通过。Electron 本地 HTTP fixture 和显式官网联网 smoke 通过，覆盖 PNG、经典 DIB ICO、默认回退、origin 去重、配置不变、标题线稿/省略/tooltip。此处为 macOS 上的 Electron Windows 客户端预览，不等同于实体 Windows 安装测试。
- 独立只读代码审查无 Critical / Important；发现的 HTML 注释/SVG 候选筛选 Minor 已修复并经复核关闭。

## 本机安装

正式构建 `bash scripts/build-app.sh` 通过，安装版本 `0.22.12`、build `55`。旧应用正常退出后保留在忽略的 `build/acceptance-0.22.12-20261123-123755/T-Cube.app`，4 份现有 JSON 和偏好同时备份。安装后 4 份 JSON 语义逐项一致，没有覆盖用户入口或其他设置。

`/Applications/T-Cube.app` 的签名验证通过，可执行文件与构建产物逐字节一致，SHA-256：`a3cbb0f6177f6ab61055ff65756ffc0adde949b59ea2c584bcca7805e3b3d2fb`。已验证新进程从 `/Applications/T-Cube.app/Contents/MacOS/TCube` 启动。外部实体键盘/多显示器交互未作为本次人工桌面验收声称；功能视觉来自独立原生预览和已有真实网站图标请求验证。

## 交付边界

本次交付源码和维护者本机安装，不是双平台公开安装包发布。GitHub 已发布安装包保持 `0.22.11`，下载表及校验和链接未指向未发布版本。根目录两份 README 和 Windows README 已明确区分新源码与已发布安装包；产品网站仍描述当前公开安装包，待新版本发布时再同步该站的功能文案。

本地证据保留在忽略的 `.build/website-icon*.log`、`.build/website-icons-*.log`、`.build/website-title-previews/` 和 `windows/.cache/smoke/website-icons/`。
