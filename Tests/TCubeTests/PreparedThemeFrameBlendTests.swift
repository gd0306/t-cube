import AppKit
import Testing
@testable import TCube

@MainActor
struct PreparedThemeFrameBlendTests {
    private func frame(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            rect.fill(using: .copy)
            return true
        }
    }

    private func sample(_ image: NSImage) throws -> [CGFloat] {
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let color = try #require(bitmap.colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB))
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }

    @Test func preparedBlendReusesContextWithoutChangingEarlierFrames() throws {
        let source = frame(NSColor.red.withAlphaComponent(0.3))
        let target = frame(NSColor.blue.withAlphaComponent(0.2))
        let blend = try #require(ThemeFrameBlend.Prepared(from: source, to: target))
        #expect(blend.image(progress: 0) === source)
        #expect(blend.image(progress: 1) === target)
        let first = try #require(blend.image(progress: 0.25))
        let expected = try sample(first)
        let second = try #require(blend.image(progress: 0.75))
        #expect(try sample(first) == expected)
        #expect(try sample(second) != expected)
        let standalone = try #require(ThemeFrameBlend.image(from: source, to: target, progress: 0.75))
        #expect(try sample(second) == sample(standalone))
    }
}
