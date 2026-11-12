import Foundation

public enum ClipboardTextProcessingError: Error, LocalizedError, Sendable {
    case invalidInput, emptyResult, outputTooLarge, invalidJSON, invalidURL
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "文字为空、含空字符或超过 64 KiB。"
        case .emptyResult: "处理后没有可复制的文字。"
        case .outputTooLarge: "处理结果超过 64 KiB，请减少内容；原文保持不变。"
        case .invalidJSON: "JSON 格式不正确或嵌套超过 128 层；原文保持不变。"
        case .invalidURL: "URL 编码不完整或不是有效的 UTF-8；原文保持不变。"
        }
    }
}

public enum ClipboardTextAction: String, CaseIterable, Identifiable, Sendable {
    case original, trimLines, collapseBlankLines, uppercase, lowercase, jsonPretty, jsonCompact, urlEncode, urlDecode
    public var id: Self { self }
    public var title: String {
        switch self {
        case .original: "原文（纯文本）"
        case .trimLines: "去除每行首尾空白"
        case .collapseBlankLines: "合并连续空行"
        case .uppercase: "转为大写"
        case .lowercase: "转为小写"
        case .jsonPretty: "JSON 格式化"
        case .jsonCompact: "JSON 压缩"
        case .urlEncode: "URL 编码（参数值）"
        case .urlDecode: "URL 解码"
        }
    }

    public func apply(to source: String) throws -> String {
        guard ClipboardHistory.accepts(source) else { throw ClipboardTextProcessingError.invalidInput }
        let result: String
        switch self {
        case .original: result = source
        case .trimLines:
            result = Self.lines(source).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case .collapseBlankLines:
            var previousBlank = false
            result = Self.lines(source).filter { line in
                let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
                defer { previousBlank = blank }
                return !blank || !previousBlank
            }.joined(separator: "\n")
        case .uppercase: result = source.uppercased()
        case .lowercase: result = source.lowercased()
        case .jsonPretty, .jsonCompact:
            var formatter = ClipboardJSONLayout(source: source, pretty: self == .jsonPretty)
            result = try formatter.format()
        case .urlEncode:
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let encoded = source.addingPercentEncoding(withAllowedCharacters: unreserved) else { throw ClipboardTextProcessingError.invalidURL }
            result = encoded
        case .urlDecode:
            guard let decoded = source.removingPercentEncoding else { throw ClipboardTextProcessingError.invalidURL }
            result = decoded
        }
        guard result.utf8.count <= ClipboardHistory.maximumEntryUTF8Bytes else { throw ClipboardTextProcessingError.outputTooLarge }
        guard !result.utf8.contains(0) else { throw ClipboardTextProcessingError.invalidInput }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipboardTextProcessingError.emptyResult }
        return result
    }

    public func notice(source: String, result: String) -> String? {
        if self == .original { return nil }
        if source.utf8.elementsEqual(result.utf8) {
            switch self {
            case .urlEncode: return "内容不含需要转义的字符，无需 URL 编码。"
            case .urlDecode: return "原内容没有需要解码的百分号编码，内容保持原样。"
            case .jsonPretty, .jsonCompact: return "内容已符合所选 JSON 格式，无需修改。"
            default: return "处理结果与原文相同，无需修改。"
            }
        }
        if self == .urlEncode, source.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil {
            return "内容含 %XX 序列，再编码会将 % 编为 %25，请确认预览。"
        }
        return nil
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
}

/// Validate syntax and change whitespace only. Never decode/re-encode numbers or keys.
private struct ClipboardJSONLayout {
    let bytes: [UInt8]
    let pretty: Bool
    var index = 0
    var output = ""
    var outputBytes = 0

    init(source: String, pretty: Bool) { bytes = Array(source.utf8); self.pretty = pretty }

    mutating func format() throws -> String {
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw ClipboardTextProcessingError.invalidJSON }
        return output
    }

    mutating func emit(_ text: String) throws {
        outputBytes += text.utf8.count
        guard outputBytes <= ClipboardHistory.maximumEntryUTF8Bytes else { throw ClipboardTextProcessingError.outputTooLarge }
        output += text
    }

    mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func line(_ depth: Int) throws {
        if pretty { try emit("\n" + String(repeating: "  ", count: depth)) }
    }

    mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 128, index < bytes.count else { throw ClipboardTextProcessingError.invalidJSON }
        let byte = bytes[index]
        if byte == 123 || byte == 91 {
            let object = byte == 123, close: UInt8 = object ? 125 : 93
            index += 1
            try emit(object ? "{" : "[")
            if take(close) { try emit(object ? "}" : "]"); return }
            try line(depth + 1)
            while true {
                if object {
                    whitespace()
                    try string()
                    guard take(58) else { throw ClipboardTextProcessingError.invalidJSON }
                    try emit(pretty ? ": " : ":")
                }
                try value(depth: depth + 1)
                if take(close) { try line(depth); try emit(object ? "}" : "]"); return }
                guard take(44) else { throw ClipboardTextProcessingError.invalidJSON }
                try emit(","); try line(depth + 1)
            }
        } else if byte == 34 {
            try string()
        } else {
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"\A(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\z"#, options: .regularExpression) != nil else {
                throw ClipboardTextProcessingError.invalidJSON
            }
            try emit(token)
        }
    }

    mutating func string() throws {
        guard index < bytes.count, bytes[index] == 34 else { throw ClipboardTextProcessingError.invalidJSON }
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { try emit(String(decoding: bytes[start..<index], as: UTF8.self)); return }
            guard byte >= 32 else { throw ClipboardTextProcessingError.invalidJSON }
            if byte == 92 {
                guard index < bytes.count else { throw ClipboardTextProcessingError.invalidJSON }
                let escape = bytes[index]; index += 1
                if escape == 117 {
                    guard index + 4 <= bytes.count, bytes[index..<(index + 4)].allSatisfy({
                        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                    }) else { throw ClipboardTextProcessingError.invalidJSON }
                    index += 4
                } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) { throw ClipboardTextProcessingError.invalidJSON }
            }
        }
        throw ClipboardTextProcessingError.invalidJSON
    }
}
