import Foundation

public enum CubeRenderingMode: Equatable, Sendable {
    case suspended, idle, interactive
    public var animationInterval: TimeInterval {
        switch self {
        case .suspended: .infinity
        case .idle: 1.0 / 15
        case .interactive: 1.0 / 30
        }
    }
}

public enum CubeRenderingPolicy {
    public static func mode(visible: Bool, hovered: Bool, interacting: Bool, autoRotates: Bool,
                            slimeActive: Bool, reducedMotion: Bool) -> CubeRenderingMode {
        guard visible else { return .suspended }
        if interacting { return .interactive }
        if reducedMotion { return .suspended }
        if hovered || slimeActive { return .interactive }
        return autoRotates ? .idle : .suspended
    }
}
