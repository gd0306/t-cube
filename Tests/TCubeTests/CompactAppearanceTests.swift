import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct CompactAppearanceTests {
    @Test func faceBackgroundLetsTheDesktopShowThroughWhileContentStaysVisible() throws {
        let group = try FaceGroup(name: "常用")
        let image = try #require(CubeTheme.faceImage(group: group, ordinal: 0))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let background = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        #expect(background.alphaComponent == 0)
        var visibleContent = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.8 { visibleContent = true }
            }
        }
        #expect(visibleContent)
    }
}
