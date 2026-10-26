import Foundation

public struct CubeHoverSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var multiplier: Double
    public init(isEnabled: Bool = true, multiplier: Double = 4.0) {
        self.isEnabled = isEnabled
        self.multiplier = multiplier
    }
    public func validate() throws {
        guard multiplier.isFinite, (1.1...4.0).contains(multiplier) else {
            throw ConfigurationError.invalidHover
        }
    }
}
