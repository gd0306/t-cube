import Foundation
import Testing
@testable import CubeCore

struct ClipboardTextProcessingTests {
    @Test func cleansLinesAndConvertsCaseWithoutRewritingTheSource() throws {
        let source = "  A b \r\n\r\n\r\n 中文\t"
        #expect(try ClipboardTextAction.trimLines.apply(to: source) == "A b\n\n\n中文")
        #expect(try ClipboardTextAction.collapseBlankLines.apply(to: source) == "  A b \n\n 中文\t")
        #expect(try ClipboardTextAction.uppercase.apply(to: "Straße 中文") == "STRASSE 中文")
        #expect(try ClipboardTextAction.lowercase.apply(to: "HELLO 中文") == "hello 中文")
        #expect(try ClipboardTextAction.original.apply(to: source) == source)
    }

    @Test func formatsJSONWithoutChangingNumbersKeysOrStringEscapes() throws {
        let source = #" {"id":900719925474099312345,"a":[true,null,"a b\n\""],"id":1e400} "#
        let pretty = try ClipboardTextAction.jsonPretty.apply(to: source)
        #expect(pretty == "{\n  \"id\": 900719925474099312345,\n  \"a\": [\n    true,\n    null,\n    \"a b\\n\\\"\"\n  ],\n  \"id\": 1e400\n}")
        #expect(try ClipboardTextAction.jsonCompact.apply(to: pretty) == source.trimmingCharacters(in: .whitespaces))
        #expect(try ClipboardTextAction.jsonPretty.apply(to: "42") == "42")
        #expect(try ClipboardTextAction.jsonPretty.apply(to: "[]") == "[]")
        for invalid in ["{bad}", "[1,]", "{\"a\":01}", "true false", "\"\\x\"", "{\"a\":}", "[", "\"a\n b\""] {
            #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.jsonPretty.apply(to: invalid) }
        }
    }

    @Test func URLComponentEncodingRoundTripsUnicodeAndNeverTreatsPlusAsSpace() throws {
        let text = "中文 a+b/?=😀"
        #expect(try ClipboardTextAction.urlEncode.apply(to: text) == "%E4%B8%AD%E6%96%87%20a%2Bb%2F%3F%3D%F0%9F%98%80")
        #expect(try ClipboardTextAction.urlDecode.apply(to: ClipboardTextAction.urlEncode.apply(to: text)) == text)
        #expect(try ClipboardTextAction.urlDecode.apply(to: "a+b") == "a+b")
        for invalid in ["%", "%Q0", "%FF", "%00"] {
            #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.urlDecode.apply(to: invalid) }
        }
    }

    @Test func explainsNoOpAndPotentialDoubleEncodingBeforeConfirmation() throws {
        for action in [ClipboardTextAction.urlEncode, .urlDecode, .jsonPretty] {
            let source = action == .jsonPretty ? "42" : "abc-123"
            let output = try action.apply(to: source)
            #expect(output == source)
            #expect(action.notice(source: source, result: output) != nil)
        }
        let output = try ClipboardTextAction.urlEncode.apply(to: "a%20b")
        #expect(output == "a%2520b")
        #expect(ClipboardTextAction.urlEncode.notice(source: "a%20b", result: output)?.contains("%25") == true)
        #expect(ClipboardTextAction.urlEncode.notice(source: "中文", result: try ClipboardTextAction.urlEncode.apply(to: "中文")) == nil)
    }

    @Test func boundsInputOutputAndNestingInsteadOfTruncatingOrCrashing() throws {
        #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.original.apply(to: "\0") }
        #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.trimLines.apply(to: " \t ") }
        #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.urlEncode.apply(to: String(repeating: "中", count: 8000)) }
        #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.original.apply(to: String(repeating: "a", count: 65537)) }
        #expect(throws: ClipboardTextProcessingError.self) { try ClipboardTextAction.jsonPretty.apply(to: String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)) }
    }
}
