import CoreGraphics
import Foundation
import Testing
@testable import TCube

struct IconTextureTests {
    @Test func rasterConversionPreservesBothImageAxes() throws {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                              0, 0, 255, 255, 0, 0, 0, 255]
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let source = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let result = try #require(IconTexture.preparedImage(from: source))
        let data = try #require(result.dataProvider?.data) as Data
        #expect([UInt8](data) == bytes)
    }

    @Test func transparentPaddingKeepsEdgeColorWithoutChangingCoverageOrOpaqueDarkDetails() throws {
        // Premultiplied red, half-covered white, transparent black, opaque black.
        let bytes: [UInt8] = [255, 0, 0, 255, 128, 128, 128, 128, 0, 0, 0, 0, 0, 0, 0, 255]
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let source = try #require(CGImage(width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let result = try #require(IconTexture.preparedImage(from: source))
        let data = try #require(result.dataProvider?.data) as Data
        let pixels = [UInt8](data)
        #expect(result.alphaInfo == .last)
        #expect(Array(pixels[0..<4]) == [255, 0, 0, 255])
        #expect(Array(pixels[4..<8]) == [255, 255, 255, 128])
        #expect(Array(pixels[8..<12]) == [255, 255, 255, 0])
        #expect(Array(pixels[12..<16]) == [0, 0, 0, 255])
    }
}
