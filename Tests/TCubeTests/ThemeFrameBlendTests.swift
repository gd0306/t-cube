import AppKit
import Testing
@testable import TCube

@MainActor
struct ThemeFrameBlendTests {
    private func frame(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).setFill()
            rect.fill(using: .copy)
            return true
        }
    }

    private func pixel(_ image: NSImage) throws -> (Double, Double, Double, Double) {
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let space = try #require(CGColorSpace(name: CGColorSpace.linearSRGB).flatMap(NSColorSpace.init(cgColorSpace:)))
        let color = try #require(bitmap.colorAt(x: 4, y: 4)?.usingColorSpace(space))
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    @Test func transparentHighlightsNeverBecomeBrighterThanBothEndpoints() throws {
        let first = frame(red: 0.9, green: 0.5, blue: 0.15, alpha: 0.28)
        let second = frame(red: 0.1, green: 0.4, blue: 0.9, alpha: 0.18)
        let a = try pixel(first), b = try pixel(second)
        for step in 1..<10 {
            let image = try #require(ThemeFrameBlend.image(from: first, to: second, progress: Double(step) / 10))
            let mixed = try pixel(image)
            #expect(mixed.3 <= max(a.3, b.3) + 0.005)
            for background in [0.0, 1.0] {
                let luma = { (p: (Double,Double,Double,Double)) in
                    (0.2126 * p.0 + 0.7152 * p.1 + 0.0722 * p.2) * p.3 + background * (1 - p.3)
                }
                #expect(luma(mixed) <= max(luma(a),luma(b)) + 0.01)
            }
        }
    }

    @Test func transparentRGBDoesNotLeakIntoTheFadeAndEndpointsStayExact() throws {
        let empty = frame(red: 1, green: 1, blue: 1, alpha: 0)
        let black = frame(red: 0, green: 0, blue: 0, alpha: 0.5)
        let midpoint = try pixel(#require(ThemeFrameBlend.image(from: empty, to: black, progress: 0.5)))
        #expect(midpoint.0 * midpoint.3 < 0.005)
        #expect(abs(midpoint.3 - 0.25) < 0.01)
        #expect(ThemeFrameBlend.image(from: empty, to: black, progress: 0) === empty)
        #expect(ThemeFrameBlend.image(from: empty, to: black, progress: 1) === black)
    }
}
