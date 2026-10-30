import AppKit
import CubeCore
import RealityKit
import Testing
@testable import TCube

@MainActor
struct FaceTextureReuseTests {
    @Test func faceRasterIs1024PixelsAndAlignsWithEverySharedIconHitRectangle() throws {
        for slot in 0..<4 {
            var slots = [LauncherItem?](repeating: nil, count: 4)
            slots[slot] = SystemSettingsTarget.sound.item
            let image = try #require(CubeTheme.faceImage(group: FaceGroup(name: "布局", slots: slots), ordinal: 0))
            #expect(image.width == 1024 && image.height == 1024)
            guard image.width == 1024 && image.height == 1024 else { continue }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let bounds = FaceLayout.iconRect(slot)
            var visible = 0
            for y in stride(from: 0, to: image.height, by: 4) {
                for x in stride(from: 0, to: image.width, by: 4) {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                        visible += 1
                        #expect(bounds.contains(CGPoint(x: x, y: y)), "Slot \(slot) artwork must remain inside its shared hit rectangle")
                    }
                }
            }
            #expect(visible > 100)
        }
    }

    @Test func unchangedRefreshesAndNonArtworkSettingsKeepTheExistingFaceTextures() throws {
        try withView { model, view, _ in
            let original = try textures(in: view)
            #expect(original.count == 2)
            #expect(original.values.allSatisfy { $0.width == 1024 && $0.height == 1024 })
            view.refreshTextures()
            try expectSameTextures(original, in: view)

            model.change { try $0.rename(.front, to: "重新命名的分组") }
            view.refreshTextures()
            try expectSameTextures(original, in: view)

            var renamed = try #require(model.configuration.group(for: .front).slots[0])
            renamed.name = "重新命名的入口"
            model.change { try $0.place(renamed, to: .front, slot: 0, replacing: true) }
            view.refreshTextures()
            try expectSameTextures(original, in: view)

            model.change {
                $0.appearance = CubeThemePreset.ocean.appearance(glowIntensity: 0.2)
                $0.hover = CubeHoverSettings(isEnabled: false, multiplier: 1.5, delaySeconds: 0.5)
                $0.expandsFacesOnClick = false
                $0.autoRotatesWhenIdle = false
            }
            view.refreshTextures()
            try expectSameTextures(original, in: view)
        }
    }

    @Test func addingReplacingMovingAndRemovingSlotsRefreshesOnlyTheEditedFace() throws {
        try withView { model, view, _ in
            var previous = try textures(in: view)
            let added = SystemSettingsTarget.sound.item
            model.change { try $0.place(added, to: .right, slot: 3) }
            view.refreshTextures()
            try expectOnlyChangedFace(.right, comparedTo: previous, in: view)
            previous = try textures(in: view)

            let replacement = SystemSettingsTarget.keyboard.item
            model.change { try $0.place(replacement, to: .front, slot: 0, replacing: true) }
            view.refreshTextures()
            try expectOnlyChangedFace(.front, comparedTo: previous, in: view)
            previous = try textures(in: view)

            model.change { try $0.move(in: .right, from: 3, to: 1) }
            view.refreshTextures()
            try expectOnlyChangedFace(.right, comparedTo: previous, in: view)
            previous = try textures(in: view)

            model.change { try $0.remove(from: .front, slot: 0) }
            view.refreshTextures()
            try expectOnlyChangedFace(.front, comparedTo: previous, in: view)
            previous = try textures(in: view)
            view.refreshTextures()
            try expectSameTextures(previous, in: view)
        }
    }

    @Test func emptyFacesHaveNoAtlasAndRemovingTheLastItemReleasesItsTexture() throws {
        try withView(populated: false) { model, view, _ in
            #expect(try textures(in: view).isEmpty)
            view.setHovered(true)
            for face in CubeFace.allCases {
                let panel = try #require(view.cube.children.first { $0.name == face.rawValue } as? ModelEntity)
                let material = try #require(panel.model?.materials.first as? UnlitMaterial)
                #expect(material.color.texture == nil)
                #expect(material.color.tint.alphaComponent == 0)
            }
            let added = SystemSettingsTarget.sound.item
            model.change { try $0.place(added, to: .front, slot: 2) }
            view.refreshTextures()
            let populated = try textures(in: view)
            #expect(populated.count == 1)
            let atlas = try #require(populated[.front])
            #expect(atlas.width == 1024 && atlas.height == 1024)
            model.change { try $0.remove(from: .front, slot: 2) }
            view.refreshTextures()
            #expect(try textures(in: view).isEmpty)
            let panel = try #require(view.cube.children.first { $0.name == CubeFace.front.rawValue } as? ModelEntity)
            let material = try #require(panel.model?.materials.first as? UnlitMaterial)
            #expect(material.color.tint.alphaComponent == 0)
        }
    }

    @Test func changingTargetURLKindOrBookmarkInvalidatesTheEditedFace() throws {
        try withView { model, view, directory in
            var item = try #require(model.configuration.group(for: .front).slots[0])
            var previous = try textures(in: view)
            item.url = URL(string: "https://example.org/changed")!
            model.change { try $0.place(item, to: .front, slot: 0, replacing: true) }
            view.refreshTextures()
            try expectOnlyChangedFace(.front, comparedTo: previous, in: view)
            previous = try textures(in: view)

            item.url = directory
            item.kind = .folder
            model.change { try $0.place(item, to: .front, slot: 0, replacing: true) }
            view.refreshTextures()
            try expectOnlyChangedFace(.front, comparedTo: previous, in: view)
            previous = try textures(in: view)

            let relinked = directory.appendingPathComponent("relinked", isDirectory: true)
            try FileManager.default.createDirectory(at: relinked, withIntermediateDirectories: true)
            item.bookmark = try relinked.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
            model.change { try $0.place(item, to: .front, slot: 0, replacing: true) }
            view.refreshTextures()
            try expectOnlyChangedFace(.front, comparedTo: previous, in: view)
        }
    }

    private func withView(populated: Bool = true, _ body: (AppModel, CubeView, URL) throws -> Void) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        var configuration = CubeConfiguration()
        for face in [CubeFace.front, .right] where populated {
            try configuration.add(WebsiteTarget.item(title: face.rawValue, address: "https://example.com/\(face.rawValue)"), to: face)
        }
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        let view = CubeView(model: model)
        defer { view.suspendAnimationUpdates() }
        try body(model, view, directory)
    }

    private func textures(in view: CubeView) throws -> [CubeFace: TextureResource] {
        try Dictionary(uniqueKeysWithValues: CubeFace.allCases.compactMap { face -> (CubeFace, TextureResource)? in
            let panel = try #require(view.cube.children.first { $0.name == face.rawValue } as? ModelEntity)
            let material = try #require(panel.model?.materials.first as? UnlitMaterial)
            return material.color.texture.map { (face, $0.resource) }
        })
    }

    private func expectSameTextures(_ expected: [CubeFace: TextureResource], in view: CubeView) throws {
        let actual = try textures(in: view)
        for face in CubeFace.allCases { #expect(actual[face] === expected[face], "\(face.rawValue) should reuse its live texture") }
    }

    private func expectOnlyChangedFace(_ edited: CubeFace, comparedTo previous: [CubeFace: TextureResource], in view: CubeView) throws {
        let actual = try textures(in: view)
        for face in CubeFace.allCases {
            if face == edited { #expect(actual[face] !== previous[face]) }
            else { #expect(actual[face] === previous[face], "Editing \(edited.rawValue) should preserve \(face.rawValue)") }
        }
    }
}
