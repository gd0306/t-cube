'use strict';

const translations = {"t0": {"zh": "产品", "en": "Product"}, "t1": {"zh": "桌面", "en": "Desktop"}, "t2": {"zh": "功能", "en": "Features"}, "t3": {"zh": "通透玻璃", "en": "Glass"}, "t4": {"zh": "极光流动", "en": "Aurora"}, "t5": {"zh": "安静待机", "en": "At rest"}, "t6": {"zh": "外观与交互", "en": "Appearance & interaction"}, "t7": {"zh": "玻璃与史莱姆双材质；9 款主题、自定义双色渐变，每 10 或 20 秒自动轮换。", "en": "Glass and Slime materials; nine themes, custom two-color gradients and automatic cycling every 10 or 20 seconds."}, "t8": {"zh": "悬停显示图标并放大 1.1–4.0 倍；移开后恢复。空闲旋转、滚轮与双指滚动、右键拖动旋转。", "en": "Hover reveals icons and enlarges the cube by 1.1–4.0×. Move away to restore; use idle rotation, scrolling, two-finger gestures or right-drag rotation."}, "t9": {"zh": "macOS 26+ 支持原生 Clear Liquid Glass，早期系统使用磨砂回退；Windows 使用独立玻璃渲染。", "en": "macOS 26+ supports native Clear Liquid Glass, with frosted fallbacks on earlier systems. Windows has its own glass renderer."}, "t10": {"zh": "Windows 11 22H2+ 设置与快捷面板使用 Acrylic；旧系统、减少透明度与高对比度使用实色回退。尊重减少动态效果。", "en": "Settings and quick panels use Acrylic on Windows 11 22H2+; older systems, reduced transparency and high contrast use solid fallbacks. Reduced motion is respected."}, "t11": {"zh": "启动与入口", "en": "Launchers & shortcuts"}, "t12": {"zh": "六个面、每面四项，共 24 个快捷槽位；支持应用、文件夹、文件、网页和平台系统设置入口。", "en": "Six faces with four slots each: 24 shortcuts for apps, folders, files, websites and platform system settings."}, "t13": {"zh": "拖入配置，直接点击打开，或先展开四图标面板。移除入口不会删除原文件或应用。", "en": "Configure with drag and drop. Launch directly or expand a four-icon panel first. Removing a shortcut never deletes the original app or file."}, "t14": {"zh": "自动获取网页图标，无法获取时保留默认图标；标题前显示单色地球标记，长标题可悬停查看。", "en": "Website icons load automatically, with the default icon as a fallback. Titles carry a monochrome globe marker; hover to read long names."}, "t15": {"zh": "Windows 提供可搜索的应用选择器，支持已注册系统／Store 应用与便携 .exe。", "en": "Windows includes a searchable application picker for registered desktop, system and Store apps, plus portable .exe files."}, "t16": {"zh": "桌面与显示器", "en": "Desktop & displays"}, "t17": {"zh": "靠近屏幕外侧约 32 逻辑像素，离开约 0.8 秒后收成 10 × 56 控制条；悬停恢复，原位置不变。", "en": "Within about 32 logical pixels of an outer display edge, leaving for about 0.8 seconds collapses the cube into a 10 × 56 handle. Hover to restore without changing its saved position."}, "t18": {"zh": "macOS 约 0.36 秒吸附、0.46 秒展开；可中断，减少动态效果时跳过空间过渡。", "en": "macOS uses an approximately 0.36-second absorption and 0.46-second reveal; transitions can be interrupted and are skipped with reduced motion."}, "t19": {"zh": "全屏自动隐藏、屏幕四角／中央快速放置、拖动保存位置；显示器检测不读取屏幕像素。", "en": "Fullscreen auto-hide, corner/center placement and saved dragging positions. Display detection does not read screen pixels."}, "t20": {"zh": "macOS 独立调节屏幕亮度。Apple 屏幕走原生控制，外接屏幕需要 Apple Silicon 与可用 DDC/CI。", "en": "Independent brightness on macOS: native control for Apple displays; external hardware backlight control requires Apple Silicon and usable DDC/CI."}, "t21": {"zh": "双平台 Type-C／HDMI 输入切换，按显示器保存实测代码并回读确认。硬件兼容性取决于固件、驱动和连接路径。", "en": "Type-C/HDMI switching on both platforms, with measured codes saved per display and confirmed readback. Compatibility depends on firmware, drivers and the connection path."}, "t22": {"zh": "剪贴板与常用内容", "en": "Clipboard & reusable content"}, "t23": {"zh": "会话历史仅在内存中；启动后自动记录，可暂停，不导入启动前的剪贴板，退出即清除。", "en": "Session history stays in memory, starts recording on launch and can be paused. Pre-launch clipboard content is not imported; quitting clears history."}, "t24": {"zh": "文字最多 100 条：单条 64 KiB、总计 2 MiB；图片最多 10 张：单张 8 MiB PNG、总计 32 MiB、1600 万像素上限。", "en": "Up to 100 text entries: 64 KiB each and 2 MiB total. Up to 10 images: 8 MiB PNG each, 32 MiB total and a 16-megapixel limit."}, "t25": {"zh": "立方体外单独长按 Ctrl 1 秒唤出可拖动快捷历史，支持复制、编辑和删除；每次重新唤出回到历史列表。打开完整历史管理可搜索、多选合并。", "en": "Hold Ctrl alone for one second outside the cube for draggable quick history: copy, edit and delete. Each invocation returns to the list. Open the full history manager for search and multi-entry merging."}, "t26": {"zh": "空白整理、大小写转换、JSON 格式化／压缩、URL 编解码均在本地预览；复制或明确保存后才写入。图片不含 OCR。", "en": "Whitespace cleanup, case conversion, JSON formatting/minification and URL encoding/decoding are previewed locally. Write only by copying or explicitly saving; no image OCR."}, "t27": {"zh": "常用内容支持分组、收藏、搜索、结构化字段与 {{变量}} 模板。macOS 用 ⌘⇧Space，Windows 用 Ctrl+Shift+Space 唤出。", "en": "Reusable content supports groups, favorites, search, structured fields and {{variable}} templates. Open with ⌘⇧Space on macOS or Ctrl+Shift+Space on Windows."}, "t28": {"zh": "粘贴前验证目标焦点；macOS 自动粘贴需要辅助功能授权。无法安全恢复焦点时保留复制内容，供手动粘贴。", "en": "Target focus is verified before paste; automatic paste on macOS requires Accessibility permission. When focus cannot be safely restored, content remains copied for manual paste."}, "t29": {"zh": "性能、数据与维护", "en": "Performance, data & maintenance"}, "t30": {"zh": "静置节能暂停渲染：macOS 默认开启，Windows 默认关闭。隐藏时停止渲染；macOS 隐藏／遮挡时延后主题纹理更新。", "en": "Idle power saving pauses rendering: enabled by default on macOS, off by default on Windows. Hidden surfaces stop rendering; macOS defers hidden/occluded theme textures."}, "t31": {"zh": "复用纹理并限制缓存；修改外观即时保存，仅重置当前外观，不影响入口和位置。", "en": "Textures are reused and caches are bounded. Appearance changes save immediately; resetting appearance preserves launchers and position."}, "t32": {"zh": "配置导入／导出提供预览、导入前备份、恢复与失效入口重连；损坏配置保留。显示器映射独立保存，不含在启动器配置导出中。", "en": "Configuration import/export has previews, pre-import backups, restore and broken-shortcut relinking; corrupt files are preserved. Display mappings are stored separately and excluded from launcher exports."}, "t33": {"zh": "安装版首次启动默认开启登录自启，可关闭并记住；尊重系统批准和禁用状态。", "en": "Installed apps enable login startup by default on first launch. Opt out and the choice is remembered; system approvals and disabled states are respected."}, "t34": {"zh": "核心功能本地运行，无遥测、无云同步。网页图标直接从已配置站点匿名获取，不使用第三方服务；手动检查或启用默认关闭的 6 小时版本提醒时访问 GitHub。", "en": "Core features run locally, with no telemetry or cloud sync. Website icons are fetched anonymously from configured sites without third-party services. Manual checks and optional six-hour release reminders contact GitHub; reminders default off."}, "t35": {"zh": "悬停 / 移开", "en": "Hover / leave"}, "t36": {"zh": "显示图标、放大 / 恢复静置", "en": "Reveal icons and enlarge / return to rest"}, "t37": {"zh": "左键拖动", "en": "Left drag"}, "t38": {"zh": "移动并保存位置", "en": "Move and save position"}, "t39": {"zh": "右键拖动 / 滚动", "en": "Right drag / scroll"}, "t40": {"zh": "自由旋转立方体", "en": "Rotate the cube"}, "t41": {"zh": "立方体上按住 Ctrl", "en": "Hold Ctrl over cube"}, "t42": {"zh": "临时恢复原大小，可配合左键拖动", "en": "Restore resting size; combine with left drag"}, "t43": {"zh": "立方体外 Ctrl 1 秒", "en": "Ctrl for 1s outside cube"}, "t44": {"zh": "打开剪贴板快捷历史", "en": "Open quick clipboard history"}, "t45": {"zh": "点击外部 / Esc", "en": "Click outside / Esc"}, "t46": {"zh": "收起展开的四图标面板", "en": "Dismiss the expanded panel"}, "t47": {"zh": "需要哪些权限？", "en": "Which permissions are needed?"}, "t48": {"zh": "核心启动和显示器检测不需要屏幕录制权限。macOS 自动粘贴需要辅助功能授权；登录自启可能需要系统批准。显示器控制还取决于硬件连接。", "en": "Core launching and display detection do not need Screen Recording permission. Automatic paste on macOS requires Accessibility; login startup may require system approval. Display control also depends on hardware."}, "t49": {"zh": "显示器切换一定可用吗？", "en": "Will every monitor support switching?"}, "t50": {"zh": "不是。显示器需支持 DDC/CI；请用实体菜单分别切到两个输入，在当前活动主机读取代码后保存。检测到设备不代表兼容。切换后失去回读时，请用活动主机或显示器实体菜单恢复。", "en": "No. The display must support DDC/CI. Physically select each input, read its code on the active host and save both codes. Detection does not guarantee compatibility. If readback is lost after switching, recover from the active host or physical display menu."}, "t51": {"zh": "剪贴板会保存到磁盘吗？", "en": "Is clipboard history saved to disk?"}, "t52": {"zh": "会话历史不写磁盘、不云同步，退出即清除。你明确保存到常用内容的记录会本地持久化。部分隐私排除标记会被跳过，但未标记的敏感内容仍可能被会话历史记录，可随时暂停或清空。", "en": "Session history is never written to disk or synced; quitting clears it. Records explicitly saved to the content library persist locally. Some privacy exclusion markers are respected, but unmarked sensitive content may be recorded; pause or clear history when needed."}, "t53": {"zh": "下载后如何升级？", "en": "How do I upgrade?"}, "t54": {"zh": "先正常退出旧版，再安装新版本，并保留现有配置。macOS 当前为 ad-hoc 签名、未做 Developer ID 公证；Windows 安装包未做 Authenticode 签名，系统可能显示安全提示。仅从可信发布渠道下载。", "en": "Quit the previous version normally, install the new build and keep your configuration. macOS builds are ad-hoc signed and not Developer ID notarized; Windows installers are not Authenticode signed, so system security prompts may appear. Download only from trusted release sources."}, "t55": {"zh": "跳到主要内容", "en": "Skip to content"}, "t56": {"zh": "下载", "en": "Download"}, "t59": {"zh": "应用、文件、剪贴板与显示器。\n一个悬浮立方体，接起桌面日常。", "en": "Apps, files, clipboard and displays.\nOne floating cube for your everyday work."}, "t60": {"zh": "下载 T-Cube", "en": "Download T-Cube"}, "t62": {"zh": "macOS / Windows · 免费开源", "en": "macOS / Windows · Free and open source"}, "t69": {"zh": "六个面，\n装下你的快捷入口。", "en": "Six faces.\nA place for every shortcut."}, "t70": {"zh": "应用、文件、网页与系统设置，拖入即可添加。点击直达，或展开四图标面板。", "en": "Drag in apps, files, websites or system settings. Launch directly, or expand a four-icon panel."}, "t71": {"zh": "自动获取网页图标，标题清晰可辨。", "en": "Automatic website icons, with clearly marked titles."}, "t72": {"zh": "左键移动，右键或滚动旋转。", "en": "Left-drag to move. Right-drag or scroll to rotate."}, "t73": {"zh": "Windows 支持搜索已安装应用。", "en": "Search installed apps on Windows."}, "t74": {"zh": "材质与主题", "en": "Materials and themes"}, "t75": {"zh": "玻璃、史莱姆与九款主题，支持自定义渐变和自动轮换。", "en": "Glass, Slime and nine themes, with custom gradients and automatic cycling."}, "t76": {"zh": "悬停显现，1.1–4.0 倍放大。", "en": "Reveal on hover. Enlarge from 1.1–4.0×."}, "t81": {"zh": "桌面控制", "en": "Desktop controls"}, "t83": {"zh": "贴边收起，全屏隐藏", "en": "Edge docking and fullscreen hiding"}, "t84": {"zh": "移开指针后收起，悬停恢复；全屏时自动隐藏，原位置不变。", "en": "Move away to collapse, hover to restore. Hide in fullscreen and keep the saved position."}, "t85": {"zh": "播放演示", "en": "Play demo"}, "t88": {"zh": "macOS 显示器 Type-C 与 HDMI 输入切换", "en": "Type-C and HDMI input switching on macOS"}, "t89": {"zh": "显示器控制", "en": "Display controls"}, "t90": {"zh": "从菜单栏或托盘切换 Type-C / HDMI，按显示器保存映射并回读确认。macOS 支持独立调节屏幕亮度。", "en": "Switch Type-C / HDMI from the menu bar or tray, with per-display mappings and confirmed readback. macOS also supports independent display brightness."}, "t92": {"zh": "硬件要求", "en": "Hardware requirements"}, "t93": {"zh": "复制过的，\n随时找回来。", "en": "Copied once.\nReady when you need it."}, "t95": {"zh": "macOS 剪贴板快捷历史面板，包含文字和图片记录", "en": "macOS quick clipboard history with text and image records"}, "t96": {"zh": "Ctrl 长按一秒", "en": "Hold Ctrl for one second"}, "t97": {"zh": "在立方体外唤出快捷历史，点击复制、编辑或删除。搜索和多选合并位于完整历史管理中。", "en": "Open quick history outside the cube to copy, edit or delete. Search and multi-entry merging are in the full history manager."}, "t98": {"zh": "本地文字处理", "en": "Local text tools"}, "t99": {"zh": "空白整理、大小写、JSON 与 URL 编解码。预览后复制或保存。", "en": "Clean whitespace, change case, format JSON and encode URLs. Preview, then copy or save."}, "t100": {"zh": "文案与模板", "en": "Snippets and templates"}, "t101": {"zh": "分组、收藏、结构化字段与 {{变量}} 模板，填好即可复用。", "en": "Groups, favorites, structured fields and {{variable}} templates, ready to reuse."}, "t106": {"zh": "留在本地，\n轻装运行。", "en": "Local by design.\nLight on your desktop."}, "t107": {"zh": "空闲节能，隐藏时停止渲染。", "en": "Idle power saving. Hidden surfaces stop rendering."}, "t108": {"zh": "GitHub", "en": "GitHub"}, "t109": {"zh": "会话历史只在内存", "en": "Session history stays in memory"}, "t110": {"zh": "退出即清除，不写入磁盘。主动保存到常用内容的记录会在本地保留。", "en": "Cleared on quit, never written to disk. Items explicitly saved to the content library persist locally."}, "t111": {"zh": "无遥测、无云同步", "en": "No telemetry or cloud sync"}, "t112": {"zh": "配置留在本地，支持导入导出和备份。网页图标直接访问已配置站点；检查更新和版本提醒访问 GitHub。", "en": "Configuration stays local, with import, export and backups. Website icons contact configured sites directly; update checks and reminders contact GitHub."}, "t113": {"zh": "完整功能", "en": "All features"}, "t117": {"zh": "文档", "en": "Documentation"}, "t118": {"zh": "控制与手势", "en": "Controls and gestures"}, "t119": {"zh": "控制与手势", "en": "Controls and gestures"}, "t120": {"zh": "把 T-Cube\n放上你的桌面。", "en": "Make room\nfor T-Cube."}, "t123": {"zh": "Apple Silicon", "en": "Apple Silicon"}, "t124": {"zh": "下载 macOS 版", "en": "Download for macOS"}, "t125": {"zh": "macOS 15+ · Apple Silicon · DMG", "en": "macOS 15+ · Apple Silicon · DMG"}, "t127": {"zh": "独立安装包", "en": "Standalone installer"}, "t128": {"zh": "下载 Windows 版", "en": "Download for Windows"}, "t129": {"zh": "Windows 10 22H2 / 11 · x64 · EXE", "en": "Windows 10 22H2 / 11 · x64 · EXE"}, "t132": {"zh": "更新记录", "en": "Release notes"}, "t133": {"zh": "SHA-256 校验和", "en": "SHA-256 checksums"}, "t134": {"zh": "GitHub", "en": "GitHub"}, "t135": {"zh": "常见问题", "en": "Frequently asked questions"}, "t137": {"zh": "gd306.cn", "en": "gd306.cn"}, "heroTitle": {"zh": "常用的一切，\n就在手边。", "en": "Your desktop.\nWithin reach."}, "launcherAlt": {"zh": "T-Cube 展开的四项网页入口与标题", "en": "Four expanded website shortcuts with titles in T-Cube"}, "toolsAlt": {"zh": "macOS 剪贴板文字处理窗口，包含 JSON 与 URL 本地工具", "en": "Native macOS clipboard text tools with local JSON and URL processing"}, "libraryAlt": {"zh": "Windows 常用内容库，包含分组与结构化模板", "en": "Native Windows content library with groups and structured templates"}, "announcement": {"zh": "✦ T-Cube v0.22.12 已发布 · 适用于 macOS 与 Windows", "en": "✦ T-Cube v0.22.12 is live · For macOS & Windows"}, "heroAlt": {"zh": "透明 3D 立方体启动器，图标贴合曲面", "en": "Transparent 3D launcher with shortcut icons following the cube’s curved faces"}};

const themeLabels = {
    zh: { group: "外观主题", system: "跟随系统", light: "浅色模式", dark: "深色模式" },
    en: { group: "Theme mode", system: "System", light: "Light", dark: "Dark" }
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

let language = "zh";
let themeMode = "system";
let resolvedTheme = "dark";
let selectedMaterial = 0;
let releaseState = "initial";
let latestVersion = "0.22.12";
let triggerFieldPulse = null;

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
if (!prefersReducedMotion) {
    document.documentElement.classList.add("js-motion");
}

const colorSchemeMedia = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;

function updateThemeIndicator() {
    const activeBtn = $('[data-theme-option][aria-checked="true"]');
    const indicator = $(".theme-switcher .theme-indicator");
    if (!activeBtn || !indicator) return;
    indicator.style.width = `${activeBtn.offsetWidth}px`;
    indicator.style.transform = `translateX(${activeBtn.offsetLeft}px)`;
}

function updateThemeLabels() {
    const group = $("[data-theme-group]");
    const copy = themeLabels[language] || themeLabels.zh;
    if (group) group.setAttribute("aria-label", copy.group);
    $$("[data-theme-option]").forEach(btn => {
        const opt = btn.dataset.themeOption;
        const label = copy[opt];
        if (label) {
            btn.title = label;
            btn.setAttribute("aria-label", label);
        }
    });
}

function applyTheme(nextMode, persist = true) {
    themeMode = (nextMode === "light" || nextMode === "dark" || nextMode === "system") ? nextMode : "system";
    const prefersDark = colorSchemeMedia ? colorSchemeMedia.matches : true;
    resolvedTheme = themeMode === "system" ? (prefersDark ? "dark" : "light") : themeMode;

    const root = document.documentElement;
    root.dataset.themeMode = themeMode;
    root.dataset.theme = resolvedTheme;
    root.style.colorScheme = resolvedTheme;

    $$("[data-theme-option]").forEach(btn => {
        const selected = btn.dataset.themeOption === themeMode;
        btn.setAttribute("aria-checked", String(selected));
        btn.tabIndex = selected ? 0 : -1;
    });

    requestAnimationFrame(updateThemeIndicator);

    if (persist) {
        try {
            localStorage.setItem("tcube-theme", themeMode);
        } catch (_) {}
    }
}

(() => {
    const options = ["system", "light", "dark"];
    let initialMode = document.documentElement.dataset.themeMode || "system";
    try {
        const saved = localStorage.getItem("tcube-theme");
        if (saved === "light" || saved === "dark" || saved === "system") initialMode = saved;
    } catch (_) {}
    applyTheme(initialMode, false);

    $$("[data-theme-option]").forEach(btn => {
        btn.addEventListener("click", () => applyTheme(btn.dataset.themeOption, true));
        btn.addEventListener("keydown", event => {
            const idx = options.indexOf(btn.dataset.themeOption);
            let nextIdx;
            if (event.key === "ArrowRight") nextIdx = (idx + 1) % options.length;
            else if (event.key === "ArrowLeft") nextIdx = (idx + options.length - 1) % options.length;
            else if (event.key === "Home") nextIdx = 0;
            else if (event.key === "End") nextIdx = options.length - 1;
            if (nextIdx !== undefined) {
                event.preventDefault();
                const nextMode = options[nextIdx];
                applyTheme(nextMode, true);
                $(`[data-theme-option="${nextMode}"]`)?.focus();
            }
        });
    });

    if (colorSchemeMedia) {
        const onSystemChange = () => {
            if (themeMode === "system") applyTheme("system", false);
        };
        if (typeof colorSchemeMedia.addEventListener === "function") {
            colorSchemeMedia.addEventListener("change", onSystemChange);
        } else if (typeof colorSchemeMedia.addListener === "function") {
            colorSchemeMedia.addListener(onSystemChange);
        }
    }
})();

const materialImages = ["cube-hover-dark.png", "cube-aurora-dark.png", "cube-idle-dark.png"];
const materialVersion = "20261122-preview";
const materialLoads = new Map();
const initialMaterialImage = $("#material-image");
let materialRequest = 0;
let materialLoading = false;
let materialFailed = false;

const materialDescriptions = {
    zh: ["悬停显现，1.1–4.0 倍放大。", "极光主题。让光线，流过每一面。", "移开指针，回到安静的玻璃轮廓。"],
    en: ["Reveal on hover. Enlarge from 1.1–4.0×.", "Aurora. A little light on every face.", "Move away. Return to a quiet glass silhouette."]
};

const materialAlt = {
    zh: ["通透玻璃主题，显示快捷图标", "极光流动主题的原生立方体", "隐藏图标的静置玻璃立方体"],
    en: ["Native glass cube with shortcut icons", "Native cube with the Aurora theme", "Resting glass cube with hidden icons"]
};

function translate(key) {
    if (key === "announcement") {
        return language === "zh"
            ? `✦ T-Cube v${latestVersion} 已发布 · 适用于 macOS 与 Windows`
            : `✦ T-Cube v${latestVersion} is live · For macOS & Windows`;
    }
    return translations[key]?.[language] ?? "";
}

function updateTabIndicator() {
    const activeTab = $('.material-tabs button[aria-selected="true"]');
    const indicator = $(".material-tabs .tab-indicator");
    if (!activeTab || !indicator) return;
    indicator.style.width = `${activeTab.offsetWidth}px`;
    indicator.style.transform = `translateX(${activeTab.offsetLeft}px)`;
}

function applyLanguage(next) {
    language = next === "en" ? "en" : "zh";
    document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
    document.body.classList.toggle("language-en", language === "en");

    $$("[data-i18n]").forEach(element => {
        const text = translate(element.dataset.i18n);
        if (text) element.textContent = text;
    });

    $$("[data-i18n-alt]").forEach(element => {
        const alt = translate(element.dataset.i18nAlt);
        if (alt) element.alt = alt;
    });

    const control = $("[data-language]");
    if (control) {
        const span = $("span", control);
        if (span) span.textContent = language === "zh" ? "EN" : "中文";
        control.setAttribute("aria-label", language === "zh" ? "Switch to English" : "切换为中文");
    }

    document.title = language === "zh" ? "T-Cube — 3D 桌面启动器" : "T-Cube — 3D Desktop Launcher";
    const description = language === "zh"
        ? "T-Cube 是一款适用于 macOS 和 Windows 的透明 3D 桌面启动器。六面快捷入口、剪贴板、常用内容、显示器控制，尽在一个立方体。"
        : "T-Cube is a transparent 3D desktop launcher for macOS and Windows. Six-face shortcuts, clipboard history, reusable content and display controls in one cube.";

    const metaDesc = $('meta[name="description"]');
    if (metaDesc) metaDesc.content = description;

    const guideLink = $("[data-guide-link]");
    if (guideLink) {
        guideLink.href = "https://github.com/gd0306/t-cube/blob/master/" + (language === "zh" ? "README-CN.md" : "README.md");
    }

    $$(".image-button").forEach(button => {
        const img = $("img", button);
        button.setAttribute("aria-label", (language === "zh" ? "查看大图：" : "Enlarge: ") + (img?.alt || ""));
    });

    updateThemeLabels();
    updateMaterialCopy();
    showReleaseStatus();
    requestAnimationFrame(() => {
        updateTabIndicator();
        updateThemeIndicator();
    });

    try {
        localStorage.setItem("tcube-language", language);
    } catch (_) {}
}

function updateMaterialCopy() {
    const captionEl = $("#material-caption");
    if (captionEl) {
        captionEl.textContent = materialLoading
            ? (language === "zh" ? "正在加载预览…" : "Loading preview…")
            : materialFailed
                ? (language === "zh" ? "预览加载失败，请再次选择重试。" : "Preview could not load. Select a tab to retry.")
                : materialDescriptions[language][selectedMaterial];
    }
    const imgEl = $("#material-image");
    if (imgEl) {
        imgEl.alt = materialAlt[language][selectedMaterial];
    }
}

function loadMaterial(index) {
    if (materialLoads.has(index)) return materialLoads.get(index);
    const image = index === 0 ? initialMaterialImage : new Image(1120, 840);
    image.decoding = "async";
    image.className = "hero-cube";
    const source = new URL("assets/" + materialImages[index] + "?v=" + materialVersion, document.baseURI).href;
    if (image.src !== source) image.src = source;
    const loading = image.decode().then(() => image).catch(error => {
        materialLoads.delete(index);
        throw error;
    });
    materialLoads.set(index, loading);
    return loading;
}

function selectMaterial(index, moveFocus = false, emitPulse = false) {
    const request = ++materialRequest;
    const preview = $("#material-preview");
    const heroArt = $(".hero-art");
    if (!preview) return;
    if (moveFocus) $(`[data-material="${index}"]`)?.focus();
    materialLoading = true;
    materialFailed = false;
    preview.setAttribute("aria-busy", "true");
    updateMaterialCopy();

    return loadMaterial(index).then(image => {
        if (request !== materialRequest) return;
        selectedMaterial = index;
        image.id = "material-image";
        preview.replaceChildren(image);
        $$("[data-material]").forEach((button, i) => {
            button.setAttribute("aria-selected", String(index === i));
            button.tabIndex = index === i ? 0 : -1;
        });
        if (heroArt) heroArt.dataset.activeMaterial = String(index);
        preview.setAttribute("aria-labelledby", "material-tab-" + index);
        materialLoading = false;
        preview.setAttribute("aria-busy", "false");
        updateMaterialCopy();
        updateTabIndicator();
        if (emitPulse && typeof triggerFieldPulse === "function") {
            triggerFieldPulse(index === 1 ? "aurora" : "default");
        }
    }).catch(() => {
        if (request !== materialRequest) return;
        materialLoading = false;
        materialFailed = true;
        preview.setAttribute("aria-busy", "false");
        updateMaterialCopy();
    });
}

$$("[data-material]").forEach((button, index) => {
    button.addEventListener("click", () => selectMaterial(index, false, true));
    button.addEventListener("keydown", event => {
        let next;
        if (event.key === "ArrowRight") next = (index + 1) % 3;
        if (event.key === "ArrowLeft") next = (index + 2) % 3;
        if (event.key === "Home") next = 0;
        if (event.key === "End") next = 2;
        if (next !== undefined) {
            event.preventDefault();
            selectMaterial(next, true, true);
        }
    });
});

const langToggle = $("[data-language]");
if (langToggle) {
    langToggle.addEventListener("click", () => applyLanguage(language === "zh" ? "en" : "zh"));
}

try {
    if (localStorage.getItem("tcube-language") === "en") language = "en";
} catch (_) {}

applyLanguage(language);
selectMaterial(0);
materialImages.forEach((_, index) => loadMaterial(index).catch(() => {}));
window.addEventListener("resize", () => requestAnimationFrame(() => {
    updateTabIndicator();
    updateThemeIndicator();
}), { passive: true });
document.fonts?.ready?.then(() => requestAnimationFrame(() => {
    updateTabIndicator();
    updateThemeIndicator();
}));

/* Media Zoom and Motion Dialog */
const dialog = $(".media-dialog");
let dialogOpener = null;

function openMedia(src, caption) {
    if (!dialog) return;
    if (typeof dialog.showModal !== "function") {
        window.open(src, "_blank", "noopener");
        return;
    }
    const image = document.createElement("img");
    image.src = src;
    image.alt = caption;
    $(".dialog-body", dialog).replaceChildren(image);
    $(".dialog-caption", dialog).textContent = caption;
    dialogOpener = document.activeElement;
    dialog.showModal();
    $("[data-close]", dialog)?.focus();
}

$$("[data-zoom]").forEach(button => button.addEventListener("click", () => {
    const image = $("img", button);
    if (image) openMedia(image.currentSrc || image.src, image.alt);
}));

$("[data-motion]")?.addEventListener("click", () => {
    openMedia("assets/mac-edge-dock.gif", language === "zh" ? "macOS 原生贴边吸附与恢复动效" : "Native macOS edge docking and reveal");
});

$("[data-close]")?.addEventListener("click", () => dialog?.close());

if (dialog) {
    dialog.addEventListener("click", event => {
        if (event.target === dialog) {
            const r = dialog.getBoundingClientRect();
            if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) {
                dialog.close();
            }
        }
    });
    dialog.addEventListener("close", () => {
        $(".dialog-body", dialog).replaceChildren();
        dialogOpener?.focus();
    });
}

/* Smooth Inertia 3D Parallax Tilt on Hero Cube */
(() => {
    const art = $(".hero-art");
    if (!art || prefersReducedMotion || !window.matchMedia("(hover: hover)").matches) return;

    let targetX = 0;
    let targetY = 0;
    let currentX = 0;
    let currentY = 0;
    let rafId = null;

    function tick() {
        currentX += (targetX - currentX) * 0.1;
        currentY += (targetY - currentY) * 0.1;
        art.style.setProperty("--tilt-x", currentX.toFixed(3) + "deg");
        art.style.setProperty("--tilt-y", currentY.toFixed(3) + "deg");

        if (Math.abs(targetX - currentX) > 0.015 || Math.abs(targetY - currentY) > 0.015) {
            rafId = requestAnimationFrame(tick);
        } else {
            rafId = null;
        }
    }

    function ensureTick() {
        if (!rafId) rafId = requestAnimationFrame(tick);
    }

    art.addEventListener("pointermove", event => {
        const r = art.getBoundingClientRect();
        targetX = ((event.clientX - r.left) / r.width - 0.5) * 9;
        targetY = -((event.clientY - r.top) / r.height - 0.5) * 7;
        ensureTick();
    }, { passive: true });

    art.addEventListener("pointerleave", () => {
        targetX = 0;
        targetY = 0;
        ensureTick();
    });
})();

/* Cursor Spotlight Borders across Bento / Gesture / Download Cards */
(() => {
    if (prefersReducedMotion || !window.matchMedia("(hover: hover)").matches) return;

    const cards = $$(".bento-card, .gesture-card, .download-platform");
    let pendingEvent = null;
    let scheduled = false;

    function updateSpotlight() {
        scheduled = false;
        if (!pendingEvent) return;
        const { clientX, clientY } = pendingEvent;
        for (const card of cards) {
            const rect = card.getBoundingClientRect();
            if (
                clientX >= rect.left - 120 &&
                clientX <= rect.right + 120 &&
                clientY >= rect.top - 120 &&
                clientY <= rect.bottom + 120
            ) {
                card.style.setProperty("--mouse-x", `${clientX - rect.left}px`);
                card.style.setProperty("--mouse-y", `${clientY - rect.top}px`);
            }
        }
    }

    window.addEventListener("pointermove", event => {
        pendingEvent = event;
        if (!scheduled) {
            scheduled = true;
            requestAnimationFrame(updateSpotlight);
        }
    }, { passive: true });
})();

/* Scroll Choreography: Header State, Progress Hairline, Active Nav & Section Reveals */
(() => {
    const header = $(".site-header");
    const navLinks = $$(".nav-inner nav a");
    const sections = ["#experience", "#workflow", "#details", "#download"]
        .map(id => $(id))
        .filter(Boolean);

    function syncScroll() {
        const y = window.scrollY;
        const maxScroll = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
        const progress = Math.min(1, Math.max(0, y / maxScroll));

        if (header) {
            header.classList.toggle("is-scrolled", y > 24);
            header.style.setProperty("--scroll-progress", progress.toFixed(4));
        }

        let currentId = "";
        for (const section of sections) {
            const rect = section.getBoundingClientRect();
            if (rect.top <= window.innerHeight * 0.42) {
                currentId = "#" + section.id;
            }
        }
        navLinks.forEach(link => {
            link.classList.toggle("is-active", link.getAttribute("href") === currentId);
        });
    }

    let scrollRaf = false;
    window.addEventListener("scroll", () => {
        if (!scrollRaf) {
            scrollRaf = true;
            requestAnimationFrame(() => {
                scrollRaf = false;
                syncScroll();
            });
        }
    }, { passive: true });
    syncScroll();

    const revealItems = $$(".reveal-item");
    if (prefersReducedMotion || !("IntersectionObserver" in window)) {
        revealItems.forEach(el => el.classList.add("is-revealed"));
        return;
    }

    const observer = new IntersectionObserver(entries => {
        let batchIndex = 0;
        entries.forEach(entry => {
            if (!entry.isIntersecting) return;
            const el = entry.target;
            const delay = Math.min(batchIndex * 55, 220);
            el.style.transitionDelay = `${delay}ms`;
            el.classList.add("is-revealed");
            batchIndex++;
            observer.unobserve(el);
        });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.06 });

    revealItems.forEach(el => observer.observe(el));
})();

/* Dynamic Release Metadata */
function showReleaseStatus() {
    const el = $("[data-release-status]");
    if (el) {
        el.textContent = releaseState === "unavailable"
            ? (language === "zh" ? "暂时无法刷新版本；可到发布页核对最新下载。" : "Version refresh is unavailable. Check the release page for the newest download.")
            : "";
    }
}

function validAsset(asset) {
    try {
        const url = new URL(asset.url);
        return url.origin === "https://github.com" &&
               url.pathname.startsWith("/gd0306/t-cube/releases/download/") &&
               typeof asset.size === "number" &&
               asset.size > 0;
    } catch (_) {
        return false;
    }
}

function applyRelease(data) {
    if (!data || !/^\d+\.\d+\.\d+$/.test(data.version) || !Array.isArray(data.assets)) throw new Error("Invalid release data");
    const mac = data.assets.find(a => a.name?.endsWith("-macos-arm64.dmg") && validAsset(a));
    const windows = data.assets.find(a => a.name?.endsWith("-windows-x64-setup.exe") && validAsset(a));
    const sums = data.assets.find(a => a.name === "SHA256SUMS.txt" && validAsset(a));
    if (!mac || !windows || !sums) throw new Error("Incomplete release");

    latestVersion = data.version;
    for (const [platform, asset] of [["macos", mac], ["windows", windows]]) {
        $$(`[data-download="${platform}"]`).forEach(link => link.href = asset.url);
        const sizeEl = $(`[data-size="${platform}"]`);
        if (sizeEl) sizeEl.textContent = (asset.size / 1048576).toFixed(1) + " MB";
    }
    $$("[data-version]").forEach(el => el.textContent = "v" + data.version);
    const announcementEl = $('[data-i18n="announcement"]');
    if (announcementEl) announcementEl.textContent = translate("announcement");

    const checksumLink = $("[data-checksums]");
    if (checksumLink) checksumLink.href = sums.url;
    releaseState = "current";
    showReleaseStatus();
}

fetch("release.json", { cache: "no-cache" })
    .then(res => { if (!res.ok) throw new Error("Fetch failed"); return res.json(); })
    .then(applyRelease)
    .catch(() => { releaseState = "unavailable"; showReleaseStatus(); });

/* Antigravity Gravitational Ring & Poisson-Disk Micro-Capsule Field (Dark + Antigravity Light Palettes) */
(() => {
    if (prefersReducedMotion) return;

    function poissonDiskSample(width, height, minDist, maxSamples) {
        const cellSize = minDist / Math.SQRT2;
        const gridW = Math.max(1, Math.ceil(width / cellSize));
        const gridH = Math.max(1, Math.ceil(height / cellSize));
        const grid = new Int32Array(gridW * gridH).fill(-1);
        const points = [];
        const active = [];

        function addPoint(x, y) {
            const idx = points.length;
            points.push({
                bx: x,
                by: y,
                seed: Math.random() * Math.PI * 2,
                sizeBias: 0.78 + Math.random() * 0.45
            });
            active.push(idx);
            const gx = Math.floor(x / cellSize);
            const gy = Math.floor(y / cellSize);
            if (gx >= 0 && gx < gridW && gy >= 0 && gy < gridH) {
                grid[gy * gridW + gx] = idx;
            }
        }

        addPoint(width * 0.5, height * 0.5);

        while (active.length > 0 && points.length < maxSamples) {
            const randIdx = Math.floor(Math.random() * active.length);
            const p = points[active[randIdx]];
            let found = false;

            for (let k = 0; k < 18; k++) {
                const angle = Math.random() * Math.PI * 2;
                const dist = minDist * (1 + Math.random());
                const nx = p.bx + Math.cos(angle) * dist;
                const ny = p.by + Math.sin(angle) * dist;

                if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

                const gx = Math.floor(nx / cellSize);
                const gy = Math.floor(ny / cellSize);
                let ok = true;

                for (let oy = -2; oy <= 2 && ok; oy++) {
                    const cy = gy + oy;
                    if (cy < 0 || cy >= gridH) continue;
                    for (let ox = -2; ox <= 2; ox++) {
                        const cx = gx + ox;
                        if (cx < 0 || cx >= gridW) continue;
                        const neighborIdx = grid[cy * gridW + cx];
                        if (neighborIdx !== -1) {
                            const np = points[neighborIdx];
                            const dx = np.bx - nx;
                            const dy = np.by - ny;
                            if (dx * dx + dy * dy < minDist * minDist) {
                                ok = false;
                                break;
                            }
                        }
                    }
                }

                if (ok) {
                    addPoint(nx, ny);
                    found = true;
                    break;
                }
            }

            if (!found) {
                active.splice(randIdx, 1);
            }
        }

        return points;
    }

    function createAntigravityField(canvas, options) {
        if (!canvas) return null;
        const ctx = canvas.getContext("2d", { alpha: true });
        if (!ctx) return null;

        let width = 0;
        let height = 0;
        let points = [];
        let isRunning = false;
        let isVisible = true;
        let rafId = null;
        let startTime = performance.now();
        let lastFrame = startTime;

        const ring = { x: options.baseX, y: options.baseY, tx: options.baseX, ty: options.baseY };
        const pointer = { active: false, nx: options.baseX, ny: options.baseY };
        let pulse = { active: false, start: 0, mode: "default" };

        function rebuildPoints() {
            const isMobile = width < 680;
            const minDist = isMobile ? options.mobileSpacing : options.desktopSpacing;
            const maxCount = isMobile ? options.mobileCap : options.desktopCap;
            points = poissonDiskSample(width, height, minDist, maxCount);
        }

        function resize() {
            const dpr = Math.min(window.devicePixelRatio || 1, 2);
            const rect = canvas.getBoundingClientRect();
            if (!rect.width || !rect.height) return;
            width = rect.width;
            height = rect.height;
            canvas.width = Math.round(width * dpr);
            canvas.height = Math.round(height * dpr);
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            rebuildPoints();
        }

        function triggerPulse(mode = "default") {
            pulse = { active: true, start: performance.now(), mode };
        }

        function smoothstep(edge0, edge1, x) {
            const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
            return t * t * (3 - 2 * t);
        }

        function drawFrame(now) {
            if (!isRunning) return;

            const isLight = resolvedTheme === "light";
            const elapsed = (now - startTime) * 0.001;
            const dt = Math.min(0.05, (now - lastFrame) * 0.001);
            lastFrame = now;

            const idleX = options.baseX + Math.sin(elapsed * 0.38) * 0.12 + Math.cos(elapsed * 0.19) * 0.05;
            const idleY = options.baseY + Math.cos(elapsed * 0.31) * 0.10 + Math.sin(elapsed * 0.23) * 0.04;

            ring.tx = pointer.active ? pointer.nx : idleX;
            ring.ty = pointer.active ? pointer.ny : idleY;

            const followRate = 1 - Math.exp(-(pointer.active ? 5.2 : 2.1) * dt);
            ring.x += (ring.tx - ring.x) * followRate;
            ring.y += (ring.ty - ring.y) * followRate;

            const cx = ring.x * width;
            const cy = ring.y * height;
            const minDim = Math.min(width, height);
            const ringRadius = minDim * (options.ringRadiusRatio + Math.sin(elapsed * 0.85) * 0.025);
            const ringWidth = minDim * options.ringWidthRatio;

            let shockRadius = -1;
            let shockAlpha = 0;
            if (pulse.active) {
                const age = (now - pulse.start) * 0.001;
                if (age > 1.35) {
                    pulse.active = false;
                } else {
                    shockRadius = age * Math.max(width, height) * 0.72;
                    shockAlpha = (1 - age / 1.35);
                }
            }

            ctx.clearRect(0, 0, width, height);

            const baseOpacity = isLight ? options.baseOpacity * 0.78 : options.baseOpacity;

            for (let i = 0; i < points.length; i++) {
                const p = points[i];

                const driftX = Math.sin(elapsed * 0.7 + p.seed) * 4.5;
                const driftY = Math.cos(elapsed * 0.62 + p.seed * 1.3) * 4.5;
                const px = p.bx + driftX;
                const py = p.by + driftY;

                const dx = px - cx;
                const dy = py - cy;
                const dist = Math.hypot(dx, dy) || 0.0001;
                const dirX = dx / dist;
                const dirY = dy / dist;

                const angle = Math.atan2(dy, dx);
                const wobble =
                    Math.sin(angle * 3 + elapsed * 1.15) * (ringWidth * 0.28) +
                    Math.cos(angle * 5 - elapsed * 0.85) * (ringWidth * 0.16);
                const effDist = dist + wobble;

                const bandOuter = smoothstep(ringRadius - ringWidth * 1.4, ringRadius, effDist) -
                                  smoothstep(ringRadius, ringRadius + ringWidth * 1.1, effDist);
                const bandCore = smoothstep(ringRadius - ringWidth * 0.45, ringRadius, effDist) -
                                 smoothstep(ringRadius, ringRadius + ringWidth * 0.45, effDist);
                const band = Math.max(0, bandOuter * 0.85 + bandCore * 1.15);

                let shockBoost = 0;
                if (pulse.active) {
                    const sd = Math.abs(dist - shockRadius);
                    if (sd < 90) {
                        shockBoost = (1 - sd / 90) * shockAlpha;
                    }
                }

                const energy = Math.min(1, band + shockBoost * 0.9);
                const disp = energy * (minDim * 0.022);
                const tangX = -dirY;
                const tangY = dirX;
                const drawX = px + dirX * disp + tangX * energy * 4;
                const drawY = py + dirY * disp + tangY * energy * 4;

                const len = (1.5 + energy * 7.2) * p.sizeBias;
                const thickness = (1.2 + energy * 1.45) * p.sizeBias;
                const alpha = Math.min(0.95, baseOpacity + energy * (isLight ? 0.76 : 0.68));

                let r, g, b;
                if (isLight) {
                    // Antigravity light spectrum: cobalt (#2c64ed) on one arc, warm coral/gold (#f84242 -> #f59e0b) on the opposite arc
                    const warmMix = Math.cos(angle + Math.PI * 0.82 - elapsed * 0.22) * 0.5 + 0.5;
                    if (pulse.active && pulse.mode === "aurora" && shockBoost > 0.2) {
                        r = 16; g = 185; b = 129;
                    } else if (energy > 0.16) {
                        if (warmMix > 0.55) {
                            const goldMix = (warmMix - 0.55) / 0.45;
                            r = Math.round(248 - goldMix * 3);
                            g = Math.round(66 + goldMix * 130);
                            b = Math.round(66 - goldMix * 56);
                        } else {
                            r = 44;
                            g = Math.round(100 + warmMix * 30);
                            b = 237;
                        }
                    } else {
                        r = 88;
                        g = 96;
                        b = 114;
                    }
                } else {
                    const directional = Math.cos(angle - elapsed * 0.5) * 0.5 + 0.5;
                    if (pulse.active && pulse.mode === "aurora" && shockBoost > 0.2) {
                        r = 95; g = 232; b = 200;
                    } else if (energy > 0.52) {
                        r = Math.round(56 + directional * 57);
                        g = Math.round(137 + directional * 52);
                        b = 250;
                    } else if (energy > 0.14) {
                        r = Math.round(48 + directional * 65);
                        g = Math.round(116 + directional * 21);
                        b = 255;
                    } else {
                        r = 128;
                        g = 148;
                        b = 186;
                    }
                }

                ctx.save();
                ctx.translate(drawX, drawY);
                ctx.rotate(angle + Math.PI * 0.5 * (0.25 + energy * 0.25));
                ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha.toFixed(3)})`;
                ctx.beginPath();
                if (typeof ctx.roundRect === "function") {
                    ctx.roundRect(-len * 0.5, -thickness * 0.5, len, thickness, thickness * 0.5);
                } else {
                    ctx.rect(-len * 0.5, -thickness * 0.5, len, thickness);
                }
                ctx.fill();
                ctx.restore();
            }

            rafId = requestAnimationFrame(drawFrame);
        }

        function start() {
            if (isRunning || !isVisible || document.hidden) return;
            isRunning = true;
            lastFrame = performance.now();
            rafId = requestAnimationFrame(drawFrame);
        }

        function stop() {
            isRunning = false;
            if (rafId) {
                cancelAnimationFrame(rafId);
                rafId = null;
            }
        }

        const container = canvas.parentElement || canvas;
        window.addEventListener("pointermove", event => {
            const rect = canvas.getBoundingClientRect();
            if (
                event.clientX >= rect.left &&
                event.clientX <= rect.right &&
                event.clientY >= rect.top &&
                event.clientY <= rect.bottom
            ) {
                pointer.nx = (event.clientX - rect.left) / Math.max(1, rect.width);
                pointer.ny = (event.clientY - rect.top) / Math.max(1, rect.height);
                pointer.active = true;
            } else {
                pointer.active = false;
            }
        }, { passive: true });

        window.addEventListener("pointerleave", () => {
            pointer.active = false;
        });

        container.addEventListener("click", event => {
            if (event.target.closest("a, button")) return;
            const rect = canvas.getBoundingClientRect();
            pointer.nx = (event.clientX - rect.left) / Math.max(1, rect.width);
            pointer.ny = (event.clientY - rect.top) / Math.max(1, rect.height);
            triggerPulse();
        });

        window.addEventListener("resize", resize, { passive: true });

        if ("IntersectionObserver" in window) {
            new IntersectionObserver(entries => {
                isVisible = entries[0].isIntersecting;
                if (isVisible && !document.hidden) start();
                else stop();
            }, { threshold: 0.01 }).observe(canvas);
        }

        document.addEventListener("visibilitychange", () => {
            if (document.hidden) stop();
            else start();
        });

        resize();
        start();

        return { triggerPulse };
    }

    const heroField = createAntigravityField(document.getElementById("gravity-canvas"), {
        baseX: 0.69,
        baseY: 0.48,
        ringRadiusRatio: 0.34,
        ringWidthRatio: 0.16,
        baseOpacity: 0.14,
        desktopSpacing: 34,
        desktopCap: 1200,
        mobileSpacing: 44,
        mobileCap: 380
    });

    createAntigravityField(document.getElementById("download-canvas"), {
        baseX: 0.5,
        baseY: 0.5,
        ringRadiusRatio: 0.38,
        ringWidthRatio: 0.18,
        baseOpacity: 0.09,
        desktopSpacing: 44,
        desktopCap: 550,
        mobileSpacing: 52,
        mobileCap: 220
    });

    if (heroField) {
        triggerFieldPulse = mode => heroField.triggerPulse(mode);
    }
})();

// Pause CSS idle effects when hero is offscreen or tab hidden
(() => {
    const stage = $(".hero-shell");
    if (!stage) return;
    let visible = true;
    const synchronize = () => stage.classList.toggle("effects-paused", !visible || document.hidden);
    if ("IntersectionObserver" in window) {
        new IntersectionObserver(entries => {
            visible = entries[0].isIntersecting;
            synchronize();
        }).observe(stage);
    }
    document.addEventListener("visibilitychange", synchronize);
    synchronize();
})();
