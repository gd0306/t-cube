import AppKit
import CubeCore

@MainActor final class DisplayInputMenuRow: NSView {
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let left = NSTextField(labelWithString: "Type-C")
    private let right = NSTextField(labelWithString: "HDMI")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let setup = NSButton(title: "设置…", target: nil, action: nil)
    private let refresh = NSButton(title: "刷新", target: nil, action: nil)
    private var row: DisplayInputRow
    private let change: (String, DisplayInputSource) -> Void
    private let configure: (DisplayInputRow) -> Void
    private let reload: () -> Void
    init(row: DisplayInputRow, change: @escaping (String, DisplayInputSource) -> Void, configure: @escaping (DisplayInputRow) -> Void, reload: @escaping () -> Void) {
        self.row = row; self.change = change; self.configure = configure; self.reload = reload
        super.init(frame: CGRect(x: 0, y: 0, width: 288, height: 92))
        name.font = .systemFont(ofSize: 12, weight: .medium); name.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        left.font = .systemFont(ofSize: 10); right.font = .systemFont(ofSize: 10); right.alignment = .right
        slider.controlSize = .small; slider.numberOfTickMarks = 2; slider.allowsTickMarkValuesOnly = true; slider.isContinuous = false
        slider.target = self; slider.action = #selector(changed)
        setup.bezelStyle = .inline; setup.controlSize = .small; setup.target = self; setup.action = #selector(openSetup)
        refresh.bezelStyle = .inline; refresh.controlSize = .small; refresh.target = self; refresh.action = #selector(doRefresh)
        [name, detail, left, right, slider, setup, refresh].forEach(addSubview); apply(row)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        name.frame = NSRect(x: 16, y: 69, width: 160, height: 17)
        setup.frame = NSRect(x: 224, y: 67, width: 50, height: 20)
        refresh.frame = NSRect(x: 178, y: 67, width: 42, height: 20)
        left.frame = NSRect(x: 16, y: 41, width: 47, height: 15)
        right.frame = NSRect(x: 226, y: 41, width: 47, height: 15)
        slider.frame = NSRect(x: 68, y: 37, width: 151, height: 23)
        detail.frame = NSRect(x: 16, y: 10, width: 258, height: 18)
    }
    func apply(_ row: DisplayInputRow) {
        self.row = row; name.stringValue = row.target.name; name.toolTip = row.target.name
        slider.isEnabled = row.enabled
        if let current = row.current, let source = row.mapping?.source(for: current) { slider.doubleValue = source == .typeC ? 0 : 1 }
        let activeSource = row.current.flatMap { row.mapping?.source(for: $0) }
        let currentText = activeSource.map { $0 == .typeC ? "当前：Type-C" : "当前：HDMI" } ?? row.current.map { "当前输入代码：\($0)" } ?? "不可用"
        detail.stringValue = row.message ?? (row.busy ? "正在读取…" : currentText)
        detail.toolTip = detail.stringValue; setup.isEnabled = !row.busy; refresh.isEnabled = !row.busy
        slider.setAccessibilityLabel("\(row.target.name) 输入源")
        let source = row.current.flatMap { row.mapping?.source(for: $0) }.map { $0 == .typeC ? "Type-C" : "HDMI" } ?? "未知"
        slider.setAccessibilityHelp("当前输入：\(source)。\(detail.stringValue)")
    }
    @objc private func changed() { if slider.isEnabled { change(row.id, slider.doubleValue < 0.5 ? .typeC : .hdmi) } }
    @objc private func openSetup() {
        let selected = row
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { [configure] in configure(selected) }
    }
    @objc private func doRefresh() { reload() }
}

@MainActor final class DisplayInputMenu {
    let controller: DisplayInputController
    private weak var menu: NSMenu?
    private var items: [NSMenuItem] = []
    private var views: [String: DisplayInputMenuRow] = [:]
    private var observer: NSObjectProtocol?
    init(menu: NSMenu) {
        self.menu = menu
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("T-Cube/display-inputs.json")
        controller = DisplayInputController(hardware: NativeDisplayInputHardware(), targets: DisplayBrightnessMenu.connectedDisplays, store: DisplayInputStore(url: base))
        controller.onChange = { [weak self] in self?.render() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.screenParametersChanged() }
        }
        render()
    }
    func beginTracking() { controller.beginTracking() }
    func endTracking() { controller.endTracking() }
    private func render() {
        guard let menu else { return }
        let rows = controller.rows
        if !rows.isEmpty, Set(views.keys) == Set(rows.map(\.id)) { for row in rows { views[row.id]?.apply(row) }; return }
        for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) }
        items.removeAll(); views.removeAll()
        let header = NSMenuItem(title: "显示器输入源", action: nil, keyEquivalent: ""); header.isEnabled = false; items.append(header)
        if rows.isEmpty {
            let empty = NSMenuItem(title: controller.isOpen ? "未检测到外接显示器" : "正在读取显示器…", action: nil, keyEquivalent: ""); empty.isEnabled = false; items.append(empty)
        }
        for row in rows {
            let item = NSMenuItem()
            let view = DisplayInputMenuRow(row: row, change: { [weak self] in self?.controller.setSource($1, for: $0) }, configure: { [weak self] in self?.configure($0) }, reload: { [weak self] in self?.controller.refresh() })
            item.view = view; items.append(item); views[row.id] = view
        }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
    }
    private func configure(_ row: DisplayInputRow) {
        let alert = NSAlert(); alert.messageText = "设置 \(row.target.name) 的输入代码"
        alert.informativeText = "当前输入代码：\(row.current.map(String.init) ?? "无法读取")。请填写两个不同的十进制代码（0–65535）。另一个代码可能需要在其连接的主机上读取。切回时请在当前显示画面的主机上操作，或使用显示器实体菜单。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "使用 27C1U-D 预设")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 60))
        let typeLabel = NSTextField(labelWithString: "Type-C") ; typeLabel.frame = NSRect(x: 0, y: 35, width: 80, height: 18)
        let hdmiLabel = NSTextField(labelWithString: "HDMI"); hdmiLabel.frame = NSRect(x: 0, y: 5, width: 80, height: 18)
        let type = NSTextField(string: row.mapping.map { String($0.typeC) } ?? ""); type.frame = NSRect(x: 85, y: 32, width: 150, height: 22)
        let hdmi = NSTextField(string: row.mapping.map { String($0.hdmi) } ?? ""); hdmi.frame = NSRect(x: 85, y: 2, width: 150, height: 22)
        [typeLabel, hdmiLabel, type, hdmi].forEach(container.addSubview); alert.accessoryView = container
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { type.stringValue = "7"; hdmi.stringValue = "5" }
        else if response != .alertFirstButtonReturn { return }
        guard let a = UInt16(type.stringValue), let b = UInt16(hdmi.stringValue), let mapping = DisplayInputMapping(typeC: a, hdmi: b) else {
            let error = NSAlert(); error.messageText = "输入代码无效"; error.informativeText = "请输入两个不同的 0–65535 整数。"; error.runModal(); return
        }
        do { try controller.save(mapping, for: row.id) }
        catch { let alert = NSAlert(error: error); alert.informativeText = "无法保存输入映射。请备份并修复 display-inputs.json 后重试。"; alert.runModal() }
    }
    func stop() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; controller.stop(); if let menu { for item in items where menu.index(of: item) >= 0 { menu.removeItem(item) } }; items.removeAll(); views.removeAll() }
}
