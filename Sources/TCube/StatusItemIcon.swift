import AppKit

/// The app icon's three rounded faces, redrawn for an 18-point monochrome menu-bar mask.
@MainActor
enum StatusItemIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 18, y: rect.height / 18)
            let faces: [([CGPoint], CGFloat)] = [
                ([CGPoint(x: 9, y: 16.8), CGPoint(x: 16.1, y: 12.6),
                  CGPoint(x: 9, y: 8.5), CGPoint(x: 1.9, y: 12.6)], 1),
                ([CGPoint(x: 1.5, y: 11.4), CGPoint(x: 8.2, y: 7.5),
                  CGPoint(x: 8.2, y: 0.8), CGPoint(x: 1.5, y: 4.7)], 0.72),
                ([CGPoint(x: 9.8, y: 7.5), CGPoint(x: 16.5, y: 11.4),
                  CGPoint(x: 16.5, y: 4.7), CGPoint(x: 9.8, y: 0.8)], 0.9)
            ]
            for (points, opacity) in faces {
                context.addPath(roundedFace(points))
                context.setFillColor(CGColor(gray: 0, alpha: opacity))
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "T-Cube"
        return image
    }

    nonisolated private static func roundedFace(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        for index in points.indices {
            let point = points[index]
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            func inset(toward other: CGPoint) -> CGPoint {
                let length = hypot(other.x - point.x, other.y - point.y)
                let fraction = min(0.5, 0.7 / length)
                return CGPoint(x: point.x + (other.x - point.x) * fraction,
                               y: point.y + (other.y - point.y) * fraction)
            }
            let entry = inset(toward: previous), exit = inset(toward: next)
            if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: point)
        }
        path.closeSubpath()
        return path
    }
}
