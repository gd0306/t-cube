import AppKit
import CubeCore
import ImageIO
import UniformTypeIdentifiers

struct WebsiteIconResource: Sendable {
    let data: Data
    let url: URL
}

struct WebsiteIconFetcher: Sendable {
    let load: @Sendable (URL, Int) async -> WebsiteIconResource?
    init(load: @escaping @Sendable (URL, Int) async -> WebsiteIconResource? = { await WebsiteIconHTTP.load($0, limit: $1) }) {
        self.load = load
    }

    static func origin(for url: URL) -> URL? {
        guard WebsiteTarget.isValid(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.path = "/"; components.query = nil; components.fragment = nil
        if components.port == (components.scheme == "https" ? 443 : 80) { components.port = nil }
        return components.url
    }

    func icon(for url: URL) async -> Data? {
        guard let origin = Self.origin(for: url), !Task.isCancelled else { return nil }
        let fallback = origin.appendingPathComponent("favicon.ico")
        if let response = await load(fallback, 512 * 1024), let image = Self.raster(response.data) { return image }
        guard !Task.isCancelled, let page = await load(origin, 256 * 1024), page.data.count <= 256 * 1024,
              let html = String(data: page.data, encoding: .utf8) ?? String(data: page.data, encoding: .isoLatin1) else { return nil }
        for candidate in Self.declaredIcons(in: html, base: page.url).filter({ $0 != fallback }).prefix(2) {
            guard !Task.isCancelled else { return nil }
            if let response = await load(candidate, 512 * 1024), let image = Self.raster(response.data) { return image }
        }
        return nil
    }

    static func declaredIcons(in html: String, base: URL) -> [URL] {
        guard let tags = try? NSRegularExpression(pattern: #"<link\b[^>]{0,8192}>"#, options: .caseInsensitive),
              let attributes = try? NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s'"=<>`]+))"#) else { return [] }
        var result: [URL] = []
        var visibleHTML = "", cursor = html.startIndex
        while let start = html.range(of: "<!--", range: cursor..<html.endIndex) {
            visibleHTML += html[cursor..<start.lowerBound]
            guard let end = html.range(of: "-->", range: start.upperBound..<html.endIndex) else { cursor = html.endIndex; break }
            cursor = end.upperBound
        }
        visibleHTML += html[cursor...]
        let text = visibleHTML as NSString
        for match in tags.matches(in: visibleHTML, range: NSRange(location: 0, length: text.length)).prefix(64) {
            let tag = text.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for attr in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let key = tag.substring(with: attr.range(at: 1)).lowercased()
                if let range = (2...4).map({ attr.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                    values[key] = tag.substring(with: range)
                }
            }
            let roles = (values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard roles.contains("icon") || roles.contains("apple-touch-icon"),
                  let href = values["href"]?.replacingOccurrences(of: "&amp;", with: "&"),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL, WebsiteTarget.isValid(url),
                  base.scheme?.lowercased() != "https" || url.scheme?.lowercased() == "https",
                  !["svg", "svgz"].contains(url.pathExtension.lowercased()),
                  !(values["type"]?.lowercased().contains("svg") ?? false),
                  !result.contains(url) else { continue }
            result.append(url)
        }
        return result
    }

    /// Decode only supported raster formats, cap dimensions before decompression, and flatten to PNG.
    static func raster(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= 512 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) <= 64 else { return nil }
        var best: (index: Int, area: Int)?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 1024, height <= 1024 else { continue }
            if width * height > (best?.area ?? 0) { best = (index, width * height) }
        }
        guard let best, let image = CGImageSourceCreateThumbnailAtIndex(source, best.index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) else { return nil }
        let png = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, nil)
        return CGImageDestinationFinalize(output) ? png as Data : nil
    }
}

/// Rendering only reads this cache. Network work begins explicitly at app startup/configuration changes.
@MainActor final class WebsiteIconCache {
    static let shared = WebsiteIconCache { await WebsiteIconFetcher().icon(for: $0) }
    private let load: @Sendable (URL) async -> Data?
    private var images: [URL: NSImage] = [:]
    private var finished: Set<URL> = []
    private var active: Set<URL> = []
    private var queue: [URL] = []
    private var tasks: [URL: (UUID, Task<Void, Never>)] = [:]
    private(set) var revision = 0
    var onChange: (() -> Void)?

    init(load: @escaping @Sendable (URL) async -> Data?) { self.load = load }
    func image(for url: URL) -> NSImage? { WebsiteIconFetcher.origin(for: url).flatMap { images[$0] } }

    func update(items: [LauncherItem]) {
        active = Set(items.filter { $0.kind == .website }.compactMap { WebsiteIconFetcher.origin(for: $0.url) }.prefix(64))
        for (origin, running) in tasks where !active.contains(origin) { running.1.cancel(); tasks.removeValue(forKey: origin) }
        images = images.filter { active.contains($0.key) }
        finished.formIntersection(active)
        queue = active.filter { !finished.contains($0) && tasks[$0] == nil }.sorted { $0.absoluteString < $1.absoluteString }
        pump()
    }

    private func pump() {
        while tasks.count < 4, !queue.isEmpty {
            let origin = queue.removeFirst(), token = UUID(), load = load
            let task = Task { [weak self] in
                let data = await load(origin)
                guard let self, self.tasks[origin]?.0 == token else { return }
                self.tasks.removeValue(forKey: origin)
                if self.active.contains(origin) {
                    self.finished.insert(origin)
                    if let data, let image = NSImage(data: data) {
                        self.images[origin] = image
                        self.revision &+= 1
                        self.onChange?()
                    }
                }
                self.pump()
            }
            tasks[origin] = (token, task)
        }
    }
}
