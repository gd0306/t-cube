import Foundation
import CubeCore
import DisplayBrightnessBridge

enum DisplayHardwareQueue {
    static let shared = DispatchQueue(label: "local.tcube.display-hardware", qos: .userInitiated)
}

protocol DisplayBrightnessHardware: Sendable {
    func read(_ target: DisplayBrightnessTarget) async throws -> DisplayBrightnessSample
    func write(_ fraction: Double, to target: DisplayBrightnessTarget,
               using backend: DisplayBrightnessBackend) async throws -> DisplayBrightnessSample
}

/// Blocking display-driver requests never run on the main actor or a rendering loop.
final class NativeDisplayBrightnessHardware: DisplayBrightnessHardware, @unchecked Sendable {
    private let queue = DisplayHardwareQueue.shared

    func read(_ target: DisplayBrightnessTarget) async throws -> DisplayBrightnessSample {
        guard UUID(uuidString: target.uuid) != nil else { throw DisplayBrightnessFailure.unsupported }
        return try await perform { cancellation in
            try cancellation.check()
            var value: Float = 0
            let status = target.uuid.withCString { TCBrightnessReadNative(target.id, $0, &value) }
            if status == TCBrightnessSuccess {
                return DisplayBrightnessSample(fraction: Double(value), backend: .native)
            }
            if status == TCBrightnessDisplayUnavailable { throw DisplayBrightnessFailure.disconnected }
            guard !target.isBuiltIn, status == TCBrightnessUnsupported else {
                throw status == TCBrightnessUnsupported ? DisplayBrightnessFailure.unsupported : .readFailed
            }
            let reading = try Self.readDDC(target, cancellation: cancellation)
            return DisplayBrightnessSample(fraction: reading.fraction, backend: .ddc)
        }
    }

    func write(_ fraction: Double, to target: DisplayBrightnessTarget,
               using backend: DisplayBrightnessBackend) async throws -> DisplayBrightnessSample {
        guard fraction.isFinite, (0...1).contains(fraction) else { throw DisplayBrightnessFailure.invalidValue }
        return try await perform { cancellation in
            try cancellation.check()
            switch backend {
            case .native:
                let status = target.uuid.withCString { TCBrightnessWriteNative(target.id, $0, Float(fraction)) }
                try Self.checkStatus(status, writing: true)
                try cancellation.check()
                var actual: Float = 0
                let read = target.uuid.withCString { TCBrightnessReadNative(target.id, $0, &actual) }
                try Self.checkStatus(read, writing: false)
                guard abs(Double(actual) - fraction) <= 0.02 else { throw DisplayBrightnessFailure.verificationFailed }
                return DisplayBrightnessSample(fraction: Double(actual), backend: .native)
            case .ddc:
                let before = try Self.readDDC(target, cancellation: cancellation)
                guard let raw = DDCBrightnessCodec.rawValue(fraction: fraction, maximum: before.maximum) else {
                    throw DisplayBrightnessFailure.invalidValue
                }
                try cancellation.check()
                try Self.exchange(DDCBrightnessCodec.writeRequest(value: raw), replyCount: 0, target: target)
                try cancellation.check()
                let after = try Self.readDDC(target, cancellation: cancellation)
                guard abs(after.fraction - fraction) <= max(0.02, 1 / Double(after.maximum)) else {
                    throw DisplayBrightnessFailure.verificationFailed
                }
                return DisplayBrightnessSample(fraction: after.fraction, backend: .ddc)
            }
        }
    }

    private static func readDDC(_ target: DisplayBrightnessTarget, cancellation: Cancellation) throws -> DDCBrightnessValue {
        var lastError: Error = DisplayBrightnessFailure.invalidResponse
        for _ in 0..<2 {
            try cancellation.check()
            do {
                let bytes = try exchange(DDCBrightnessCodec.readRequest, replyCount: 11, target: target)
                if let value = DDCBrightnessCodec.parseReply(bytes) { return value }
                lastError = DisplayBrightnessFailure.invalidResponse
            } catch let error as DisplayBrightnessFailure {
                if error == .unsupported || error == .disconnected { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    @discardableResult
    private static func exchange(_ request: [UInt8], replyCount: Int, target: DisplayBrightnessTarget) throws -> [UInt8] {
        var reply = [UInt8](repeating: 0, count: replyCount)
        let status = target.uuid.withCString { uuid in
            request.withUnsafeBufferPointer { outgoing in
                reply.withUnsafeMutableBufferPointer { incoming in
                    TCBrightnessDDCExchange(target.id, uuid, outgoing.baseAddress, UInt32(request.count),
                        incoming.baseAddress, UInt32(replyCount))
                }
            }
        }
        try checkStatus(status, writing: replyCount == 0)
        return reply
    }

    private static func checkStatus(_ status: Int32, writing: Bool) throws {
        switch status {
        case Int32(TCBrightnessSuccess): return
        case Int32(TCBrightnessUnsupported): throw DisplayBrightnessFailure.unsupported
        case Int32(TCBrightnessDisplayUnavailable): throw DisplayBrightnessFailure.disconnected
        case Int32(TCBrightnessInvalidArgument): throw DisplayBrightnessFailure.invalidValue
        default: throw writing ? DisplayBrightnessFailure.writeFailed : .readFailed
        }
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable (Cancellation) throws -> T) async throws -> T {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do { try cancellation.check(); continuation.resume(returning: try work(cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}
