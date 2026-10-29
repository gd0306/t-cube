import Foundation

public struct SnippetTemplate {
    private let text: String
    private let matches: [NSTextCheckingResult]
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{([^{}\r\n]+)\}\}"#)

    public init(_ text: String) {
        self.text = text
        self.matches = Self.pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    public var variables: [String] {
        var seen = Set<String>()
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[range])
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    public func render(_ values: [String: String]) -> String {
        var output = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            output += text[cursor..<range.lowerBound]
            output += values[String(text[nameRange])] ?? String(text[range])
            cursor = range.upperBound
        }
        output += text[cursor...]
        return output
    }
}
