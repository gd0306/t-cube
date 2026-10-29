import AppKit
import CubeCore
import XCTest
@testable import TCube

/// Run synchronously so AppKit can service both consecutive nested modal loops.
final class LauncherTargetPickerModalTests: XCTestCase {
    func testChoosingWebsiteContinuesToWebsiteFormAndCancelPreservesConfiguration() {
        MainActor.assumeIsolated { Self.verifyModalChain(kind: .website) }
    }

    func testChoosingSettingsContinuesToCuratedPagesAndCancelPreservesConfiguration() {
        MainActor.assumeIsolated { Self.verifyModalChain(kind: .systemSettings) }
    }

    @MainActor
    private static func verifyModalChain(kind: LauncherItem.Kind) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        let original = model.configuration
        for _ in 0..<5 {
            let driver = ShortcutModalDriver(kind: kind)
            let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated { driver.advance() }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            RunLoop.main.add(timer, forMode: .default)
            defer { timer.invalidate() }
            model.choose(for: .front, slot: 0)
            timer.invalidate()
            XCTAssertEqual(driver.stages, ["kind", kind.rawValue], "\(driver.failure ?? "The modal chain returned before showing the target form")")
            XCTAssertNil(driver.failure)
            XCTAssertEqual(model.configuration, original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        }
    }
}

@MainActor
private final class ShortcutModalDriver {
    private let kind: LauncherItem.Kind
    private let deadline = Date().addingTimeInterval(5)
    private(set) var stages: [String] = []
    private(set) var failure: String?

    init(kind: LauncherItem.Kind) { self.kind = kind }

    func advance() {
        guard let window = NSApp.modalWindow else { return }
        let views = descendants(of: window.contentView)
        let labels = views.compactMap { $0 as? NSTextField }
        let popups = views.compactMap { $0 as? NSPopUpButton }
        let buttons = views.compactMap { $0 as? NSButton }
        if stages.isEmpty,
           labels.contains(where: { $0.stringValue == "添加入口" }),
           let popup = popups.first,
           let button = buttons.first(where: { $0.title == "继续" }) {
            popup.selectItem(withTitle: kind.title)
            guard popup.titleOfSelectedItem == kind.title else {
                fail("Could not select the requested target kind", window: window)
                return
            }
            stages.append("kind")
            button.performClick(nil)
        } else if stages == ["kind"],
                  labels.contains(where: { $0.stringValue == (kind == .website ? "网页入口" : "系统设置入口") }),
                  let cancel = buttons.first(where: { $0.title == "取消" }) {
            if kind == .website {
                let inputs = labels.filter(\.isEditable)
                guard inputs.count == 2,
                      inputs.contains(where: { $0.placeholderString == "https://example.com" }) else {
                    fail("The website form did not contain its name and URL inputs", window: window)
                    return
                }
            } else {
                guard let popup = popups.first,
                      popup.numberOfItems == 6,
                      popup.itemTitles == SystemSettingsTarget.allCases.map(\.title) else {
                    fail("The settings form did not contain the six curated pages", window: window)
                    return
                }
            }
            stages.append(kind.rawValue)
            cancel.performClick(nil)
        } else if Date() > deadline {
            fail("Timed out waiting for the expected modal stage: \(stages)", window: window)
        }
    }

    private func fail(_ message: String, window: NSWindow) {
        failure = message
        NSApp.abortModal()
        window.orderOut(nil)
    }

    private func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
