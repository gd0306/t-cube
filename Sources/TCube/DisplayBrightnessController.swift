import Foundation
import CubeCore

struct DisplayBrightnessRow: Equatable, Identifiable {
    let target: DisplayBrightnessTarget
    var id: String { target.uuid }
    var sample: DisplayBrightnessSample?
    var fraction: Double?
    var isLoading = true
    var isWriting = false
    var message: String?
    var isEnabled: Bool { sample != nil }
}

@MainActor
final class DisplayBrightnessController {
    private(set) var rows: [DisplayBrightnessRow] = []
    private(set) var isMenuOpen = false
    var onChange: (() -> Void)?
    private let hardware: any DisplayBrightnessHardware
    private let targets: @MainActor () -> [DisplayBrightnessTarget]
    private let debounce: @Sendable () async throws -> Void
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var edits: [String: UInt64] = [:]
    private var pending: [String: Double] = [:]
    private var writeTasks: [String: Task<Void, Never>] = [:]
    private var writeTokens: [String: UUID] = [:]
    private var stopped = false

    init(hardware: any DisplayBrightnessHardware,
         targets: @escaping @MainActor () -> [DisplayBrightnessTarget],
         debounce: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }) {
        self.hardware = hardware; self.targets = targets; self.debounce = debounce
    }

    func beginTracking() { guard !stopped else { return }; isMenuOpen = true; refresh() }

    func endTracking() {
        isMenuOpen = false
        refreshGeneration &+= 1
        refreshTask?.cancel(); refreshTask = nil
        for index in rows.indices { rows[index].isLoading = false }
        // User writes keep draining after dismissal, including the last drag value.
    }

    func refresh() {
        guard isMenuOpen, !stopped else { return }
        refreshTask?.cancel(); refreshGeneration &+= 1
        let generation = refreshGeneration
        var seen: Set<String> = []
        let displays = targets().filter { seen.insert($0.uuid).inserted }
        let previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = displays.map { target in
            var row = previous[target.uuid].flatMap { $0.target == target ? $0 : nil } ?? DisplayBrightnessRow(target: target)
            row.isLoading = true
            return row
        }
        onChange?()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            for target in displays {
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                let version = self.edits[target.uuid, default: 0]
                if self.writeTokens[target.uuid] != nil {
                    self.update(target) { $0.isLoading = false }
                    continue
                }
                do {
                    let sample = try await self.hardware.read(target)
                    guard sample.fraction.isFinite, (0...1).contains(sample.fraction) else {
                        throw DisplayBrightnessFailure.invalidResponse
                    }
                    guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                    self.update(target) { row in
                        row.isLoading = false
                        if self.edits[target.uuid, default: 0] == version {
                            row.sample = sample; row.fraction = sample.fraction; row.message = nil
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                    self.update(target) { row in
                        row.isLoading = false
                        if self.edits[target.uuid, default: 0] == version {
                            row.sample = nil; row.fraction = nil; row.message = Self.message(error)
                        }
                    }
                }
            }
            if self.refreshGeneration == generation { self.refreshTask = nil }
        }
    }

    func screenParametersChanged() {
        refreshGeneration &+= 1; refreshTask?.cancel(); refreshTask = nil
        writeTasks.values.forEach { $0.cancel() }
        writeTasks.removeAll(); writeTokens.removeAll(); pending.removeAll(); edits.removeAll()
        rows.removeAll()
        if isMenuOpen { refresh() } else { onChange?() }
    }

    func setFraction(_ fraction: Double, for uuid: String) {
        guard !stopped, fraction.isFinite, (0...1).contains(fraction),
              let index = rows.firstIndex(where: { $0.id == uuid }), rows[index].isEnabled else { return }
        let target = rows[index].target
        edits[uuid, default: 0] &+= 1
        pending[uuid] = fraction
        rows[index].fraction = fraction; rows[index].message = nil; rows[index].isWriting = true
        onChange?()
        guard writeTasks[uuid] == nil else { return }
        let token = UUID(); writeTokens[uuid] = token
        writeTasks[uuid] = Task { [weak self] in await self?.drain(target, token: token) }
    }

    private func drain(_ target: DisplayBrightnessTarget, token: UUID) async {
        let key = target.uuid
        defer {
            if writeTokens[key] == token {
                writeTokens.removeValue(forKey: key); writeTasks.removeValue(forKey: key)
                update(target) { $0.isWriting = false }
            }
        }
        while !stopped, !Task.isCancelled, writeTokens[key] == token {
            do { try await debounce() } catch { return }
            guard !stopped, !Task.isCancelled, writeTokens[key] == token,
                  let fraction = pending.removeValue(forKey: key),
                  let row = rows.first(where: { $0.target == target }), let backend = row.sample?.backend else { return }
            let version = edits[key, default: 0]
            do {
                let actual = try await hardware.write(fraction, to: target, using: backend)
                guard actual.fraction.isFinite, (0...1).contains(actual.fraction) else {
                    throw DisplayBrightnessFailure.invalidResponse
                }
                guard !Task.isCancelled, writeTokens[key] == token else { return }
                update(target) { row in
                    row.sample = actual; row.isLoading = false
                    if self.edits[key, default: 0] == version {
                        row.fraction = actual.fraction; row.message = nil
                    }
                }
            } catch {
                guard !Task.isCancelled, writeTokens[key] == token else { return }
                let actual = try? await hardware.read(target)
                guard !Task.isCancelled, writeTokens[key] == token else { return }
                let valid = actual.flatMap { $0.fraction.isFinite && (0...1).contains($0.fraction) ? $0 : nil }
                if valid == nil { pending.removeValue(forKey: key) }
                update(target) { row in
                    row.sample = valid; row.isLoading = false
                    if self.pending[key] == nil {
                        row.fraction = valid?.fraction; row.message = Self.message(error)
                    }
                }
            }
            if pending[key] == nil { return }
        }
    }

    private func update(_ target: DisplayBrightnessTarget, _ action: (inout DisplayBrightnessRow) -> Void) {
        guard !stopped, let index = rows.firstIndex(where: { $0.target == target }) else { return }
        action(&rows[index]); onChange?()
    }

    private static func message(_ error: Error) -> String {
        (error as? DisplayBrightnessFailure)?.message ?? DisplayBrightnessFailure.readFailed.message
    }

    func stop() {
        stopped = true; isMenuOpen = false
        refreshGeneration &+= 1; refreshTask?.cancel(); refreshTask = nil
        writeTasks.values.forEach { $0.cancel() }
        writeTasks.removeAll(); writeTokens.removeAll(); pending.removeAll(); edits.removeAll()
        onChange = nil; rows.removeAll()
    }
}
