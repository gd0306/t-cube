import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct WebsiteTitleTests {
    @Test func webpageCaptionsArePaintedBelowIconsAndNamesInvalidateOnlyWebsiteArtwork() throws {
        let item = try WebsiteTarget.item(title: "工作仓库", address: "https://example.com/work")
        var renamed = item; renamed.name = "个人仓库"
        let first = try FaceGroup(name: "网页", slots: [item, nil, nil, nil])
        let second = try FaceGroup(name: "网页", slots: [renamed, nil, nil, nil])
        #expect(CubeTheme.FaceArtwork(group: first) != CubeTheme.FaceArtwork(group: second))
        let image = try #require(CubeTheme.faceImage(group: first, ordinal: 0))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var painted = 0
        var whiteGlyphs = 0
        for y in stride(from: 462, to: 526, by: 4) {
            for x in stride(from: 110, to: 454, by: 4) {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    if pixel.alphaComponent > 0.1 { painted += 1 }
                    if pixel.alphaComponent > 0.8 && min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.85 { whiteGlyphs += 1 }
                }
            }
        }
        #expect(painted > 100, "The website name must be visible below the globe, inside the caption hit region")
        #expect(whiteGlyphs > 20, "The title glyphs must be visible, not just their background")
        let renamedImage = try #require(CubeTheme.faceImage(group: second, ordinal: 0)?.dataProvider?.data)
        #expect((try #require(image.dataProvider?.data) as Data) != (renamedImage as Data))
        var app = item; app.kind = .application; app.url = URL(fileURLWithPath: "/Applications/Test.app")
        var renamedApp = app; renamedApp.name = "Renamed"
        #expect(CubeTheme.FaceArtwork(group: try FaceGroup(name: "Apps", slots: [app, nil, nil, nil])) ==
                CubeTheme.FaceArtwork(group: try FaceGroup(name: "Apps", slots: [renamedApp, nil, nil, nil])))
    }
}
