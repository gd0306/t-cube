import Foundation
import Testing
import simd
@testable import CubeCore

struct WebsiteTitlePickingTests {
    @Test func captionHitsFollowWebsiteSlotsAcrossEveryRotatedFace() throws {
        var config = CubeConfiguration()
        for face in CubeFace.allCases {
            for index in 0..<4 {
                let item = index % 2 == 0
                    ? try WebsiteTarget.item(title: "网页 \(index)", address: "https://example.com/\(index)")
                    : LauncherItem(url: URL(fileURLWithPath: "/Applications/App\(index).app"), name: "App", kind: .application)
                try config.place(item, to: face, slot: index)
            }
        }
        let captions: [SIMD2<Float>] = [[-0.18785156, 0.01394531], [0.18785156, 0.01394531], [-0.18785156, -0.28957031], [0.18785156, -0.28957031]]
        for face in CubeFace.allCases {
            for (index, point) in captions.enumerated() {
                let target = face.orientation.act(FaceLayout.surfacePoint(at: point))
                let origin = face.orientation.act(SIMD3<Float>(0.8, 0.4, 3))
                let hit = CubeFacePicking.icon(origin: origin, direction: target - origin, configuration: config)
                if index % 2 == 0 { #expect(hit?.face == face && hit?.slot == index) }
                else { #expect(hit == nil) }
            }
        }
    }

    @Test func websiteArtworkUsesBoundedSingleLineNamesWithoutChangingOriginalTitles() throws {
        var item = try WebsiteTarget.item(title: "工作\n  文档\t👩🏽‍💻", address: "https://example.com")
        #expect(item.websiteDisplayTitle == "工作 文档 👩🏽‍💻")
        #expect(item.name == "工作\n  文档\t👩🏽‍💻")
        item.name = String(repeating: "👩🏽‍💻", count: 200)
        #expect(item.websiteDisplayTitle == String(repeating: "👩🏽‍💻", count: 120))
        item.kind = .application
        #expect(item.websiteDisplayTitle == nil)
    }
}
