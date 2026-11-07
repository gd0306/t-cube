import AppKit
import Testing
import CubeCore
@testable import TCube

private final class InputPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor @Suite(.serialized) struct DisplayInputMenuTests {
    @Test func inputCodeHelpIsDiscoverableWithoutAUsableMonitor() {
        _ = NSApplication.shared
        let menu = NSMenu()
        let feature = DisplayInputMenu(menu: menu)
        defer { feature.stop() }
        let help = menu.items.first { $0.title == "如何获取输入代码…" }
        #expect(help?.isEnabled == true)
        #expect(help?.action != nil)
    }
    @Test func setupKeepsSavedCodesAndOffersWorkingHelpWithoutGuessingNewCodes() throws {
        _ = NSApplication.shared
        let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "Generic", isBuiltIn: false)
        var helpOpened = false
        let view = DisplayInputSetupView(row: .init(target: target, mapping: DisplayInputMapping(typeC: 15, hdmi: 17)), onHelp: { helpOpened = true })
        #expect(view.typeC.stringValue == "15" && view.hdmi.stringValue == "17")
        let help = try #require(view.subviews.compactMap { $0 as? NSButton }.first)
        #expect(help.isEnabled)
        NSApp.sendAction(try #require(help.action), to: help.target, from: help)
        #expect(helpOpened)
        let unconfigured = DisplayInputSetupView(row: .init(target: target), onHelp: {})
        #expect(unconfigured.typeC.stringValue.isEmpty && unconfigured.hdmi.stringValue.isEmpty)
    }
    @Test func readyAndUnknownRowsExposeControlsAndSource() throws {
        _ = NSApplication.shared
        let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "Example", isBuiltIn: false)
        let mapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
        let row = DisplayInputMenuRow(row: .init(target: target, mapping: mapping, current: 5, busy: false), change: { _, _ in }, configure: { _ in }, reload: {})
        let sourceSwitch = try #require(row.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        #expect(sourceSwitch.isEnabled && sourceSwitch.selectedSegment == 1)
        #expect(sourceSwitch.label(forSegment: 0) == "Type-C" && sourceSwitch.label(forSegment: 1) == "HDMI")
        #expect(sourceSwitch.accessibilityHelp()?.contains("HDMI") == true)
        #expect(row.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "当前：HDMI" })
        #expect(row.subviews.compactMap { $0 as? NSButton }.filter { !$0.isEnabled }.isEmpty)
        row.apply(.init(target: target, current: 16, busy: false))
        #expect(!sourceSwitch.isEnabled && sourceSwitch.selectedSegment == -1)
        #expect(row.subviews.compactMap { $0 as? NSButton }.filter { !$0.isEnabled }.isEmpty)
    }

    @Test func switchCommitsExplicitPortsAndKeepsOnlyConfirmedSelection() throws {
        _ = NSApplication.shared
        let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "Example", isBuiltIn: false)
        let mapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
        var requests: [DisplayInputSource] = []
        let row = DisplayInputMenuRow(row: .init(target: target, mapping: mapping, current: 5, busy: false),
            change: { id, source in #expect(id == target.uuid); requests.append(source) }, configure: { _ in }, reload: {})
        let control = try #require(row.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        func choose(_ segment: Int) {
            control.selectedSegment = segment
            NSApp.sendAction(control.action!, to: control.target, from: control)
        }
        choose(0)
        #expect(requests == [.typeC])
        #expect(control.selectedSegment == 1, "A click is a request, not hardware confirmation")
        row.apply(.init(target: target, mapping: mapping, current: 5, busy: true, message: "正在切换…"))
        choose(0)
        #expect(requests == [.typeC] && !control.isEnabled && control.selectedSegment == 1)
        row.apply(.init(target: target, mapping: mapping, current: 7, busy: false))
        #expect(control.selectedSegment == 0)
        choose(0)
        #expect(requests == [.typeC], "Selecting the current input must not write again")
        choose(1)
        #expect(requests == [.typeC, .hdmi])
        row.apply(.init(target: target, mapping: mapping, busy: false, message: "命令已发送，无法确认"))
        #expect(!control.isEnabled && control.selectedSegment == -1)
        choose(1)
        #expect(requests == [.typeC, .hdmi] && control.selectedSegment == -1)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_INPUT_PREVIEWS"] == "1"))
    func exportInputRows() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/display-input-previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 304, height: 405)); content.wantsLayer = true
            let window = InputPreviewPanel(contentRect: content.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = content
            window.appearance?.performAsCurrentDrawingAppearance { content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "示例显示器 A", isBuiltIn: false)
            let second = DisplayBrightnessTarget(id: 3, uuid: UUID().uuidString, name: "示例显示器 B", isBuiltIn: false)
            let rows = [DisplayInputRow(target: target, mapping: DisplayInputMapping(typeC: 15, hdmi: 17), current: 15, busy: false), DisplayInputRow(target: second, mapping: DisplayInputMapping(typeC: 16, hdmi: 18), current: 18, busy: false), DisplayInputRow(target: target, current: 16, busy: false, message: "当前输入代码 16；请设置映射"), DisplayInputRow(target: second, busy: false, message: "此连接不支持输入源 DDC/CI；请查看获取代码帮助")]
            for (index, state) in rows.enumerated() {
                let row = DisplayInputMenuRow(row: state, change: { _, _ in }, configure: { _ in }, reload: {})
                row.frame.origin = CGPoint(x: 8, y: 305 - 96 * index); content.addSubview(row)
            }
            window.makeKeyAndOrderFront(nil); NSApp.activate(); content.layoutSubtreeIfNeeded()
            defer { window.orderOut(nil); window.contentView = nil }
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("input-menu-\(name).png"))

            // Render the actual native alert factories; sample mappings never touch hardware or user data.
            let alerts = [("help", DisplayInputHelp.makeAlert()),
                          ("setup", DisplayInputSetupView.makeAlert(row: rows[0], onHelp: {}))]
            for (kind, alert) in alerts {
                alert.layout()
                alert.window.appearance = NSAppearance(named: appearance)
                alert.window.animationBehavior = .none
                let screenshot = Process()
                screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                let capture = Timer(timeInterval: 0.5, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        screenshot.arguments = ["-x", "-o", "-l", String(alert.window.windowNumber), folder.appendingPathComponent("input-\(kind)-\(name).png").path]
                        do { try screenshot.run(); screenshot.waitUntilExit() }
                        catch { Issue.record("Native alert capture failed: \(error)") }
                        NSApp.stopModal()
                    }
                }
                RunLoop.main.add(capture, forMode: .modalPanel)
                alert.runModal()
                #expect(screenshot.terminationStatus == 0)
                let captured = try #require(NSBitmapImageRep(data: Data(contentsOf: folder.appendingPathComponent("input-\(kind)-\(name).png"))))
                #expect(captured.pixelsWide >= Int(alert.window.frame.width), "Capture the settled window, not its opening animation")
                alert.window.orderOut(nil)
            }
        }
    }
}
