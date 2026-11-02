import Foundation

/// Stable numeric release versions. Int bounds agree with JavaScript's exact integers.
public struct ReleaseVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    private let numbers: [Int64]
    public var description: String { numbers.map(String.init).joined(separator: ".") }

    public init?(_ value: String) {
        guard value.utf8.count <= 64 else { return nil }
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int64] = []
        for part in parts {
            guard !part.isEmpty, part.count == 1 || part.first != "0",
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int64(part), number <= 9_007_199_254_740_991 else { return nil }
            numbers.append(number)
        }
        self.numbers = numbers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
    }
}

/// Release metadata is a notice only; this model never accepts installer URLs.
public struct ReleaseNotice: Equatable, Sendable {
    public static let repositoryPage = URL(string: "https://github.com/gd0306/t-cube/releases")!
    public static let endpoint = URL(string: "https://api.github.com/repos/gd0306/t-cube/releases/latest")!
    public static let maximumResponseBytes = 512 * 1024
    public let version: ReleaseVersion
    public let pageURL: URL

    public static func decode(_ data: Data) throws -> Self {
        struct Document: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let html_url: String
        }
        guard data.count <= maximumResponseBytes else { throw ReleaseNoticeError.invalidResponse }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard !document.draft, !document.prerelease, let version = ReleaseVersion(document.tag_name),
              document.html_url == repositoryPage.absoluteString + "/tag/" + document.tag_name,
              let pageURL = URL(string: document.html_url) else { throw ReleaseNoticeError.invalidResponse }
        return Self(version: version, pageURL: pageURL)
    }
}

public enum ReleaseNoticeError: Error, Sendable {
    case invalidResponse
    case unavailable
    case rateLimited(until: Date)
}
