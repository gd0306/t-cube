import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct CompactAppearanceTests {
    @Test func renamingGroupOrAppDoesNotChangeTheFaceArtwork() throws {
        var item = LauncherItem(url: URL(fileURLWithPath: "/Applications", isDirectory: true), name: "应用程序", kind: .folder)
        let first = try #require(CubeTheme.faceImage(group: FaceGroup(name: "常用", slots: [item, nil, nil, nil]), ordinal: 0)?.dataProvider?.data)
        item.name = "另一个名称"
        let renamed = try #require(CubeTheme.faceImage(group: FaceGroup(name: "工作", slots: [item, nil, nil, nil]), ordinal: 0)?.dataProvider?.data)
        #expect((first as Data) == (renamed as Data))
    }

    @Test func unconfiguredFaceHasNoGroupNameOrPlaceholderMarks() throws {
        let image = try #require(CubeTheme.faceImage(group: FaceGroup(name: "常用"), ordinal: 0))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var hasVisiblePixels = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0 {
                    hasVisiblePixels = true
                }
            }
        }
        #expect(!hasVisiblePixels)
    }

    @Test func faceBackgroundLetsTheDesktopShowThroughWhileContentStaysVisible() throws {
        let item = LauncherItem(url: URL(fileURLWithPath: "/Applications", isDirectory: true), name: "应用程序", kind: .folder)
        let group = try FaceGroup(name: "常用", slots: [item, nil, nil, nil])
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
