import Foundation
import Testing
import CubeCore
import DisplayBrightnessBridge
@testable import TCube

private func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool { semaphore.wait(timeout: .now() + 2) == .success }
private let inputTarget = DisplayBrightnessTarget(id: 2, uuid: "D458F247-EEA0-BB54-0857-D6964E3302DB", name: "Fixture", isBuiltIn: false)
private let inputMapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
private func inputReply(_ value: UInt16) -> [UInt8] {
    let bytes: [UInt8] = [0x6e, 0x88, 2, 0, 0x60, 0, 0, 14, UInt8(value >> 8), UInt8(value & 255)]
    return bytes + [bytes.reduce(UInt8(0x50), ^)]
}
private final class InputExchangeFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt16?]
    private var requests: [[UInt8]] = []
    var onRead: (@Sendable () -> Void)?
    init(_ values: [UInt16?]) { self.values = values }
    var sent: [[UInt8]] { lock.withLock { requests } }
    func exchange(_ request: [UInt8], _ target: DisplayBrightnessTarget, _ count: Int) throws -> [UInt8] {
        let value: UInt16? = lock.withLock {
            requests.append(request)
            guard count != 0, !values.isEmpty else { return nil }
            return values.removeFirst()
        }
        if count == 0 { return [] }
        onRead?()
        guard let value else { throw DisplayBrightnessFailure.readFailed }
        return inputReply(value)
    }
}
@Suite(.serialized) struct DisplayInputHardwareTests {
    @Test func productionWritePreflightAndReadbackClassification() async throws {
        for (after, expected): (UInt16?, DisplayInputOutcome) in [(5, .confirmed(5)), (7, .notApplied(7)), (16, .otherInput(16)), (nil, .sentUnconfirmed)] {
            let fixture = InputExchangeFixture([7, after])
            let hardware = NativeDisplayInputHardware(queue: DispatchQueue(label: UUID().uuidString), exchange: fixture.exchange, pause: {})
            #expect(try await hardware.write(5, target: inputTarget, mapping: inputMapping) == expected)
            #expect(fixture.sent == [DDCInputCodec.readRequest, DDCInputCodec.writeRequest(value: 5), DDCInputCodec.readRequest])
        }
        for before: UInt16 in [5, 16] {
            let fixture = InputExchangeFixture([before])
            let hardware = NativeDisplayInputHardware(queue: DispatchQueue(label: UUID().uuidString), exchange: fixture.exchange, pause: {})
            if before == 5 { #expect(try await hardware.write(5, target: inputTarget, mapping: inputMapping) == .confirmed(5)) }
            else { await #expect(throws: DisplayBrightnessFailure.invalidValue) { try await hardware.write(5, target: inputTarget, mapping: inputMapping) } }
            #expect(fixture.sent == [DDCInputCodec.readRequest])
        }
    }
    @Test func cancellationBetweenPreflightAndSetPreventsWrite() async throws {
        let fixture = InputExchangeFixture([7]), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        fixture.onRead = { entered.signal(); release.wait() }
        let hardware = NativeDisplayInputHardware(queue: DispatchQueue(label: UUID().uuidString), exchange: fixture.exchange, pause: {})
        let task = Task { try await hardware.write(5, target: inputTarget, mapping: inputMapping) }
        #expect(waitForSignal(entered))
        task.cancel(); release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.sent == [DDCInputCodec.readRequest])
    }
    @Test func cancellationWhileQueuedAndSharedQueueSerialization() async throws {
        let queue = DisplayHardwareQueue.shared, entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        queue.async { entered.signal(); release.wait() }
        #expect(waitForSignal(entered))
        let fixture = InputExchangeFixture([7])
        let hardware = NativeDisplayInputHardware(exchange: fixture.exchange, pause: {})
        let task = Task { try await hardware.write(5, target: inputTarget, mapping: inputMapping) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.sent.isEmpty)
        task.cancel(); release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.sent.isEmpty)
    }
    @Test func bridgeTransmissionResultsPreserveAcceptedFirstSet() {
        #expect(TCInputTestTransmissionResults(Int32(TCBrightnessSuccess), Int32(TCBrightnessOperationFailed)) == TCBrightnessSuccess)
        #expect(TCInputTestTransmissionResults(Int32(TCBrightnessSuccess), Int32(TCBrightnessDisplayUnavailable)) == TCBrightnessSuccess)
        #expect(TCInputTestTransmissionResults(Int32(TCBrightnessOperationFailed), Int32(TCBrightnessSuccess)) == TCBrightnessOperationFailed)
        #expect(TCInputTestTransmissionResults(Int32(TCBrightnessDisplayUnavailable), Int32(TCBrightnessSuccess)) == TCBrightnessDisplayUnavailable)
    }
}
