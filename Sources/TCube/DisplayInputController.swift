import Foundation
import CoreGraphics

import CubeCore

struct DisplayInputRow: Identifiable {
    let target: DisplayBrightnessTarget
    var id: String { target.uuid }
    var mapping: DisplayInputMapping?
    var current: UInt16?
    var busy = true
    var message: String?
    var enabled: Bool { !busy && mapping?.source(for: current ?? UInt16.max) != nil && current != nil }
}

@MainActor final class DisplayInputController {
    private(set) var rows: [DisplayInputRow] = []
    private(set) var isOpen = false
    var onChange: (() -> Void)?
    private let hardware: any DisplayInputHardware
    private let targets: @MainActor () -> [DisplayBrightnessTarget]
    private let store: DisplayInputStore
    private var generation = 0
    private var tasks: [Task<Void, Never>] = []
    init(hardware: any DisplayInputHardware, targets: @escaping @MainActor () -> [DisplayBrightnessTarget], store: DisplayInputStore) {
        self.hardware = hardware; self.targets = targets; self.store = store
    }
    func beginTracking() { isOpen = true; refresh() }
    func endTracking() { isOpen = false; generation += 1; tasks.forEach { $0.cancel() }; tasks.removeAll() }
    func stop() { endTracking(); rows = []; onChange = nil }
    func screenParametersChanged() { generation += 1; tasks.forEach { $0.cancel() }; tasks.removeAll(); rows = []; if isOpen { refresh() } }
    func refresh() {
        guard isOpen else { return }
        generation += 1; tasks.forEach { $0.cancel() }; tasks.removeAll()
        let token = generation
        let displays = targets().filter { !$0.isBuiltIn && UUID(uuidString: $0.uuid) != nil }
        let identities = Dictionary(grouping: displays, by: { UUID(uuidString: $0.uuid)!.uuidString })
        rows = displays.filter { identities[UUID(uuidString: $0.uuid)!.uuidString]?.count == 1 }.map { target in
            var row = DisplayInputRow(target: target)
            do {
                row.mapping = try store.mapping(for: target.uuid) ?? Self.preset(target)
            } catch { row.message = "输入配置损坏，请备份并修复 display-inputs.json" }
            return row
        }
        onChange?()
        for row in rows {
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    let current = try await self.hardware.read(row.target)
                    guard self.isOpen, self.generation == token, !Task.isCancelled else { return }
                    self.update(row.id) { $0.current = current; $0.busy = false; if $0.message == nil && $0.mapping?.source(for: current) == nil { $0.message = "当前输入代码 \(current)；请设置映射" } }
                } catch {
                    guard self.isOpen, self.generation == token, !Task.isCancelled else { return }
                    self.update(row.id) { $0.busy = false; if $0.message == nil { $0.message = "无法读取输入源，请检查 DDC/CI" } }
                }
            }
            tasks.append(task)
        }
    }
    static func preset(_ target: DisplayBrightnessTarget) -> DisplayInputMapping? {
        guard target.name == "27C1U-D", CGDisplayVendorNumber(target.id) == 9699, CGDisplayModelNumber(target.id) == 65535 else { return nil }
        return DisplayInputMapping(typeC: 7, hdmi: 5)
    }
    func save(_ mapping: DisplayInputMapping, for uuid: String) throws {
        guard let target = rows.first(where: { $0.id == uuid })?.target else { throw DisplayBrightnessFailure.disconnected }
        try store.save(mapping, for: uuid)
        if isOpen { refresh() }
        else { Task { [hardware] in _ = try? await hardware.read(target) } }
    }
    func setSource(_ source: DisplayInputSource, for uuid: String) {
        guard isOpen, let row = rows.first(where: { $0.id == uuid }), row.enabled,
              let mapping = row.mapping, mapping.source(for: row.current!) != source else { return }
        let token = generation
        update(uuid) { $0.busy = true; $0.message = "正在切换…" }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.hardware.write(mapping.value(for: source), target: row.target, mapping: mapping)
                guard self.isOpen, self.generation == token, !Task.isCancelled else { return }
                self.update(uuid) { row in
                    row.busy = false
                    switch result {
                    case .confirmed(let value): row.current = value; row.message = nil
                    case .notApplied(let value): row.current = value; row.message = "显示器未切换输入"
                    case .otherInput(let value): row.current = value; row.message = "当前输入代码 \(value)；请设置映射"
                    case .sentUnconfirmed: row.current = nil; row.message = "命令已发送，无法确认；请在当前显示画面的主机或显示器实体菜单中切回"
                    }
                }
            } catch {
                guard self.isOpen, self.generation == token, !Task.isCancelled else { return }
                self.update(uuid) { $0.current = nil; $0.busy = false; $0.message = "切换失败，请刷新后重试" }
            }
        }
        tasks.append(task)
    }
    private func update(_ uuid: String, _ body: (inout DisplayInputRow) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == uuid }) else { return }; body(&rows[index]); onChange?()
    }
}
