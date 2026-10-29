import Foundation
import Testing
@testable import CubeCore

struct ShortcutTargetTests {
    private func item(_ url: String, kind: String, name: String = "入口") throws -> LauncherItem {
        LauncherItem(url: try #require(URL(string: url)), name: name, kind: try #require(LauncherItem.Kind(rawValue: kind)))
    }

    @Test func extendedTargetsSurviveConfigurationAndArchiveRoundTrips() throws {
        var configuration = CubeConfiguration()
        for (url, kind) in [("file:///tmp/report.pdf", "file"), ("https://example.com/help?q=1#top", "website"),
                            ("x-apple.systempreferences:com.apple.wifi-settings-extension", "systemSettings")] {
            try configuration.add(item(url, kind: kind), to: .front)
        }
        #expect(try JSONDecoder().decode(CubeConfiguration.self, from: JSONEncoder().encode(configuration)) == configuration)
        let archive = try ConfigurationArchive(configuration: configuration, contentLibrary: SnippetLibrary())
        #expect(try ConfigurationArchive.decode(archive.encoded()).configuration == configuration)
    }

    @Test func websitesRejectUnsafeSchemesMissingHostsAndCredentials() throws {
        let kind = try #require(LauncherItem.Kind(rawValue: "website"))
        for text in ["file:///tmp/test", "javascript:alert(1)", "ftp://example.com", "https:example.com", "https:///", "https://user:password@example.com", "https://user@example.com", "https://example.com:99999"] {
            var configuration = CubeConfiguration()
            let target = LauncherItem(url: try #require(URL(string: text)), name: "网页", kind: kind)
            #expect(throws: ConfigurationError.invalidItem) { try configuration.add(target, to: .front) }
        }
        for text in ["https://example.com", "http://localhost:8080/path", "https://例子.测试/path"] {
            var configuration = CubeConfiguration()
            try configuration.add(item(text, kind: "website"), to: .front)
        }
    }

    @Test func settingsAcceptOnlyCuratedPagesAndKindsMatchTargetSchemes() throws {
        for text in ["x-apple.systempreferences:com.apple.wifi-settings-extension", "x-apple.systempreferences:com.apple.BluetoothSettings", "x-apple.systempreferences:com.apple.Displays-Settings.extension", "x-apple.systempreferences:com.apple.Sound-Settings.extension", "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"] {
            var configuration = CubeConfiguration()
            try configuration.add(item(text, kind: "systemSettings"), to: .front)
        }
        for (text, kind) in [("x-apple.systempreferences:com.apple.Unknown", "systemSettings"), ("https://example.com", "systemSettings"), ("file:///tmp/report.pdf", "website"), ("https://example.com", "file"), ("x-apple.systempreferences:com.apple.wifi-settings-extension?custom", "systemSettings")] {
            var configuration = CubeConfiguration()
            let target = try item(text, kind: kind)
            #expect(throws: ConfigurationError.invalidItem) { try configuration.add(target, to: .front) }
        }
    }

    @Test func websiteDuplicatesNormalizeEmptyPathsAndDefaultPorts() throws {
        for (original, duplicate) in [("https://example.com", "https://example.com/"),
                                      ("https://example.com:443/docs", "https://example.com/docs"),
                                      ("http://example.com:80", "http://example.com/")] {
            var configuration = CubeConfiguration()
            try configuration.add(item(original, kind: "website"), to: .front)
            let target = try item(duplicate, kind: "website")
            #expect(throws: ConfigurationError.duplicateItem) { try configuration.add(target, to: .front) }
            let before = configuration
            #expect(throws: ConfigurationError.duplicateItem) { try configuration.place(target, to: .front, slot: 3) }
            #expect(configuration == before)
        }
    }

    @Test func websiteDuplicatesNormalizeHostAndSchemeButKeepPathsQueriesAndFragments() throws {
        var configuration = CubeConfiguration()
        try configuration.add(item("https://EXAMPLE.com/path", kind: "website"), to: .front)
        let duplicate = try item("https://example.com/path", kind: "website")
        #expect(throws: ConfigurationError.duplicateItem) { try configuration.add(duplicate, to: .front) }
        for text in ["https://example.com/Path", "https://example.com/path?q=1", "https://example.com/path#part"] {
            try configuration.add(item(text, kind: "website"), to: .front)
        }
        let before = configuration
        #expect(throws: ConfigurationError.duplicateItem) { try configuration.place(duplicate, to: .front, slot: 2, replacing: true) }
        #expect(configuration == before)
    }
}
