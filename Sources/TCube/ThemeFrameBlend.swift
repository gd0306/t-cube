import AppKit

/// Blend premultiplied pixels into one surface; transparent highlights never add.
@MainActor
enum ThemeFrameBlend {
    static let duration: TimeInterval = 0.4

    static func image(from source: NSImage, to target: NSImage, progress: Double) -> NSImage? {
        let amount = progress.isFinite ? min(1, max(0, progress)) : 1
        if amount == 0 { return source }
        if amount == 1 { return target }
        guard let first = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let second = target.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(data: nil, width: second.width, height: second.height,
                                      bitsPerComponent: 8, bytesPerRow: second.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: second.width, height: second.height)
        let eased = amount * amount * (3 - 2 * amount)
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.setAlpha(1 - eased)
        context.draw(first, in: rect)
        context.setBlendMode(.plusLighter)
        context.setAlpha(eased)
        context.draw(second, in: rect)
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: target.size)
    }
}
