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
            // These are launcher labels, not a glass surface. Every pixel between
            // icons and labels stays clear, including the centre of the face.
            func label(_ string: String, rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = .byTruncatingTail
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.78)
                shadow.shadowBlurRadius = 5
                shadow.shadowOffset = NSSize(width: 0, height: 2)
                (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph, .shadow: shadow, .strokeColor: NSColor(white: 0, alpha: 0.48), .strokeWidth: -3])
            }
            label(group.name, rect: NSRect(x: 90, y: 64, width: 844, height: 104), size: 80, color: text, weight: .semibold, alignment: .center)
            for slot in 0..<4 {
                let rect = FaceLayout.slotRect(slot)
                if let item = group.slots[slot] {
                    LauncherService.icon(for: item).draw(in: NSRect(x: rect.midX - 108, y: rect.minY + 6, width: 216, height: 216), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                    label(item.name, rect: NSRect(x: rect.minX + 6, y: rect.minY + 236, width: rect.width - 12, height: 86), size: 62, color: text, weight: .medium, alignment: .center)
                } else {
                    let centre = NSPoint(x: rect.midX, y: rect.minY + 132)
                    label("+", rect: NSRect(x: centre.x - 46, y: centre.y - 60, width: 92, height: 110), size: 82, color: muted, weight: .light, alignment: .center)
                }
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
