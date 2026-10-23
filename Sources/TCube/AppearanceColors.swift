import AppKit

extension NSColor {
    convenience init?(hexRGB: String) {
        guard hexRGB.utf8.count == 7, hexRGB.first == "#", let value = UInt32(hexRGB.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var hexRGB: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#65DEFF" }
        func byte(_ component: CGFloat) -> Int { Int((max(0, min(1, component)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
