import Foundation
import Testing
@testable import CubeCore

struct ClipboardHistoryTests {
    @Test func exactDuplicatesPromoteExistingEntryAndKeepOriginalWhitespace() {
        var history = ClipboardHistory()
        let firstTime = Date(timeIntervalSince1970: 1)
        #expect(history.record("  first\n", at: firstTime) == true)
        let first = history.entries[0]
        #expect(history.record("second", at: firstTime) == true)
        #expect(history.record("  first\n", at: Date(timeIntervalSince1970: 3)) == true)
        #expect(history.entries.map(\.text) == ["  first\n", "second"])
        #expect(history.entries[0].id == first.id)
        #expect(history.entries[0].capturedAt == Date(timeIntervalSince1970: 3))
        #expect(history.totalUTF8Bytes == "  first\nsecond".utf8.count)
    }

    @Test func deduplicationUsesExactUTF8RatherThanCanonicalUnicodeEquivalence() {
        var history = ClipboardHistory()
        let composed = "\u{e9}", decomposed = "e\u{301}"
        #expect(history.record(composed) == true)
        #expect(history.record(decomposed) == true)
        #expect(history.entries.count == 2)
        #expect(Array(history.entries[0].text.utf8) == Array(decomposed.utf8))
    }

    @Test func invalidTextIsSkippedWithoutTruncatingOrChangingHistory() {
        var history = ClipboardHistory()
        #expect(history.record("kept") == true)
        let before = history
        for text in ["", " \n\t\r", "has\0nul", String(repeating: "a", count: 65_537), String(repeating: "中", count: 21_846)] {
            #expect(history.record(text) == false)
            #expect(history == before)
        }
        #expect(history.record(String(repeating: "a", count: 65_536)) == true)
        #expect(history.entries[0].text.utf8.count == 65_536)
    }

    @Test func entryLimitEvictsTheOldestAfterOneHundredItems() {
        var history = ClipboardHistory()
        for index in 0..<105 { #expect(history.record("entry-\(index)") == true) }
        #expect(history.entries.count == 100)
        #expect(history.entries.first?.text == "entry-104")
        #expect(history.entries.last?.text == "entry-5")
    }

    @Test func totalByteBudgetEvictsOldestAndPromotionDoesNotIncreaseBytes() {
        var history = ClipboardHistory()
        for index in 0..<34 {
            let prefix = String(format: "%02d", index)
            #expect(history.record(prefix + String(repeating: "x", count: 65_534)) == true)
        }
        #expect(history.entries.count == 32)
        #expect(history.totalUTF8Bytes == 2 * 1024 * 1024)
        let last = history.entries.last!
        #expect(history.record(last.text) == true)
        #expect(history.entries.first?.id == last.id)
        #expect(history.entries.count == 32)
        #expect(history.totalUTF8Bytes == 2 * 1024 * 1024)
    }

    @Test func searchDeleteAndClearOperateOnlyOnMemoryEntries() {
        var history = ClipboardHistory()
        #expect(history.record("Café notes") == true)
        #expect(history.record("工作记录") == true)
        #expect(history.filtered(query: "CAFE").map(\.text) == ["Café notes"])
        #expect(history.filtered(query: "  ").count == 2)
        #expect(history.delete(history.entries[0].id) == true)
        #expect(history.delete(UUID()) == false)
        #expect(history.entries.map(\.text) == ["Café notes"])
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.totalUTF8Bytes == 0)
    }
}
