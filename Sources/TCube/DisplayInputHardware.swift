import Foundation
import CubeCore
import DisplayBrightnessBridge

enum DisplayInputOutcome: Equatable, Sendable { case confirmed(UInt16), notApplied(UInt16), otherInput(UInt16), sentUnconfirmed }
protocol DisplayInputHardware: Sendable {
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome
}

final class NativeDisplayInputHardware: DisplayInputHardware, @unchecked Sendable {
    private static func exchange(_ request: [UInt8], target: DisplayBrightnessTarget, replyCount: Int) throws -> [UInt8] {
        var reply = [UInt8](repeating: 0, count: replyCount)
        let status = target.uuid.withCString { uuid in
            request.withUnsafeBufferPointer { outgoing in
                reply.withUnsafeMutableBufferPointer { incoming in
                    TCInputDDCExchange(target.id, uuid, outgoing.baseAddress, UInt32(request.count), incoming.baseAddress, UInt32(replyCount))
                }
            }
        }
        guard status == TCBrightnessSuccess else {
            if status == TCBrightnessDisplayUnavailable { throw DisplayBrightnessFailure.disconnected }
            if status == TCBrightnessUnsupported { throw DisplayBrightnessFailure.unsupported }
            throw DisplayBrightnessFailure.readFailed
        }
        return reply
    }
    typealias Exchange = @Sendable ([UInt8], DisplayBrightnessTarget, Int) throws -> [UInt8]
    private let queue: DispatchQueue
    private let exchange: Exchange
    private let pause: @Sendable () -> Void
    init(queue: DispatchQueue = DisplayHardwareQueue.shared, exchange: @escaping Exchange = { try NativeDisplayInputHardware.exchange($0, target: $1, replyCount: $2) }, pause: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: 0.25) }) {
        self.queue = queue; self.exchange = exchange; self.pause = pause
    }
    private func readNow(_ target: DisplayBrightnessTarget) throws -> UInt16 {
        guard let reading = DDCInputCodec.parseReply(try exchange(DDCInputCodec.readRequest, target, 11)) else { throw DisplayBrightnessFailure.invalidResponse }
        return reading.current
    }
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
    }
    private func perform<T: Sendable>(_ operation: @escaping @Sendable (Cancellation) throws -> T) async throws -> T {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do { try cancellation.check(); continuation.resume(returning: try operation(cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
    func read(_ target: DisplayBrightnessTarget) async throws -> UInt16 {
        try await perform { _ in try self.readNow(target) }
    }
    func write(_ value: UInt16, target: DisplayBrightnessTarget, mapping: DisplayInputMapping) async throws -> DisplayInputOutcome {
        try await perform { cancellation in
            let before = try self.readNow(target)
            guard mapping.source(for: before) != nil, mapping.source(for: value) != nil else { throw DisplayBrightnessFailure.invalidValue }
            if before == value { return .confirmed(before) }
            try cancellation.check()
            try self.exchange(DDCInputCodec.writeRequest(value: value), target, 0)
            self.pause()
            guard let after = try? self.readNow(target) else { return .sentUnconfirmed }
            if after == value { return .confirmed(after) }
            if after == before { return .notApplied(after) }
            return .otherInput(after)
        }
    }
}
