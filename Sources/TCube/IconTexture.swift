import CoreGraphics
import Foundation

/// Straight-alpha texels with color padding for GPU filtering and mipmaps.
/// Coverage is unchanged; only invisible RGB around the icon is extended.
enum IconTexture {
    static func preparedImage(from source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var distance = [UInt8](repeating: 255, count: width * height)
        var queue: [Int] = []
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else { continue }
            if alpha < 255 {
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(min(255, (Int(pixels[offset + channel]) * 255 + alpha / 2) / alpha))
                }
            }
            distance[index] = 0
            let x = index % width, y = index / width
            if (x > 0 && pixels[(index - 1) * 4 + 3] == 0) ||
                (x + 1 < width && pixels[(index + 1) * 4 + 3] == 0) ||
                (y > 0 && pixels[(index - width) * 4 + 3] == 0) ||
                (y + 1 < height && pixels[(index + width) * 4 + 3] == 0) {
                queue.append(index)
            }
        }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            guard distance[index] < 16 else { continue }
            let x = index % width, y = index / width
            for neighbor in [x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1,
                             y > 0 ? index - width : -1, y + 1 < height ? index + width : -1] {
                guard neighbor >= 0, distance[neighbor] == 255 else { continue }
                distance[neighbor] = distance[index] + 1
                for channel in 0..<3 { pixels[neighbor * 4 + channel] = pixels[index * 4 + channel] }
                queue.append(neighbor)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
