import AppKit
import RealityKit
import CubeCore

@MainActor
enum CubeTheme {
    static let windowSize = NSSize(width: 164, height: 164)
    static let body = NSColor.clear
    static let edge = NSColor(calibratedWhite: 1, alpha: 0.38)
    static let edgeShadow = NSColor(calibratedWhite: 0.08, alpha: 0.36)
    static let text = NSColor(calibratedWhite: 1, alpha: 0.96)
    static let muted = NSColor(calibratedWhite: 1, alpha: 0.58)
    static let bodyCorner: Float = 0.025

    /// The ordered icon sources are the only configuration values painted in a face.
    /// Display names and appearance settings must not invalidate its texture.
    struct FaceArtwork: Equatable {
        struct IconSource: Equatable {
            let url: URL
            let kind: LauncherItem.Kind
            let bookmark: Data?
        }

        let slots: [IconSource?]
        var isEmpty: Bool { slots.allSatisfy { $0 == nil } }

        init(group: FaceGroup) {
            slots = group.slots.map { item in
                item.map { IconSource(url: $0.url, kind: $0.kind,
                                      bookmark: $0.kind.isLocal ? $0.bookmark : nil) }
            }
        }
    }

    static func faceImage(group: FaceGroup, ordinal: Int, appearance: CubeAppearance = CubeAppearance()) -> CGImage? {
        // Use layout pixels directly. NSImage's logical size otherwise creates
        // a 2048-pixel atlas on Retina displays despite the 1024-pixel layout.
        let side = Int(FaceLayout.textureSize)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        // All six faces draw icons only; empty slots and surrounding pixels stay clear.
        for slot in 0..<4 {
            if let item = group.slots[slot] {
                LauncherService.icon(for: item).draw(in: FaceLayout.iconRect(slot), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }
        guard let rendered = context.makeImage() else { return nil }
        guard group.slots.contains(where: { $0 != nil }) else { return rendered }
        return IconTexture.preparedImage(from: rendered)
    }
}
