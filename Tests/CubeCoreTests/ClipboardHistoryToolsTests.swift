import Foundation
import Testing
@testable import CubeCore

struct ClipboardHistoryToolsTests {
    @Test func mergeUsesVisibleHistoryOrderAndDoesNotChangeOriginals() {
        var history = ClipboardHistory()
        history.record("  old \r\n\r\n\r\n end \t")
        history.record("\tnew \n\n")
        let original = history
        let ids = Set(history.entries.map(\.id))
        #expect(history.mergedText(selectedIDs: ids, query: "", trimLines: true, collapseBlankLines: true) == "new\n\nold\n\nend")
        #expect(history == original)
        #expect(history.mergedText(selectedIDs: ids, query: "old", trimLines: false, collapseBlankLines: false) == "  old \r\n\r\n\r\n end \t")
        #expect(history.mergedText(selectedIDs: [], query: "", trimLines: false, collapseBlankLines: false) == nil)
    }

    @Test func mergeRejectsOversizedOutputWithoutTruncation() {
        var history = ClipboardHistory()
        history.record(String(repeating: "a", count: 40_000))
        history.record(String(repeating: "b", count: 40_000))
        #expect(history.mergedText(selectedIDs: Set(history.entries.map(\.id)), query: "", trimLines: false, collapseBlankLines: false) == nil)
    }

    @Test func mergeHonorsUTF8BoundaryAndCleanupOptionsIndependently() {
        var history = ClipboardHistory()
        history.record("  first  \n \t\n\n  last ")
        let ids = Set(history.entries.map(\.id))
        #expect(history.mergedText(selectedIDs: ids, query: "", trimLines: true, collapseBlankLines: false) == "first\n\n\nlast")
        #expect(history.mergedText(selectedIDs: ids, query: "", trimLines: false, collapseBlankLines: true) == "  first  \n \t\n  last ")
        history.clearText()
        history.record(String(repeating: "中", count: 21_845))
        let large = history.entries[0].id
        history.record("a")
        #expect(history.mergedText(selectedIDs: [large], query: "", trimLines: false, collapseBlankLines: false)?.utf8.count == 65_535)
        #expect(history.mergedText(selectedIDs: Set(history.entries.map(\.id)), query: "", trimLines: false, collapseBlankLines: false) == nil)
    }

    @Test func lineCleanupRecognizesUnicodeLineBoundaries() {
        var history = ClipboardHistory()
        history.record("  first \u{2028}  second  \u{0085} \u{2029}\n  last ")
        #expect(history.mergedText(selectedIDs: Set(history.entries.map(\.id)), query: "", trimLines: true, collapseBlankLines: true) == "first\nsecond\n\nlast")
    }

    @Test func imagesHaveIndependentLimitsDedupePromoteAndClear() throws {
        var history = ClipboardHistory()
        history.record("retained text")
        for index in 0..<12 {
            #expect(history.recordImage(pngData: Data([UInt8(index)]), thumbnailPNG: Data([1]), width: 20, height: 30) == true)
        }
        #expect(history.images.count == 10)
        #expect(history.images.last?.pngData == Data([2]))
        let promoted = try #require(history.images.last)
        #expect(history.recordImage(pngData: promoted.pngData, thumbnailPNG: Data([1]), width: 20, height: 30) == true)
        #expect(history.images.first?.id == promoted.id)
        #expect(history.totalImageBytes == 10)
        #expect(history.deleteImage(promoted.id) == true)
        #expect(history.totalImageBytes == 9)
        history.clearImages()
        #expect(history.images.isEmpty)
        #expect(history.entries.map(\.text) == ["retained text"])
    }

    @Test func imageByteAndPixelBudgetsRejectInvalidAndEvictOldest() {
        var history = ClipboardHistory()
        for index in 0..<5 {
            #expect(history.recordImage(pngData: Data(repeating: UInt8(index), count: 8 * 1024 * 1024), thumbnailPNG: Data([1]), width: 4000, height: 4000) == true)
        }
        #expect(history.images.count == 4)
        #expect(history.images.last?.pngData.first == 1)
        #expect(history.totalImageBytes == 32 * 1024 * 1024)
        let before = history
        #expect(history.recordImage(pngData: Data([1]), thumbnailPNG: Data([1]), width: 4001, height: 4000) == false)
        #expect(history.recordImage(pngData: Data([1]), thumbnailPNG: Data([1]), width: Int.max, height: 2) == false)
        #expect(history.recordImage(pngData: Data(), thumbnailPNG: Data([1]), width: 1, height: 1) == false)
        #expect(history.recordImage(pngData: Data(repeating: 1, count: 8 * 1024 * 1024 + 1), thumbnailPNG: Data([1]), width: 1, height: 1) == false)
        #expect(history == before)
        history.clear()
        #expect(history.images.isEmpty)
        #expect(history.totalImageBytes == 0)
    }
}
