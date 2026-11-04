import Testing
@testable import CubeCore

struct DisplayBrightnessTests {
    @Test func brightnessRequestsContainOnlyTheExpectedVCPAndChecksum() {
        #expect(DDCBrightnessCodec.readRequest == [0x82, 0x01, 0x10, 0xAC])
        #expect(DDCBrightnessCodec.writeRequest(value: 37) == [0x84, 0x03, 0x10, 0, 0x25, 0x8D])
        #expect(DDCBrightnessCodec.writeRequest(value: 0x1234) == [0x84, 0x03, 0x10, 0x12, 0x34, 0x8E])
    }

    @Test func validHardwareReplyPreservesCurrentMaximumAndFraction() throws {
        let value = try #require(DDCBrightnessCodec.parseReply([0x6E, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 37, 0xE5]))
        #expect(value.current == 37 && value.maximum == 100)
        #expect(abs(value.fraction - 0.37) < 0.00001)
        let wide = checkedReply([0x6E, 0x88, 0x02, 0, 0x10, 0, 0x03, 0xE8, 0x01, 0xF4, 0])
        let highRange = try #require(DDCBrightnessCodec.parseReply(wide))
        #expect(highRange.current == 500 && highRange.maximum == 1000 && highRange.fraction == 0.5)
    }

    @Test func invalidOrUnrelatedRepliesNeverBecomeBrightnessValues() {
        let good: [UInt8] = [0x6E, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 37, 0xE5]
        for (index, byte): (Int, UInt8) in [(0, 0), (1, 0x87), (2, 3), (3, 1), (4, 0x62), (5, 1), (7, 0), (9, 101)] {
            var reply = good; reply[index] = byte
            #expect(DDCBrightnessCodec.parseReply(checkedReply(reply)) == nil)
        }
        var corrupt = good; corrupt[10] ^= 1
        #expect(DDCBrightnessCodec.parseReply(corrupt) == nil)
        #expect(DDCBrightnessCodec.parseReply(Array(good.dropLast())) == nil)
        #expect(DDCBrightnessCodec.parseReply(good + [0]) == nil)
    }

    @Test func hardwareScaleIsRespectedAndInvalidUserValuesAreRejected() {
        #expect(DDCBrightnessCodec.rawValue(fraction: 0.37, maximum: 100) == 37)
        #expect(DDCBrightnessCodec.rawValue(fraction: 0.5, maximum: 1000) == 500)
        #expect(DDCBrightnessCodec.rawValue(fraction: 1, maximum: 65535) == 65535)
        #expect(DDCBrightnessCodec.rawValue(fraction: 0, maximum: 100) == 0)
        for invalid in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            #expect(DDCBrightnessCodec.rawValue(fraction: invalid, maximum: 100) == nil)
        }
        #expect(DDCBrightnessCodec.rawValue(fraction: 0.5, maximum: 0) == nil)
    }

    private func checkedReply(_ input: [UInt8]) -> [UInt8] {
        var bytes = input
        bytes[10] = bytes.dropLast().reduce(UInt8(0x50), ^)
        return bytes
    }
}
