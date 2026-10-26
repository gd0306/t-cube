import AppKit
import CubeCore

extension CubePlacement {
    var title: String {
        switch self {
        case .topLeft: "左上角"
        case .topRight: "右上角"
        case .bottomLeft: "左下角"
        case .bottomRight: "右下角"
        case .center: "正中央"
        }
    }

    var symbol: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomRight: "arrow.down.right"
        case .center: "dot.scope"
        }
    }
}

@MainActor
final class CubePlacementMenu: NSMenu {
    private let selection: (CubePlacement) -> Void

    init(selection: @escaping (CubePlacement) -> Void) {
        self.selection = selection
        super.init(title: "快捷位置")
        for placement in CubePlacement.allCases {
            let item = NSMenuItem(title: placement.title, action: #selector(place(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = placement
            item.image = NSImage(systemSymbolName: placement.symbol, accessibilityDescription: nil)
            addItem(item)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Use init(selection:)") }

    @objc private func place(_ sender: NSMenuItem) {
        guard let placement = sender.representedObject as? CubePlacement else { return }
        selection(placement)
    }
}
