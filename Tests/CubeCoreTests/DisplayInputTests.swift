import Foundation
import Testing
@testable import CubeCore

@Test func inputFramesAndNoncontinuousReplies() {
    #expect(DDCInputCodec.readRequest == [0x82, 0x01, 0x60, 0xDC])
    #expect(DDCInputCodec.writeRequest(value: 5) == [0x84, 0x03, 0x60, 0, 5, 0xDD])
    #expect(DDCInputCodec.writeRequest(value: 7) == [0x84, 0x03, 0x60, 0, 7, 0xDF])
    #expect(DDCInputCodec.parseReply([0x6E, 0x80, 0xBE, 0, 0x60, 0, 0, 14, 0, 7, 0xDD]) == nil)
    #expect(DDCInputCodec.parseReply([0x6E, 0x88, 0x02, 0, 0x60, 1, 0, 3, 0, 16, 0xC6])?.current == 16)
}

@Test func inputMappingRequiresDistinctCodes() {
    #expect(DisplayInputMapping(typeC: 7, hdmi: 7) == nil)
    let mapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
    #expect(mapping.source(for: 7) == .typeC)
    #expect(mapping.source(for: 42) == nil)
}

@Test func inputStorePreservesCorruptFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("display-inputs.json")
    let store = DisplayInputStore(url: url)
    let id = UUID().uuidString
    let mapping = DisplayInputMapping(typeC: 7, hdmi: 5)!
    try store.save(mapping, for: id)
    #expect(try store.mapping(for: id) == mapping)
    let corrupt = Data("{bad".utf8); try corrupt.write(to: url)
    #expect(throws: (any Error).self) { try store.save(mapping, for: id) }
    #expect(try Data(contentsOf: url) == corrupt)
}
