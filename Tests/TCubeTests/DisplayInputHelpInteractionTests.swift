import AppKit
import XCTest
import CubeCore
@testable import TCube

private final class HelpInteractionHardware: DisplayInputHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var writes: Int { lock.withLock { count } }
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 { 15 }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome {
        lock.withLock { count += 1 }; return .sentUnconfirmed
    }
}

@MainActor private final class HelpInteractionDriver: NSObject, NSMenuDelegate {
    let menu: NSMenu
    let feature: DisplayInputMenu
    let save: Bool
    let captures: URL?
    var finished = false
    var succeeded = false
    private var phase = 0
    var reachedPhase: Int { phase }
    private var menuTracking = false
    private var timers: [Timer] = []
    private var setup: NSWindow?
    private var fields: DisplayInputSetupView?
    private var events: [[String: Any]] = []

    init(menu: NSMenu, feature: DisplayInputMenu, save: Bool, captures: URL?) {
        self.menu = menu; self.feature = feature; self.save = save; self.captures = captures
    }
    func menuWillOpen(_ menu: NSMenu) { menuTracking = true; feature.beginTracking() }
    func menuDidClose(_ menu: NSMenu) { menuTracking = false; feature.endTracking() }
    func schedule(_ delay: TimeInterval = 0.35) {
        let timer = Timer(timeInterval: delay, repeats: false) { [self] _ in MainActor.assumeIsolated { step() } }
        timers.append(timer)
        for mode in phase == 0 ? [RunLoop.Mode.eventTracking] : [.default, .modalPanel] { RunLoop.main.add(timer, forMode: mode) }
    }
    func stopTimers() { timers.forEach { $0.invalidate() }; timers.removeAll() }
    private func wakeEventLoop() {
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
    }
    private func descendants(_ view: NSView?) -> [NSView] { guard let view else { return [] }; return [view] + view.subviews.flatMap { descendants($0) } }
    private func button(_ title: String, in window: NSWindow?) -> NSButton? { descendants(window?.contentView).compactMap { $0 as? NSButton }.first { $0.title == title } }
    private func capture(_ name: String, window: NSWindow?) {
        events.append(["step": name, "setupVisible": setup?.isVisible == true, "modalIsSetup": NSApp.modalWindow === setup, "activeWindowVisible": window?.isVisible == true, "activeWindowKey": window?.isKeyWindow == true])
        guard let captures, let window else { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), captures.appendingPathComponent("\(name).png").path]
        do { try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0) }
        catch { XCTFail("Interaction capture failed: \(error)") }
    }
    private func openHelp(next: Int) {
        guard let help = button("如何获取输入代码…", in: setup) else { XCTFail("Setup help button missing"); finish(); return }
        phase = next; schedule(0.55)
        help.performClick(nil)
    }
    private func closeHelp(next: Int) {
        guard let modal = NSApp.modalWindow, modal !== setup else {
            XCTFail("Help must become modal and visible while setup remains open")
            // The regression path must also observe and close any delayed alert.
            phase = 90; schedule(); NSApp.stopModal(withCode: .alertSecondButtonReturn); wakeEventLoop(); return
        }
        XCTAssertTrue(modal.isVisible && setup?.isVisible == true)
        XCTAssertTrue(modal.isKeyWindow, "Help must receive focus above setup")
        if phase == 2 { capture("help-visible", window: modal) }
        guard let close = button("知道了", in: modal) else { XCTFail("Help close button missing"); finish(); return }
        phase = next; schedule(); close.performClick(nil); wakeEventLoop()
    }
    private func verifyReturnedSetup() {
        XCTAssertTrue(NSApp.modalWindow === setup && setup?.isVisible == true)
        XCTAssertTrue(setup?.isKeyWindow == true, "Focus returns to the original setup")
        XCTAssertEqual(fields?.typeC.stringValue, "23")
        XCTAssertEqual(fields?.hdmi.stringValue, "24")
    }
    private func finish() {
        let needsEvent = menuTracking || NSApp.modalWindow != nil
        finished = true; menu.cancelTracking()
        if let captures, let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: captures.appendingPathComponent("events.json")) }
        if NSApp.modalWindow != nil { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
        if needsEvent { wakeEventLoop() }
    }
    private func step() {
        switch phase {
        case 0:
            guard let row = menu.items.compactMap({ $0.view as? DisplayInputMenuRow }).first,
                  let settings = row.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "设置…" && $0.isEnabled }) else { XCTFail("Ready menu setup missing"); finish(); return }
            phase = 1; schedule(); NSApp.sendAction(settings.action!, to: settings.target, from: settings)
            menu.cancelTracking()
            wakeEventLoop()
        case 1:
            setup = NSApp.modalWindow
            fields = descendants(setup?.contentView).compactMap { $0 as? DisplayInputSetupView }.first
            guard let fields else { XCTFail("Real setup alert did not open"); finish(); return }
            fields.typeC.stringValue = "23"; fields.hdmi.stringValue = "24"
            capture("setup-before", window: setup)
            openHelp(next: 2)
        case 2: closeHelp(next: 3)
        case 3: verifyReturnedSetup(); capture("setup-return", window: setup); openHelp(next: 4)
        case 4: closeHelp(next: 5)
        case 5:
            verifyReturnedSetup()
            guard let end = button(save ? "保存" : "取消", in: setup) else { XCTFail("Setup completion button missing"); finish(); return }
            phase = 6; schedule(); end.performClick(nil); wakeEventLoop()
        case 6:
            XCTAssertNil(NSApp.modalWindow, "No delayed help should remain after closing setup")
            phase = 7; schedule()
        case 7:
            XCTAssertNil(NSApp.modalWindow, "Repeated help must not accumulate queued alerts")
            succeeded = true; finish()
        case 90:
            if let modal = NSApp.modalWindow, modal !== setup {
                XCTFail("Queued help appeared only after setup closed")
                phase = 91; schedule(); button("知道了", in: modal)?.performClick(nil); wakeEventLoop()
            } else { finish() }
        default: finish()
        }
    }
}

@MainActor final class DisplayInputHelpInteractionTests: XCTestCase {
    func testHelpAppearsInsideSetupAndCancelPreservesStoredMapping() throws { try exercise(save: false) }
    func testRepeatedHelpReturnsToUnsavedValuesAndSavePersistsThem() throws { try exercise(save: true) }
    private func exercise(save: Bool) throws {
        _ = NSApplication.shared
        if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let hardware = HelpInteractionHardware()
        let target = DisplayBrightnessTarget(id: 2, uuid: UUID().uuidString, name: "帮助交互示例", isBuiltIn: false)
        let store = DisplayInputStore(url: temporary.appendingPathComponent("display-inputs.json"))
        try store.save(try XCTUnwrap(DisplayInputMapping(typeC: 15, hdmi: 17)), for: target.uuid)
        let controller = DisplayInputController(hardware: hardware, targets: { [target] }, store: store)
        let menu = NSMenu(), feature = DisplayInputMenu(menu: menu, controller: controller)
        let captures = ProcessInfo.processInfo.environment["TCUBE_HELP_INTERACTION_PREVIEWS"] == "1" && !save
            ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/display-input-help-interaction") : nil
        if let captures { try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true) }
        let driver = HelpInteractionDriver(menu: menu, feature: feature, save: save, captures: captures)
        menu.delegate = driver
        defer { driver.stopTimers(); feature.stop() }
        let window = NSPanel(contentRect: CGRect(x: 180, y: 180, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame)); window.makeKeyAndOrderFront(nil)
        // Model a foreground menu interaction, not a background CLI process.
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { window.orderOut(nil); window.contentView = nil }
        driver.schedule()
        menu.popUp(positioning: nil, at: CGPoint(x: 10, y: 100), in: window.contentView)
        let deadline = Date().addingTimeInterval(8)
        while !driver.finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(driver.finished && driver.succeeded, "Complete both help cycles and return to setup (phase \(driver.reachedPhase))")
        XCTAssertEqual(hardware.writes, 0, "Help, save and cancel must never switch the monitor")
        if driver.succeeded { XCTAssertEqual(try store.mapping(for: target.uuid), DisplayInputMapping(typeC: save ? 23 : 15, hdmi: save ? 24 : 17)) }
    }
}
