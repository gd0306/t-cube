import AppKit
import XCTest
import Testing
import CubeCore
@testable import TCube

@MainActor
@Suite(.serialized)
struct DisplayBrightnessMenuTests {
    private let target = DisplayBrightnessTarget(id: 2, uuid: "external-unique", name: "27C1U-D", isBuiltIn: false)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_BRIGHTNESS_PREVIEWS"] == "1"))
    func exportNativeMenuRowsInBothAppearances() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/device-controls-research/previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 304, height: 254)); content.wantsLayer = true
            let window = NSPanel(contentRect: content.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = content
            window.appearance?.performAsCurrentDrawingAppearance { content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
            let heading = NSTextField(labelWithString: "显示器亮度"); heading.font = .systemFont(ofSize: 12, weight: .semibold)
            heading.frame = CGRect(x: 16, y: 226, width: 260, height: 18); content.addSubview(heading)
            let samples = [
                DisplayBrightnessRow(target: .init(id: 1, uuid: "built-in", name: "内建 Retina 显示器", isBuiltIn: true), sample: .init(fraction: 0.47, backend: .native), fraction: 0.47, isLoading: false),
                DisplayBrightnessRow(target: target, sample: .init(fraction: 0.37, backend: .ddc), fraction: 0.37, isLoading: false),
                DisplayBrightnessRow(target: .init(id: 3, uuid: "unsupported", name: "示例：不支持的连接", isBuiltIn: false), isLoading: false, message: DisplayBrightnessFailure.unsupported.message)
            ]
            for (index, state) in samples.enumerated() {
                let row = DisplayBrightnessMenuRow(state: state) { _, _ in }
                row.frame.origin = CGPoint(x: 8, y: 216 - 72 * (index + 1)); content.addSubview(row)
            }
            window.orderFrontRegardless(); content.layoutSubtreeIfNeeded()
            defer { window.orderOut(nil); window.contentView = nil }
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("brightness-menu-\(name).png"))
        }
    }

    @Test func nativeSliderRoutesTheRequestedValueToTheNamedScreen() throws {
        _ = NSApplication.shared
        var received: (String, Double)?
        let state = DisplayBrightnessRow(target: target, sample: .init(fraction: 0.37, backend: .ddc), fraction: 0.37, isLoading: false)
        let row = DisplayBrightnessMenuRow(state: state) { received = ($0, $1) }
        let slider = try #require(row.subviews.compactMap { $0 as? NSSlider }.first)
        #expect(slider.isEnabled && slider.doubleValue == 37)
        #expect(slider.accessibilityLabel()?.contains("27C1U-D") == true)
        #expect(row.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "37%" })
        slider.doubleValue = 82
        _ = slider.sendAction(slider.action, to: slider.target)
        #expect(received?.0 == "external-unique" && received?.1 == 0.82)
    }

    @Test func unavailableScreenRetainsItsNameAndReasonWithADisabledSlider() throws {
        _ = NSApplication.shared
        let state = DisplayBrightnessRow(target: target, isLoading: false, message: DisplayBrightnessFailure.unsupported.message)
        let row = DisplayBrightnessMenuRow(state: state) { _, _ in Issue.record("Disabled screen must not submit a value") }
        let slider = try #require(row.subviews.compactMap { $0 as? NSSlider }.first)
        #expect(!slider.isEnabled)
        let labels = row.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
        #expect(labels.contains("27C1U-D"))
        #expect(labels.contains(DisplayBrightnessFailure.unsupported.message))
        #expect(slider.toolTip == DisplayBrightnessFailure.unsupported.message)
    }

    @Test func updatingAVisibleRowKeepsTheSameNativeSlider() throws {
        _ = NSApplication.shared
        let row = DisplayBrightnessMenuRow(state: .init(target: target)) { _, _ in }
        let slider = try #require(row.subviews.compactMap { $0 as? NSSlider }.first)
        #expect(!slider.isEnabled)
        row.apply(.init(target: target, sample: .init(fraction: 0.42, backend: .ddc), fraction: 0.42, isLoading: false))
        #expect(row.subviews.compactMap { $0 as? NSSlider }.first === slider)
        #expect(slider.isEnabled && slider.doubleValue == 42)
    }
}


private final class MenuBrightnessFixture: DisplayBrightnessHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.37
    private var count = 0
    var writes: Int { lock.withLock { count } }
    func read(_ target: DisplayBrightnessTarget) async throws -> DisplayBrightnessSample {
        .init(fraction: lock.withLock { value }, backend: .ddc)
    }
    func write(_ fraction: Double, to target: DisplayBrightnessTarget, using backend: DisplayBrightnessBackend) async throws -> DisplayBrightnessSample {
        lock.withLock { value = fraction; count += 1 }
        return .init(fraction: fraction, backend: backend)
    }
}
@MainActor
private final class BrightnessTrackingDelegate: NSObject, NSMenuDelegate {
    let section: DisplayBrightnessMenu
    init(_ section: DisplayBrightnessMenu) { self.section = section }
    func menuWillOpen(_ menu: NSMenu) { section.beginTracking() }
    func menuDidClose(_ menu: NSMenu) { section.endTracking() }
}

@MainActor
private final class BrightnessTrackingState {
    let menu: NSMenu
    let legacy: NSMenuItem
    let hardware: MenuBrightnessFixture
    var firstRan = false
    var secondRan = false
    init(menu: NSMenu, legacy: NSMenuItem, hardware: MenuBrightnessFixture) {
        self.menu = menu; self.legacy = legacy; self.hardware = hardware
    }
    func firstTick() {
        firstRan = true
        let row = menu.items.compactMap { $0.view as? DisplayBrightnessMenuRow }.first
        let slider = row?.subviews.compactMap { $0 as? NSSlider }.first
        XCTAssertEqual(slider?.doubleValue, 37)
        XCTAssertEqual(slider?.isEnabled, true)
        XCTAssertTrue(menu.items.contains { $0 === legacy })
        slider?.doubleValue = 46
        if let slider { _ = slider.sendAction(slider.action, to: slider.target) }
    }
    func secondTick() {
        secondRan = true
        XCTAssertEqual(hardware.writes, 1, "Slider edits must reach hardware while the menu is tracking")
        menu.cancelTracking()
    }
}

@MainActor
final class BrightnessMenuTrackingTests: XCTestCase {
    func testNativeMenuProcessesAsyncReadsAndWritesBeforeItCloses() {
        _ = NSApplication.shared
        let hardware = MenuBrightnessFixture()
        let target = DisplayBrightnessTarget(id: 2, uuid: "fixture", name: "Menu fixture", isBuiltIn: false)
        let controller = DisplayBrightnessController(hardware: hardware, targets: { [target] })
        let menu = NSMenu(), legacy = NSMenuItem(title: "Existing command", action: nil, keyEquivalent: "")
        menu.addItem(legacy)
        let section = DisplayBrightnessMenu(menu: menu, controller: controller)
        let delegate = BrightnessTrackingDelegate(section); menu.delegate = delegate
        let window = NSPanel(contentRect: CGRect(x: 180, y: 180, width: 320, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame)); window.orderFrontRegardless()
        defer { section.stop(); window.orderOut(nil); window.contentView = nil }
        let state = BrightnessTrackingState(menu: menu, legacy: legacy, hardware: hardware)
        let first = Timer(timeInterval: 0.35, repeats: false) { _ in
            MainActor.assumeIsolated { state.firstTick() }
        }
        let second = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated { state.secondTick() }
        }
        RunLoop.main.add(first, forMode: .eventTracking); RunLoop.main.add(second, forMode: .eventTracking)
        defer { first.invalidate(); second.invalidate() }
        menu.popUp(positioning: nil, at: CGPoint(x: 10, y: 100), in: window.contentView)
        XCTAssertTrue(state.firstRan && state.secondRan)
        withExtendedLifetime(delegate) {}
    }
}
