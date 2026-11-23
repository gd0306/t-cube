import AppKit
import CubeCore
import Testing
@testable import TCube

private func faviconPNG() -> Data {
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

struct WebsiteIconTests {
    @Test func loadsTheOriginIconWithoutSendingTheSavedPageQuery() async throws {
        let png = faviconPNG()
        let fetcher = WebsiteIconFetcher { url, _ in
            guard url.absoluteString == "https://example.test/favicon.ico" else { return nil }
            return WebsiteIconResource(data: png, url: url)
        }
        let result = try #require(await fetcher.icon(for: URL(string: "https://example.test/account?token=private#tab")!))
        let decoded = try #require(NSBitmapImageRep(data: result))
        let pixel = try #require(decoded.colorAt(x: 8, y: 8)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent > 0.8 && pixel.greenComponent < 0.5)
    }

    @Test func discoversDeclaredIconAfterTheDefaultIconIsInvalid() async throws {
        let png = faviconPNG()
        let fetcher = WebsiteIconFetcher { url, _ in
            switch url.absoluteString {
            case "https://example.test/favicon.ico": WebsiteIconResource(data: Data("not an image".utf8), url: url)
            case "https://example.test/": WebsiteIconResource(data: Data("<link href='/brand/site.png?v=1&amp;size=32' REL='shortcut icon'>".utf8), url: url)
            case "https://example.test/brand/site.png?v=1&size=32": WebsiteIconResource(data: png, url: url)
            default: nil
            }
        }
        #expect(await fetcher.icon(for: URL(string: "https://example.test/page")!) != nil)
    }

    @Test func skipsCommentedAndUnsupportedIconsSoARealPNGCanBeFound() async {
        let png = faviconPNG()
        let fetcher = WebsiteIconFetcher { url, _ in
            if url.path == "/" {
                let html = "<!-- <link rel='icon' href='/removed.png'> --><link rel='icon' href='/vector.svg' type='image/svg+xml'><link rel='apple-touch-icon' href='/live.png'>"
                return WebsiteIconResource(data: Data(html.utf8), url: url)
            }
            return url.path == "/live.png" ? WebsiteIconResource(data: png, url: url) : nil
        }
        #expect(await fetcher.icon(for: URL(string: "https://example.test/")!) != nil)
    }

    @Test func invalidOrOversizedImagesKeepTheExistingFallback() async {
        let fetcher = WebsiteIconFetcher { url, _ in WebsiteIconResource(data: Data(repeating: 0, count: 600_000), url: url) }
        #expect(await fetcher.icon(for: URL(string: "https://example.test")!) == nil)
        #expect(await fetcher.icon(for: URL(string: "file:///private/test")!) == nil)
        #expect(await fetcher.icon(for: URL(string: "https://user:password@example.test")!) == nil)
    }

    @MainActor @Test func aLoadedIconRefreshesArtworkWithoutChangingSavedConfiguration() async throws {
        let png = faviconPNG()
        let cache = WebsiteIconCache { _ in png }
        let item = try WebsiteTarget.item(title: "狗狗加速", address: "https://example.test/account")
        #expect(cache.image(for: item.url) == nil)
        cache.update(items: [item])
        for _ in 0..<100 where cache.image(for: item.url) == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(cache.image(for: item.url) != nil)
        #expect(cache.revision > 0)
        #expect(item.name == "狗狗加速")
        cache.update(items: [])
        #expect(cache.image(for: item.url) == nil)
    }
}
