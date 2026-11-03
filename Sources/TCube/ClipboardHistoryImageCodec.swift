import AppKit
import CubeCore
import ImageIO
import UniformTypeIdentifiers

struct ClipboardHistoryImagePayload: Equatable, Sendable {
    let pngData: Data
    let thumbnailPNG: Data
    let width: Int
    let height: Int
}

/// Decodes only size-checked native PNG/TIFF and keeps no full-size decoded image.
enum ClipboardHistoryImageCodec {
    static let thumbnailPixelSize = 160
    static let previewPixelSize = 1024

    static func normalize(_ data: Data) -> ClipboardHistoryImagePayload? {
        guard !data.isEmpty, data.count <= ClipboardHistory.maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.tiff.identifier].contains(type),
              CGImageSourceGetCount(source) == 1,
              let dimensions = dimensions(source) else { return nil }
        // Inspect dimensions before requesting any decoded pixels. Orientation is
        // applied while rendering, so normalized PNG has no source metadata.
        guard let image = thumbnail(source, maximumPixelSize: max(dimensions.width, dimensions.height)),
              let png = encodePNG(image), png.count <= ClipboardHistory.maximumImageBytes,
              let small = thumbnail(source, maximumPixelSize: thumbnailPixelSize),
              let thumbnailPNG = encodePNG(small), thumbnailPNG.count <= ClipboardHistory.maximumThumbnailBytes else { return nil }
        return ClipboardHistoryImagePayload(pngData: png, thumbnailPNG: thumbnailPNG, width: image.width, height: image.height)
    }

    static func preview(_ data: Data, maximumPixelSize: Int = previewPixelSize) -> CGImage? {
        guard maximumPixelSize > 0, maximumPixelSize <= previewPixelSize,
              data.count <= ClipboardHistory.maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              dimensions(source) != nil else { return nil }
        return thumbnail(source, maximumPixelSize: maximumPixelSize)
    }

    private static func dimensions(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= ClipboardHistory.maximumImagePixels / height else { return nil }
        return (width, height)
    }

    private static func thumbnail(_ source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return bytes as Data
    }
}

/// Serializes expensive image work across capture and selected preview. Jobs that
/// were superseded while waiting do not decode, and no work runs on MainActor.
actor ClipboardHistoryImageProcessor {
    static let shared = ClipboardHistoryImageProcessor()

    func normalize(_ data: Data) -> ClipboardHistoryImagePayload? {
        guard !Task.isCancelled else { return nil }
        let image = autoreleasepool { ClipboardHistoryImageCodec.normalize(data) }
        return Task.isCancelled ? nil : image
    }

    func preview(_ data: Data) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let image = autoreleasepool { ClipboardHistoryImageCodec.preview(data) }
        return Task.isCancelled ? nil : image
    }
}
