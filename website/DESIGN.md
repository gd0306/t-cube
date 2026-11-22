---
name: T-Cube Website
description: 连续炭绿底色、清晰文字与真实原生图像构成的桌面工具产品网站。
colors:
  bg: "#222d2b"
  surface: "#293633"
  ink: "#f4f2e9"
  muted: "#bdc9c3"
  accent: "#a5edc8"
  line: "#53635d"
  hero-copy: "#d9e0da"
  scrollbar: "#8fa79b"
  link-underline: "#a5edc866"
  dialog-backdrop: "#101b18e8"
typography:
  display:
    fontFamily: '"Avenir Next Condensed","Roboto Condensed","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "clamp(46px, 4.5vw, 68px)"
    fontWeight: 500
    lineHeight: 1.23
    letterSpacing: "0"
  headline:
    fontFamily: '"Avenir Next Condensed","Roboto Condensed","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "46px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "0"
  title:
    fontFamily: '"Avenir Next Condensed","Roboto Condensed","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "28px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "0"
  body:
    fontFamily: '"Avenir Next","Nunito Sans","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.75
  label:
    fontFamily: '"Avenir Next","Nunito Sans","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.75
  button:
    fontFamily: '"Avenir Next","Nunito Sans","PingFang SC","Noto Sans SC","Microsoft YaHei",sans-serif'
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.4
rounded:
  action: "2px"
  utility: "4px"
spacing:
  control-gap: "10px"
  brand-gap: "12px"
  inline-gap: "24px"
  action-gap: "28px"
  section-inset: "60px"
  section-start: "85px"
  section-end: "100px"
components:
  button-outline:
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.action}"
    padding: "15px 22px"
    height: "60px"
  button-outline-hover:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.bg}"
  button-compact:
    textColor: "{colors.ink}"
    rounded: "{rounded.action}"
    padding: "10px 22px"
    height: "44px"
  text-link:
    textColor: "{colors.accent}"
    height: "44px"
  navigation:
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    height: "44px"
  material-tab:
    textColor: "{colors.muted}"
    padding: "8px 0"
    height: "44px"
  material-tab-selected:
    textColor: "{colors.accent}"
  product-stage:
    backgroundColor: "{colors.surface}"
  keyboard-key:
    textColor: "{colors.ink}"
    rounded: "{rounded.utility}"
    padding: "4px 13px"
  disclosure:
    textColor: "{colors.ink}"
    padding: "23px 0"
    height: "76px"
  download-platform:
    textColor: "{colors.ink}"
    padding: "0 0 0 48px"
  media-dialog:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.ink}"
    rounded: "{rounded.utility}"
    padding: "56px 24px 20px"
    width: "min(1100px, 94vw)"
---

# Design System: T-Cube Website

## Overview

**Creative North Star: "炭绿桌面工作台"**

T-Cube 网站以用户指定的 [MotionObj Regex](https://motionobj.com/regex/) 为视觉参照：连续炭绿底色、开阔分栏、厚实简洁的标题、细描边行动入口与真实产品图像。它呈现一款随手可用的桌面工具；视觉证据来自现有应用图标、原生立方体渲染和 macOS / Windows 界面截图。

整体安静、直接、克制。页面依靠字号、留白与分隔线建立层级，薄荷绿集中用于选择状态、链接和焦点。用户本次确定的新方向替代此前蓝灰底色以及早期 Apple / OpenAI 参考；无交替明暗章节、装饰画布或粒子背景。当前首屏与故事顺序属于[页面方向契约](.impeccable/surfaces/website-index-html.md)，不把单页布局当作所有未来页面的固定模板。

**Key Characteristics:**

- 连续炭绿背景，以同色系表面和细线组织内容。
- Avenir Next Condensed / Roboto Condensed 标题配合 Avenir Next / Nunito Sans 正文；中文采用自然无衬线字形。
- 近直角描边按钮，真实截图承担产品说明。
- 中文默认、英文可切换，键盘操作与减少动态效果优先。

本文为 Scan 模式快照，来源为 `style.css`、`index.html` 与 `app.js`。frontmatter 的数值是当前实现；组件中的 `height` 对应 CSS `min-height`，并非固定高度。扩展状态与完整片段记录在 `.impeccable/design.json`。产品边界见 [PRODUCT.md](PRODUCT.md)。

## Colors

低饱和炭绿与暖白形成稳定底色，薄荷绿提供轻而明确的交互信号；页面仅有一组强调色。色值统一以上方 frontmatter 为准。

### Primary

- **薄荷绿** `accent`：链接、选中材质标签、焦点环、快捷键提示与局部标记。
- **薄荷半透明线** `link-underline`：文字链接的默认下划线；悬停变为 `currentColor`。

### Neutral

- **炭绿** `bg`：页面、页头、页脚、图片放大窗口的基础底色。
- **深苔绿** `surface`：材质预览与原生截图承托面。
- **暖白** `ink`：标题、品牌、按钮边框、主要文字；按钮悬停后作为填色。
- **雾灰绿** `muted`：正文、导航、辅助说明与未选中材质标签。
- **灰绿线** `line`：章节、表格、折叠项与容器的 `1px` 边框。
- **浅灰绿** `hero-copy`：首屏介绍文字，较正文略亮。
- **滚动条灰绿** `scrollbar`：根元素滚动条前景。
- **深绿遮幕** `dialog-backdrop`：图片对话框的半透明遮幕。

sidecar 的八阶色带仅供面板预览，并未成为页面新增色阶。

**The Continuous Ground Rule.** 从页头到页脚延续 `bg`，章节通过留白与 `line` 分隔，产品承托面使用 `surface`。

## Typography

**Display / Body Font:** 与指定参考页一致，已安装的 `Avenir Next Condensed` 用于标题，`Avenir Next` 用于正文。未安装时分别使用自托管开源 `Roboto Condensed` 与 `Nunito Sans` 拉丁字符 WOFF2 可变字体；中文依次由 `PingFang SC`、`Noto Sans SC`、`Microsoft YaHei` 提供。采用 `font-display: swap`，不请求外部字体服务，不分发系统专有字体。

**Character:** 英文标题为窄体 `400` 与 `-0.015em` 字距；中文标题为 `500` 与自然字距，不压缩汉字。正文为 `400`，按钮与品牌为 `700`。字号、配色和布局沿用现有页面，标题支持明确换行和 `text-wrap: balance`；正文使用 `text-wrap: pretty`。版本与大小使用 tabular numerals。

### Hierarchy

- **Display**：首屏标题使用 frontmatter 的流动字号，桌面上限 `68px`；`1100px` 以下 `48px`，`800px` 以下 `56px`，`600px` 以下 `46px`，`360px` 以下 `39px`。
- **Headline**：章节标题默认 `46px / 1.2`，一般在 `1100px` 以下降至 `39px`，`600px` 以下为 `34px`。下载和 FAQ 标题保留各自选择器的尺寸调整。
- **Title**：`h3` 默认 `28px`，`h4` 默认 `21px`；功能、平台与隐私标题使用现有 `21–32px` 局部尺寸。
- **Body**：默认 `17px / 1.75`，`600px` 以下为 `16px`；首屏介绍默认 `20px / 1.65`，最大 `28em`。其他说明段落最大约 `30–34em`。
- **Label**：导航为 `14px`；材质标签为 `13px`，移动端 `12px`；细节说明通常为 `12–15px`。
- **Button**：默认 `16px / 1.4`、`700`；紧凑按钮 `14px`。文案使用自然大小写。

## Layout

主容器 `.section-wrap` 最大 `1320px`，左右内边距 `60px`；页头最大 `1440px`。桌面首屏为 `.84fr / 1.16fr`，间隔 `50px`；功能区采用开放双栏，常见间隔 `100–110px`。章节常用上 `85px`、下 `100px` 的留白，并由 `1px` 细线衔接。

`1100px` 以下主容器内边距减至 `36px`；`800px` 以下首屏改为单列、隐藏页头中间导航，保留语言与下载入口，主章节留白降为 `65px`，部分功能仍可双栏。`600px` 以下内边距为 `24px`，功能、隐私、下载和 FAQ 统一单列，章节留白为 `52px`；首屏 CTA 纵向铺开。`360px` 以下主容器使用 `20px` 内边距，页头使用 `16px`。`1440px` 及以上首屏最小高度为 `730px`。

当前阅读顺序是产品预览、六面入口、桌面与显示器、剪贴板、本地数据、完整功能、下载与 FAQ；扩展页面沿用色彩、排版、表面和控件语言。表格使用局部横向滚动。语言切换保持同一网格，允许英文自然换行。

## Elevation & Depth

页面 UI 没有 `box-shadow`。层级来自炭绿底与深苔绿承托面的明度差、细边框和留白；立体感由原生产品渲染提供。图片放大窗口使用深绿半透明遮幕，不新增卡片阴影或模糊背景。

首屏图像以 `10s ease-in-out` 往复浮动，从 `translateY(-4px)` 到 `translateY(6px)`；离开视口或文档隐藏时暂停。支持悬停且允许动态效果时，指针产生约 ±`3.5deg` 水平与 ±`2.5deg` 垂直倾斜，过渡为 `.6s cubic-bezier(.16,1,.3,1)`。`prefers-reduced-motion: reduce` 禁用动画、过渡、平滑滚动及倾斜。

**The Flat Surface Rule.** 页面表面保持平整，让原生立方体与截图提供产品深度。

## Shapes

CTA 使用 `2px` 圆角与 `1px` 暖白边框，接近直角。材质和截图承托面保持直角，材质容器有 `1px` 灰绿边框。键帽和图片对话框使用 `4px` 圆角。圆形用于播放图标、列表圆点等小型功能标记；主要行动入口不用胶囊。

图像以 `object-fit: contain` 保持原生界面与透明渲染完整可读。小型放大标记贴在图片右下角，悬停或键盘聚焦时显示。

## Components

### Buttons

明确、轻薄的描边行动入口。背景透明，暖白文字与 `1px` 暖白边框，`2px` 圆角；内边距 `15px 22px`、最小高度 `60px`、内容间隔 `28px`。悬停填充暖白、文字变炭绿并上移 `2px`，过渡 `.22s`。没有单独定义 pressed 或 disabled 视觉状态。

紧凑按钮为 `10px 22px`、最小高度 `44px`；移动首屏按钮最小高度 `56px`。全站链接、按钮与 summary 的键盘焦点为 `2px` 薄荷绿轮廓、偏移 `5px`。

### Text Links

薄荷绿文字与细下划线，最小高度 `44px`；悬停强化下划线。用于辅助下载、文档与演示入口。

### Navigation

品牌图标配 `800` 字重名称，桌面导航 `14px` 雾灰绿文字，悬停为薄荷绿。页头有细底线，不固定在视口。`800px` 以下隐藏中间导航；语言按钮和紧凑下载按钮仍可见。中文默认，可切换英文，并在可用时保存语言选择。

### Material Tabs and Product Stage

三个原生图像状态共享深苔绿、细边框、直角预览台。材质按钮使用文字与下划线：未选中为雾灰绿，选中为薄荷绿与 `2px` 下划线；悬停文字为暖白。最小高度 `44px`，配合 `aria-selected`、单一 tab stop、左右方向键及 Home / End。切换同时更新图例与替代文字，不自动轮播。

### Native Image Containers

原生截图使用平整同色承托面，保持比例与真实平台外观。可放大图像的悬停亮度为 `1.07`、过渡 `.2s`；放大标记由透明变为可见。动态演示按需在对话框加载；关闭后清空内容，并把焦点还给打开者。

### Disclosures and Tables

完整功能与 FAQ 使用原生 `details / summary`，每项顶部有灰绿细线。功能 summary 默认最小高度 `76px`、`20px / 600`；FAQ 为 `68px / 17px`。悬停文字变薄荷绿，展开时加号变减号；内容自然展开，无高度动画。手势表格使用 `14px`、`18px 5px` 单元格内边距与横向细线。

### Keyboard Chord

快捷键说明使用薄荷绿行文与暖白键帽；键帽有 `1px` 灰绿边框、`4px` 圆角、`4px 13px` 内边距。它是非交互说明。

### Downloads

首屏和页尾各提供 macOS / Windows 直接安装包链接，共四个 `data-download` 锚点。页尾以平台图标、名称、版本、架构、系统要求和包大小形成开放信息组，使用同一描边 CTA。HTML 自带发布链接；脚本在版本、来源和三项必需资产验证通过后更新，失败时显示可读提示。

### Media Dialog

深炭绿对话框宽 `min(1100px, 94vw)`、最大高 `94svh`，`4px` 圆角与灰绿细边框；关闭按钮有 `44px` 点击区。图像最高 `75svh`，保留图例与替代文字。支持 Esc、关闭按钮与遮幕点击；不支持原生 dialog 时打开原始图像。

当前没有输入框、表单或独立 chip 控件，不定义尚未实现的样式。

## Do's and Don'ts

### Do:

- **Do** 延续炭绿背景、同色承托面和细分隔线，以排版与留白组织信息。
- **Do** 使用真实应用图标、原生渲染与平台截图，保留图片比例和有效说明。
- **Do** 保持近直角描边 CTA、可见键盘焦点与明确的双平台下载入口。
- **Do** 同步中文和英文文案、图片替代文字与状态信息，并尊重减少动态效果设置。

### Don't:

- **Don't** 重新引入旧蓝灰视觉、交替明暗章节或装饰粒子画布。
- **Don't** 给平整承托面新增投影、模糊玻璃层或胶囊式主要按钮。
- **Don't** 用虚构界面、用户数字或营销徽章替代真实产品证据。
- **Don't** 让连续动画在页面隐藏时运行，或要求 JavaScript 才能看到正文和下载链接。
