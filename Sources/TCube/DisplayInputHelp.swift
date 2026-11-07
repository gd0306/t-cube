import AppKit
import CubeCore

/// Calibration help opened from the per-display setup view.
@MainActor enum DisplayInputHelp {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "display", accessibilityDescription: "显示器")
        alert.messageText = "如何获取显示器输入代码"
        alert.informativeText = """
        输入代码由显示器固件决定。T-Cube 自动检测外接显示器并读取当前代码，不读取全部可用值。VCP 0x60 是功能编号，不是要填写的端口值。

        1. 在显示器实体菜单中开启 DDC/CI，连接 Type-C 与 HDMI 的两台主机，并保持主机唤醒。先确认显示器名称及 ID；同名时可暂时断开其他屏幕再刷新。

        2. 用显示器实体菜单选中 Type-C。在当前显示画面的主机上打开 T-Cube 输入源控制（macOS 状态栏 / Windows 托盘），刷新对应屏幕，再打开输入代码设置，记下当前十进制代码。

        3. 用实体菜单选中 HDMI。在 HDMI 连接的活动主机上打开 T-Cube 的显示器输入源控制并刷新，记下当前代码。不能只在已经失去画面的主机上反复读取。

        4. 回到需要配置的主机，在对应屏幕的输入代码设置中填写两个实测代码（0–65535，且不同），点击保存。每台主机分别保存；保存本身不会切换输入。

        5. 确认有实体菜单可切回，再点击 Type-C 或 HDMI 验证画面及回读。只有回读确认才高亮；「无法确认」可能表示画面已切走，请从当前活动主机或实体菜单切回。

        无法读取？先检查 DDC/CI、线缆和转接器，尝试直连后刷新。当前 macOS 外接输入控制仅支持 Apple Silicon；Intel Mac 暂不支持。部分扩展坞、转接器或显示器也可能不支持。未返回代码时不要猜值，使用实体菜单或咨询厂商。自动检测不代表硬件已验证兼容。
        """
        alert.addButton(withTitle: "知道了")
        let width = NSView(frame: NSRect(x: 0, y: 0, width: 470, height: 1))
        alert.accessoryView = width
        return alert
    }
}

@MainActor final class DisplayInputSetupView: NSView {
    let typeC: NSTextField
    let hdmi: NSTextField
    private let onHelp: () -> Void

    static func makeAlert(row: DisplayInputRow, onHelp: @escaping () -> Void) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "display", accessibilityDescription: "显示器")
        alert.messageText = "设置 \(row.target.name) 的输入代码"
        alert.informativeText = "显示器 ID：\(row.target.id)\n当前输入代码：\(row.current.map(String.init) ?? "无法读取")\n请填写两个实测、不同的十进制代码（0–65535）。保存不会切换输入；获取步骤见下方帮助。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.accessoryView = DisplayInputSetupView(row: row, onHelp: onHelp)
        return alert
    }

    init(row: DisplayInputRow, onHelp: @escaping () -> Void) {
        self.onHelp = onHelp
        typeC = NSTextField(string: row.mapping.map { String($0.typeC) } ?? "")
        hdmi = NSTextField(string: row.mapping.map { String($0.hdmi) } ?? "")
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
        let typeLabel = NSTextField(labelWithString: "Type-C 代码")
        let hdmiLabel = NSTextField(labelWithString: "HDMI 代码")
        typeLabel.frame = NSRect(x: 0, y: 72, width: 110, height: 18)
        hdmiLabel.frame = NSRect(x: 0, y: 42, width: 110, height: 18)
        typeC.frame = NSRect(x: 120, y: 69, width: 180, height: 22)
        hdmi.frame = NSRect(x: 120, y: 39, width: 180, height: 22)
        typeC.setAccessibilityLabel("Type-C 十进制输入代码")
        hdmi.setAccessibilityLabel("HDMI 十进制输入代码")
        let help = NSButton(title: "如何获取输入代码…", target: self, action: #selector(showHelp))
        help.bezelStyle = .rounded
        help.controlSize = .small
        help.frame = NSRect(x: 0, y: 2, width: 180, height: 25)
        [typeLabel, hdmiLabel, typeC, hdmi, help].forEach(addSubview)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func showHelp() { onHelp() }
}
