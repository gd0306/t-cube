import Foundation

public enum ConfigurationArchiveError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case rollbackFailed(original: String, rollback: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "不支持的备份版本：\(version)。请使用支持此版本的 T-Cube。"
        case .rollbackFailed(let original, let rollback):
            "恢复未完成：\(original)\n回滚也未完成：\(rollback)\n自动备份已保留，请从备份恢复。"
        }
    }
}

/// A portable JSON document. Launcher settings and the content library retain their own schemas.
public struct ConfigurationArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let createdAt: Date
    public let configuration: CubeConfiguration
    public let contentLibrary: SnippetLibrary

    public init(configuration: CubeConfiguration, contentLibrary: SnippetLibrary, createdAt: Date = Date()) throws {
        version = Self.currentVersion
        self.createdAt = createdAt
        self.configuration = configuration
        self.contentLibrary = contentLibrary
        try validate()
    }

    public var launcherCount: Int {
        CubeFace.allCases.reduce(0) { $0 + configuration.group(for: $1).slots.compactMap { $0 }.count }
    }
    public var contentCount: Int { contentLibrary.items.count }

    public func validate() throws {
        guard version == Self.currentVersion else { throw ConfigurationArchiveError.unsupportedVersion(version) }
        try configuration.validate()
        try contentLibrary.validate()
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey { case version, createdAt, configuration, contentLibrary }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ConfigurationArchiveError.unsupportedVersion(version) }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        configuration = try container.decode(CubeConfiguration.self, forKey: .configuration)
        contentLibrary = try container.decode(SnippetLibrary.self, forKey: .contentLibrary)
        try validate()
    }
}

/// Validates both live files before export or replacement. Imports always preserve a pre-import archive.
/// Individual files use atomic replacement; a failed multi-file update restores the original bytes.
public struct ConfigurationArchiveStore: Sendable {
    public let configurationURL: URL
    public let contentLibraryURL: URL
    public let backupsURL: URL
    private let writeFile: @Sendable (Data, URL) throws -> Void

    public init(configurationURL: URL = ConfigurationStore.defaultURL,
                contentLibraryURL: URL = SnippetStore.defaultURL,
                backupsURL: URL? = nil) {
        self.init(configurationURL: configurationURL, contentLibraryURL: contentLibraryURL,
                  backupsURL: backupsURL ?? configurationURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true),
                  writeFile: { data, url in try data.write(to: url, options: .atomic) })
    }

    init(configurationURL: URL, contentLibraryURL: URL, backupsURL: URL,
         writeFile: @escaping @Sendable (Data, URL) throws -> Void) {
        self.configurationURL = configurationURL
        self.contentLibraryURL = contentLibraryURL
        self.backupsURL = backupsURL
        self.writeFile = writeFile
    }

    public func currentArchive() throws -> ConfigurationArchive {
        try ConfigurationArchive(configuration: ConfigurationStore(url: configurationURL).load(),
                                 contentLibrary: SnippetStore(url: contentLibraryURL).load())
    }

    public func export(to url: URL) throws {
        let data = try currentArchive().encoded()
        // Do not let a user-selected export destination bypass the protected live-file validation.
        guard try !aliasesLiveFile(url, liveURL: configurationURL),
              try !aliasesLiveFile(url, liveURL: contentLibraryURL) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "请将备份导出到其他文件，不能覆盖正在使用的数据文件。"])
        }
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public func makeBackup() throws -> URL { try saveBackup(currentArchive()) }

    public func backups() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: backupsURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
            .filter { $0.pathExtension.lowercased() == "json" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// The caller must show a replacement preview and obtain explicit confirmation before calling.
    @discardableResult
    public func restore(_ archive: ConfigurationArchive) throws -> URL {
        try archive.validate()
        let current = try currentArchive()
        let oldConfiguration = try existingData(at: configurationURL)
        let oldLibrary = try existingData(at: contentLibraryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configurationData = try encoder.encode(archive.configuration)
        let libraryData = try encoder.encode(archive.contentLibrary)
        let backup = try saveBackup(current)
        do {
            for url in [configurationURL, contentLibraryURL] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try writeFile(configurationData, configurationURL)
            try writeFile(libraryData, contentLibraryURL)
        } catch {
            let original = error
            // Attempt both rollbacks even if one fails, preserving as much as possible.
            var rollbackErrors: [String] = []
            for (url, data) in [(configurationURL, oldConfiguration), (contentLibraryURL, oldLibrary)] {
                do { try restoreBytes(data, at: url) }
                catch { rollbackErrors.append(error.localizedDescription) }
            }
            if !rollbackErrors.isEmpty {
                throw ConfigurationArchiveError.rollbackFailed(original: original.localizedDescription,
                                                               rollback: rollbackErrors.joined(separator: "\n"))
            }
            throw original
        }
        return backup
    }

    private func saveBackup(_ archive: ConfigurationArchive) throws -> URL {
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupsURL.appendingPathComponent("T-Cube-\(timestamp)-\(UUID().uuidString.prefix(8)).json")
        try archive.encoded().write(to: url, options: .atomic)
        return url
    }

    private func aliasesLiveFile(_ destination: URL, liveURL: URL) throws -> Bool {
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        let liveURL = liveURL.resolvingSymlinksInPath().standardizedFileURL
        if destination == liveURL { return true }
        // Resource identity catches hard links and case aliases on an existing live file.
        if try sameFileResource(destination, liveURL) { return true }

        // A missing live file still needs protection: compare the containing directory's identity
        // and the volume's case rules before allowing an archive to be created at that location.
        let destinationParent = destination.deletingLastPathComponent()
        let liveParent = liveURL.deletingLastPathComponent()
        guard try (destinationParent == liveParent || sameFileResource(destinationParent, liveParent)) else { return false }
        if destination.lastPathComponent == liveURL.lastPathComponent { return true }
        let volume = try liveParent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return volume.volumeSupportsCaseSensitiveNames == false &&
            destination.lastPathComponent.caseInsensitiveCompare(liveURL.lastPathComponent) == .orderedSame
    }

    private func sameFileResource(_ first: URL, _ second: URL) throws -> Bool {
        do {
            let firstID = try first.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            let secondID = try second.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            guard let firstID, let secondID else { return false }
            return firstID.isEqual(secondID)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
    }

    private func existingData(at url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func restoreBytes(_ data: Data?, at url: URL) throws {
        if let data { try data.write(to: url, options: .atomic) }
        else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
