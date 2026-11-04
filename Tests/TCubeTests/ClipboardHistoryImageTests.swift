import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardHistoryImageTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_CLIPBOARD_PREVIEWS"] == "1"))
    func nativeTextMergeAndImageCategoriesRenderWithOwnedFixtures() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCube-Clipboard-Preview-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        defer { model.shutdown() }
        model.enable()
        for text in ["  会议记录  \n\n\n  整理本周工作与下周计划。  ", "  项目进度  \n  完成桌面自动隐藏与剪贴板工具。  "] {
            board.clearContents()
            #expect(board.setString(text, forType: .string))
            model.poll()
        }
        board.clearContents()
        #expect(board.setData(try imageFixture(type: .png, width: 1200, height: 700), forType: .png))
        model.poll()
        try await waitForClipboardFixture { model.images.count == 1 }
        let image = try #require(model.images.first)
        let selectedIDs = Set(model.entries.map(\.id))
        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/desktop-clipboard-verification")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (theme, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua),
                                             ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)] {
            for category in ClipboardHistoryView.Category.allCases {
                let view = ClipboardHistoryView(model: model, isActive: true, libraryStatus: "", canSave: true,
                    useText: { _, _ in }, useImage: { _, _ in }, saveText: { _ in },
                    category: category, selectedIDs: selectedIDs, selectedImageID: image.id,
                    trimLines: true, collapseBlankLines: true)
                let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
                let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 920, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.appearance = NSAppearance(named: appearance)
                panel.contentView = hosting
                panel.orderFrontRegardless()
                defer { panel.orderOut(nil); panel.contentView = nil }
                try await Task.sleep(for: .milliseconds(300))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let categoryName = category == .text ? "text" : "image"
                let filename = theme == "light" ? "clipboard-\(categoryName)-preview.png" : "clipboard-\(categoryName)-dark.png"
                try data.write(to: outputDirectory.appendingPathComponent(filename))
            }
        }
        #expect(model.entries.count == 2)
        #expect(model.images.count == 1)
    }

    @Test func nativePNGAndTIFFNormalizeWithBoundedThumbnailAndPreview() throws {
        for type in [UTType.png, UTType.tiff] {
            let input = try imageFixture(type: type, width: 1200, height: 600)
            let image = try #require(ClipboardHistoryImageCodec.normalize(input))
            #expect(image.width == 1200)
            #expect(image.height == 600)
            let source = try #require(CGImageSourceCreateWithData(image.pngData as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
            let thumbnail = try #require(ClipboardHistoryImageCodec.preview(image.thumbnailPNG, maximumPixelSize: 160))
            #expect(thumbnail.width == 160)
            #expect(thumbnail.height == 80)
            let preview = try #require(ClipboardHistoryImageCodec.preview(image.pngData, maximumPixelSize: 1024))
            #expect(preview.width == 1024)
            #expect(preview.height == 512)
        }
    }

    @Test func malformedOversizeAndExcessivePixelImagesAreRejected() throws {
        #expect(ClipboardHistoryImageCodec.normalize(Data([0, 1, 2])) == nil)
        #expect(ClipboardHistoryImageCodec.normalize(Data(repeating: 0, count: 8 * 1024 * 1024 + 1)) == nil)
        let excessive = try imageFixture(type: .png, width: 4001, height: 4000)
        #expect(ClipboardHistoryImageCodec.normalize(excessive) == nil)
    }

    @Test func imageReadsRespectPrivacyBaselineAndEveryInFlightInvalidation() async throws {
        let source = ImageHistoryReaderFixture(data: try imageFixture(type: .png, width: 24, height: 12))
        var images: [ClipboardHistoryImagePayload] = []
        let recorder = ClipboardHistoryRecorder(reader: source, schedule: nil, receivedImage: { images.append($0) }) { _ in }
        recorder.start()
        recorder.poll()
        #expect(source.imageReads == 0)
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "public.file-url", "NSFilenamesPboardType"] {
            source.types = [.png, .init(marker)]
            source.changeCount += 1
            recorder.poll()
        }
        #expect(source.imageReads == 0)
        source.types = [.png]
        source.changeCount += 1
        source.afterRead = { recorder.markSelfWrite() }
        recorder.poll()
        #expect(images.isEmpty)
        source.afterRead = { recorder.stop(); recorder.start() }
        source.changeCount += 1
        recorder.poll()
        #expect(images.isEmpty)
        source.afterRead = { source.changeCount += 1 }
        source.changeCount += 1
        recorder.poll()
        #expect(images.isEmpty)
        source.afterRead = nil
        recorder.poll()
        try await waitForClipboardFixture { images.count == 1 }
        #expect(images.count == 1)
        #expect(images.first?.width == 24)
        let previousReads = source.imageReads
        for _ in 0..<100 { recorder.poll() }
        #expect(source.imageReads == previousReads)
        source.changeCount += 1
        recorder.markSelfWrite()
        recorder.poll()
        #expect(images.count == 1)
    }

    @Test func oversizedNativeImageReportsSkippedInputInsteadOfClaimingCapture() {
        let board = NSPasteboard(name: .init("TCube-Oversize-Image-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        defer { model.shutdown() }
        model.enable()
        board.clearContents()
        #expect(board.setString("retained text", forType: .string))
        model.poll()
        board.clearContents()
        #expect(board.setData(Data(repeating: 0, count: 8 * 1024 * 1024 + 1), forType: .tiff))
        model.poll()
        #expect(model.images.isEmpty)
        #expect(model.entries.map(\.text) == ["retained text"])
        #expect(model.status.contains("已跳过"))
        #expect(model.status.contains("8 MiB"))
    }

    @Test func clearingOneCategoryPreservesOtherCategoryPendingCapture() async throws {
        let board = NSPasteboard(name: .init("TCube-Scoped-Clear-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        defer { model.shutdown() }
        model.enable()
        board.clearContents()
        #expect(board.setString("clear this text", forType: .string))
        model.poll()
        let png = try imageFixture(type: .png, width: 36, height: 18)
        board.clearContents()
        #expect(board.setData(png, forType: .png))
        model.poll()
        model.clearText()
        try await waitForClipboardFixture { model.images.count == 1 }
        #expect(model.entries.isEmpty)
        #expect(model.images.first?.width == 36)
        board.clearContents()
        #expect(board.setString("preserve pending text", forType: .string))
        model.clearImages()
        model.poll()
        #expect(model.images.isEmpty)
        #expect(model.entries.map(\.text) == ["preserve pending text"])
        board.clearContents()
        #expect(board.setData(png, forType: .png))
        model.poll()
        model.clearImages()
        try await Task.sleep(for: .milliseconds(40))
        #expect(model.images.isEmpty)
        #expect(model.entries.map(\.text) == ["preserve pending text"])
    }

    @Test func pendingImageWorkKeepsOnlyNewestAndClearCancelsUndeliveredImages() async throws {
        let source = ImageHistoryReaderFixture(data: try imageFixture(type: .png, width: 20, height: 10))
        var captured: [ClipboardHistoryImagePayload] = []
        let recorder = ClipboardHistoryRecorder(reader: source, schedule: nil, receivedImage: { captured.append($0) }) { _ in }
        recorder.start()
        source.changeCount += 1
        recorder.poll()
        source.data = try imageFixture(type: .png, width: 30, height: 15)
        source.changeCount += 1
        recorder.poll()
        try await waitForClipboardFixture { captured.count == 1 }
        #expect(captured.map(\.width) == [30])
        source.data = try imageFixture(type: .png, width: 40, height: 20)
        source.changeCount += 1
        recorder.poll()
        recorder.markSelfWrite()
        try await Task.sleep(for: .milliseconds(40))
        #expect(captured.map(\.width) == [30])
        source.changeCount += 1
        recorder.poll()
        recorder.stop()
        try await Task.sleep(for: .milliseconds(40))
        #expect(captured.map(\.width) == [30])
    }

    @Test func namedPasteboardImageCopyDoesNotReingestAndClearScopesAreIndependent() async throws {
        let board = NSPasteboard(name: .init("TCube-Image-Test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let controller = SnippetLibraryController(pasteboard: board, history: model,
            model: SnippetLibraryModel(store: SnippetStore(url: directory.appendingPathComponent("content.json"))))
        defer { controller.stop() }
        model.enable()
        board.clearContents()
        #expect(board.setString("text remains", forType: .string))
        model.poll()
        board.clearContents()
        #expect(board.setData(try imageFixture(type: .tiff, width: 32, height: 16), forType: .tiff))
        model.poll()
        try await waitForClipboardFixture { model.images.count == 1 }
        let recorded = try #require(model.images.first)
        controller.useImage(recorded, paste: false)
        #expect(board.data(forType: .png) == recorded.pngData)
        model.poll()
        #expect(model.images.count == 1)
        model.clearImages()
        #expect(model.images.isEmpty)
        #expect(model.entries.map(\.text) == ["text remains"])
        board.clearContents()
        #expect(board.setData(recorded.pngData, forType: .png))
        model.poll()
        try await waitForClipboardFixture { model.images.count == 1 }
        model.clearText()
        #expect(model.entries.isEmpty)
        #expect(model.images.count == 1)
        model.shutdown()
        #expect(model.images.isEmpty)
        #expect(model.totalImageBytes == 0)
    }
}

@MainActor
private final class ImageHistoryReaderFixture: ClipboardHistoryReading {
    var changeCount = 0
    var types: [NSPasteboard.PasteboardType] = [.png]
    var data: Data
    var afterRead: (() -> Void)?
    var imageReads = 0
    init(data: Data) { self.data = data }
    var advertisedTypes: [NSPasteboard.PasteboardType] { types }
    func readText() -> String? { nil }
    func readImageData(for type: NSPasteboard.PasteboardType) -> Data? {
        imageReads += 1
        afterRead?()
        return data
    }
}

private func imageFixture(type: UTType, width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.6))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@MainActor
private func waitForClipboardFixture(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Owned clipboard fixture processing timed out")
}
