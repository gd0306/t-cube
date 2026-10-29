import Foundation
import Testing
@testable import CubeCore

struct SnippetLibraryTests {
    @Test func wholeTextPreservesBodyAndMultilineValuesWhileSkippingEmptyFields() {
        let snippet = TextSnippet(title: "Office", body: "  Address\nFloor 2  ", fields: [
            SnippetField(label: "Contact", value: "Alice\nBob"),
            SnippetField(label: "Unused", value: " \n "),
            SnippetField(label: "Phone", value: "123")
        ])
        #expect(snippet.fullText == "  Address\nFloor 2  \nContact：Alice\nBob\nPhone：123")
        #expect(TextSnippet(title: "Only fields", body: " \n", fields: [
            SnippetField(label: "Name", value: "Alice")
        ]).fullText == "Name：Alice")
    }

    @Test func searchMatchesEveryContentPartWithoutCaseOrAccentSensitivity() {
        let items = [
            TextSnippet(title: "Résumé", body: "a"),
            TextSnippet(title: "Body", body: "CAFÉ"),
            TextSnippet(title: "Group", group: "Équipe", body: "c"),
            TextSnippet(title: "Label", fields: [SnippetField(label: "Téléphone", value: "123")]),
            TextSnippet(title: "Value", fields: [SnippetField(label: "Name", value: "Zoë")])
        ]
        let library = SnippetLibrary(items: items)
        for (query, title) in [("resume", "Résumé"), ("cafe", "Body"), ("equipe", "Group"),
                               ("TELEPHONE", "Label"), ("zoe", "Value")] {
            #expect(library.filtered(query: query).map(\.title) == [title])
        }
        #expect(library.filtered(query: "no match").isEmpty)
    }

    @Test func filtersComposeAndFavoritesKeepTheirOriginalRelativeOrder() {
        let library = SnippetLibrary(items: [
            TextSnippet(title: "First", group: "Office", body: "a"),
            TextSnippet(title: "Favorite A", group: "Office", body: "a", isFavorite: true),
            TextSnippet(title: "Other", group: "Home", body: "a", isFavorite: true),
            TextSnippet(title: "Last", group: "Office", body: "a"),
            TextSnippet(title: "Favorite B", group: "Office", body: "a", isFavorite: true)
        ])
        #expect(library.filtered(query: " \n ").map(\.title) == ["Favorite A", "Other", "Favorite B", "First", "Last"])
        #expect(library.filtered(query: "", group: "Office").map(\.title) == ["Favorite A", "Favorite B", "First", "Last"])
        #expect(library.filtered(query: "B", group: "Office", favoritesOnly: true).map(\.title) == ["Favorite B"])
        #expect(library.filtered(query: "", group: "Missing").isEmpty)
    }

    @Test func validationAcceptsPlainAndStructuredContent() throws {
        try SnippetLibrary(items: [TextSnippet(title: " Text ", body: "Hello"),
                                  TextSnippet(title: "Fields", fields: [SnippetField(label: "Name", value: "Alice")])]).validate()
        try SnippetLibrary().validate()
    }

    @Test func validationRejectsBlankTitlesAndMissingContent() {
        for snippet in [TextSnippet(title: " \n", body: "Hello"), TextSnippet(title: "Empty"),
                        TextSnippet(title: "Blank", body: " \n", fields: [SnippetField(label: "Name", value: "\t")]),
                        TextSnippet(title: "No label", fields: [SnippetField(label: " \n", value: "Alice")])] {
            #expect(throws: (any Error).self) { try SnippetLibrary(items: [snippet]).validate() }
        }
    }

    @Test func validationRejectsDuplicateIdentitiesAndUnsupportedVersions() {
        let snippet = TextSnippet(title: "Hello", body: "World")
        #expect(throws: (any Error).self) { try SnippetLibrary(items: [snippet, snippet]).validate() }
        let field = SnippetField(label: "Name", value: "Alice")
        #expect(throws: (any Error).self) {
            try SnippetLibrary(items: [TextSnippet(title: "A", fields: [field, field])]).validate()
        }
        #expect(throws: (any Error).self) {
            try SnippetLibrary(items: [TextSnippet(title: "A", fields: [field]), TextSnippet(title: "B", fields: [field])]).validate()
        }
        var future = SnippetLibrary()
        future.version = 2
        #expect(throws: (any Error).self) { try future.validate() }
    }

    @Test func missingStoreLoadsEmptyAndSavesIntoNewDirectories() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(url: directory.appendingPathComponent("nested/content-library.json"))
        #expect(try store.load().items.isEmpty)
        let library = SnippetLibrary(items: [TextSnippet(title: "公司", group: "工作", body: "Line 1\nLine 2",
            fields: [SnippetField(label: "姓名", value: "小王")], isFavorite: true)])
        try store.save(library)
        #expect(try store.load() == library)
        try store.save(SnippetLibrary())
        #expect(try store.load() == SnippetLibrary())
    }

    @Test func corruptOrUnsupportedExistingFilesAreNeverOverwritten() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(url: directory.appendingPathComponent("content-library.json"))
        let invalidLibrary = SnippetLibrary(items: [TextSnippet(title: "Invalid")])
        for original in [Data("not JSON".utf8), Data("{\"version\":2,\"items\":[]}".utf8),
                         try JSONEncoder().encode(invalidLibrary)] {
            try original.write(to: store.url)
            #expect(throws: (any Error).self) { try store.load() }
            #expect(throws: (any Error).self) { try store.save(SnippetLibrary()) }
            #expect(try Data(contentsOf: store.url) == original)
        }
    }

    @Test func invalidNewContentLeavesExistingValidLibraryUnchanged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(url: directory.appendingPathComponent("content-library.json"))
        let library = SnippetLibrary(items: [TextSnippet(title: "Saved", body: "Keep me")])
        try store.save(library)
        let original = try Data(contentsOf: store.url)
        #expect(throws: (any Error).self) { try store.save(SnippetLibrary(items: [TextSnippet(title: "Blank")])) }
        #expect(try Data(contentsOf: store.url) == original)
        #expect(try store.load() == library)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnippetLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }
}

@Test func templateFillsRepeatedVariablesWithoutReplacingInsertedText() {
    let template = SnippetTemplate("你好 {{姓名}}，{{姓名}}：{{内容}}")
    #expect(template.variables == ["姓名", "内容"])
    #expect(template.render(["姓名": "小王", "内容": "{{姓名}}"]) == "你好 小王，小王：{{姓名}}")
}

@Test func legacySnippetsRemainOrdinaryAndTemplateFlagRoundTrips() throws {
    let legacy = #"{"id":"11111111-1111-4111-8111-111111111111","title":"Code","group":"","body":"{{literal}}","fields":[],"isFavorite":false}"#.data(using: .utf8)!
    var snippet = try JSONDecoder().decode(TextSnippet.self, from: legacy)
    #expect(!snippet.isTemplate)
    snippet.isTemplate = true
    #expect(try JSONDecoder().decode(TextSnippet.self, from: JSONEncoder().encode(snippet)).isTemplate)
}

@Test func templateKeepsMalformedAndUnfilledPlaceholdersIntact() {
    let template = SnippetTemplate("{{ }} {{}} {{first}} {{second}} {{broken")
    #expect(template.variables == ["first", "second"])
    #expect(template.render(["first": "one"]) == "{{ }} {{}} one {{second}} {{broken")
}
