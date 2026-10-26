import Foundation
import CoreGraphics

/// Texture coordinates and hit regions share one layout, measured from the top left.
public enum FaceLayout {
    public static let textureSize: CGFloat = 1024
    public static let panelSide: Float = 0.84
    public static let panelDistance: Float = 0.501
    public static func slotRect(_ index: Int) -> CGRect {
        CGRect(x: index % 2 == 0 ? 90 : 548, y: index < 2 ? 224 : 594, width: 386, height: 330)
    }
    /// The same painted icon rectangle is used for rendering and direct clicks.
    public static func iconRect(_ index: Int) -> CGRect {
        let slot = slotRect(index)
        return CGRect(x: slot.midX - 108, y: slot.minY + 6, width: 216, height: 216)
    }

    public static func iconSlot(at local: SIMD2<Float>) -> Int? {
        guard local.x.isFinite, local.y.isFinite else { return nil }
        let point = CGPoint(x: CGFloat(local.x / panelSide + 0.5) * textureSize,
                            y: CGFloat(0.5 - local.y / panelSide) * textureSize)
        return (0..<4).first { iconRect($0).contains(point) }
    }
    public static func slot(at local: SIMD2<Float>) -> Int? {
        guard local.x.isFinite, local.y.isFinite else { return nil }
        let point = CGPoint(x: CGFloat(local.x + 0.5) * textureSize, y: CGFloat(0.5 - local.y) * textureSize)
        return (0..<4).first { slotRect($0).contains(point) }
    }
}

public enum WindowPlacement {
    public static func clamp(_ origin: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint {
        guard !screens.isEmpty else { return origin }
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        func distance(_ rect: CGRect) -> CGFloat {
            let x = max(rect.minX, min(center.x, rect.maxX))
            let y = max(rect.minY, min(center.y, rect.maxY))
            return (center.x - x) * (center.x - x) + (center.y - y) * (center.y - y)
        }
        let screen = screens.min { distance($0) < distance($1) }!
        return CGPoint(x: max(screen.minX, min(origin.x, screen.maxX - size.width)),
                       y: max(screen.minY, min(origin.y, screen.maxY - size.height)))
    }
}

public enum LocalTargetError: Error, LocalizedError, Sendable {
    case unsupported, missing
    public var errorDescription: String? {
        switch self {
        case .unsupported: "请选择本地应用（.app）或文件夹，暂不支持普通文件。"
        case .missing: "入口目标已移动或不存在，请在编辑窗口重新选择。"
        }
    }
}

public enum LocalTarget {
    public static func kind(at url: URL) throws -> LauncherItem.Kind {
        guard url.isFileURL else { throw LocalTargetError.unsupported }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw LocalTargetError.missing }
        guard directory.boolValue else { throw LocalTargetError.unsupported }
        return url.pathExtension.lowercased() == "app" ? .application : .folder
    }
}
