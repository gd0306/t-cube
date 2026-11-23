import AppKit

@MainActor enum WebsiteTitleArtwork {
    /// A monochrome outline mark, drawn separately so the saved name and tooltip stay unchanged.
    static func draw(_ title: String, in rect: CGRect) {
        let font = NSFont.systemFont(ofSize: 54, weight: .semibold)
        let markSide: CGFloat = 44, gap: CGFloat = 8
        let width = min(rect.width - 16, (title as NSString).size(withAttributes: [.font: font]).width + markSide + gap)
        let x = rect.midX - width / 2
        let mark = CGRect(x: x, y: rect.midY - markSide / 2, width: markSide, height: markSide)
        NSColor.white.setStroke()
        let circle = NSBezierPath(ovalIn: mark.insetBy(dx: 2, dy: 2))
        circle.lineWidth = 3; circle.stroke()
        let meridian = NSBezierPath(ovalIn: mark.insetBy(dx: 13, dy: 2))
        meridian.lineWidth = 3; meridian.stroke()
        let equator = NSBezierPath()
        equator.move(to: NSPoint(x: mark.minX + 2, y: mark.midY))
        equator.line(to: NSPoint(x: mark.maxX - 2, y: mark.midY))
        equator.lineWidth = 3; equator.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: CGRect(x: mark.maxX + gap, y: rect.minY + 4,
                                           width: max(0, width - markSide - gap), height: rect.height - 8),
                                withAttributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
}
