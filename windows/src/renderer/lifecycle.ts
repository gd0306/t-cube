import type { LifecycleBridge, LifecycleState } from '../shared/maintenance';
export function renderLifecycle(content: HTMLElement) {
    const bridge = window.tcube as unknown as LifecycleBridge;
    const root = document.createElement('section'), heading = document.createElement('h2'), status = document.createElement('p'), version = document.createElement('p');
    heading.textContent = '启动与更新'; root.append(heading, version);
    const login = document.createElement('input'), automatic = document.createElement('input'); login.type = automatic.type = 'checkbox';
    function row(text: string, input: HTMLInputElement) { const label = document.createElement('label'); label.className = 'row'; label.append(document.createTextNode(text), input); return label; }
    root.append(row('登录 Windows 时启动', login), row('自动检查已签名更新（默认关闭）', automatic), status);
    const check = document.createElement('button'), install = document.createElement('button'), release = document.createElement('button');
    for (const button of [check, install, release]) button.type = 'button';
    check.textContent = '检查更新'; install.textContent = '重启并安装更新'; release.textContent = '打开发布页面'; root.append(check, install, release); content.append(root);
    function show(state: LifecycleState) { login.checked = state.loginEnabled; login.disabled = !state.loginSupported; automatic.checked = state.automaticUpdates; automatic.disabled = !state.updatesEnabled; check.disabled = !state.updatesEnabled; install.disabled = !state.updateReady; status.textContent = state.status; version.textContent = `T-Cube ${state.version} · 检查、下载与安装均在主进程执行；下载与安装会单独确认。`; }
    function run(action: () => Promise<LifecycleState>) { for (const input of [login, automatic, check, install]) input.disabled = true; void action().then(show).catch(async error => { show(await bridge.getLifecycleState()); status.textContent = error instanceof Error ? error.message : String(error); }); }
    login.onchange = () => run(() => bridge.setLoginEnabled(login.checked)); automatic.onchange = () => run(() => bridge.setAutomaticUpdates(automatic.checked));
    check.onclick = () => run(() => bridge.checkForUpdates()); install.onclick = () => run(() => bridge.installUpdate()); release.onclick = () => { void bridge.openReleasePage().catch(error => { status.textContent = String(error); }); };
    run(() => bridge.getLifecycleState());
}
