import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ThemePresentationLifecycleTests {
    private func frame(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in color.setFill(); rect.fill(); return true }
    }
    private func fixture() throws -> (URL, AppModel, CubeView, NSPanel) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
        var config = CubeConfiguration(); config.autoRotatesWhenIdle = false
        try store.save(config)
        let model = AppModel(store: store), view = CubeView(model: model)
        view.idlePowerSavingEnabled = true
        let area = try #require(NSScreen.main?.visibleFrame)
        let window = NSPanel(contentRect: NSRect(x: area.minX+20,y: area.minY+20,width:164,height:164), styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        return (folder,model,view,window)
    }
    @Test func ordinaryResumeCannotDiscardPendingThemeAndOldCallbacksCannotReplaceNewerFrames() throws {
        let (folder,model,view,window) = try fixture()
        var captures: [(NSImage?) -> Void] = []
        let surface = CubeSurfaceView(cubeView:view,frameCapture:{captures.append($0)})
        window.contentView=surface; surface.enableRenderingManagement(); window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput:true)
        defer {window.orderOut(nil);window.contentView=nil;model.stopThemeCycle();try? FileManager.default.removeItem(at:folder)}
        model.change {$0.appearance=CubeThemePreset.ocean.appearance(glowIntensity:0.7)}
        view.refreshAppearance()
        #expect(captures.count==1)
        _ = surface.resumeRendering()
        captures[0](frame(.red))
        #expect(view.appliedAppearance==model.displayedAppearance,"A visibility/setting wake must not drop the selected appearance")
        view.advanceAnimations(deltaTime:0.1,reducedMotion:false)
        view.advanceAnimations(deltaTime:0.1,reducedMotion:false)
        guard captures.count>1 else {Issue.record("New theme frame was never requested");return}
        let stale=captures[1]
        model.change {$0.appearance=CubeThemePreset.forest.appearance(glowIntensity:0.7)}
        view.refreshAppearance()
        stale(frame(.blue))
        #expect(!surface.rendererDetached,"A stale completion must not detach a newer preparation")
        #expect(view.appliedAppearance != CubeThemePreset.ocean.appearance(glowIntensity:0.7) || surface.isThemeTransitioning)
    }
    @Test func failedSnapshotsKeepAVisibleUsableLiveSurface() async throws {
        let (folder,model,view,window) = try fixture()
        var captures: [(NSImage?) -> Void] = []
        let surface=CubeSurfaceView(cubeView:view,frameCapture:{captures.append($0)})
        window.contentView=surface;surface.enableRenderingManagement();window.orderFrontRegardless()
        _ = surface.resumeRendering(forInput:true)
        defer {window.orderOut(nil);window.contentView=nil;model.stopThemeCycle();try? FileManager.default.removeItem(at:folder)}
        let deadline=Date().addingTimeInterval(3)
        while captures.isEmpty && Date()<deadline {try await Task.sleep(for:.milliseconds(30))}
        guard let initial=captures.first else {Issue.record("Initial idle frame was not requested");return}
        initial(nil)
        #expect(view.window===window)
        #expect(view.alphaValue==1)
        #expect(!surface.rendererDetached)
        _ = surface.resumeRendering(forInput:true)
        model.change {$0.appearance=CubeThemePreset.ocean.appearance(glowIntensity:0.7)}
        view.refreshAppearance()
        let old=try #require(captures.last);old(frame(.red))
        view.advanceAnimations(deltaTime:0.1,reducedMotion:false)
        view.advanceAnimations(deltaTime:0.1,reducedMotion:false)
        let target=try #require(captures.last);target(nil)
        #expect(view.window===window)
        #expect(view.alphaValue==1)
        #expect(!surface.hasFrozenFrame)
        #expect(!surface.isThemeTransitioning)
    }
}
