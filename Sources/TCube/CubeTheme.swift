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

    static func faceImage(group: FaceGroup, ordinal: Int, appearance: CubeAppearance = CubeAppearance()) -> CGImage? {
        let size = NSSize(width: FaceLayout.textureSize, height: FaceLayout.textureSize)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill(using: .copy)
            // All six faces draw icons only; empty slots and surrounding pixels stay clear.
            for slot in 0..<4 {
                if let item = group.slots[slot] {
                    LauncherService.icon(for: item).draw(in: FaceLayout.iconRect(slot), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                }
            }
            return true
        }
        guard let rendered = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard group.slots.contains(where: { $0 != nil }) else { return rendered }
        return IconTexture.preparedImage(from: rendered)
    }
}
