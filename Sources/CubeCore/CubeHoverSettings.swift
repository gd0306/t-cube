import Foundation

public struct CubeHoverSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var multiplier: Double
    public var delaySeconds: Double

    public init(isEnabled: Bool = true, multiplier: Double = 4.0, delaySeconds: Double = 0.18) {
        self.isEnabled = isEnabled
        self.multiplier = multiplier
        self.delaySeconds = delaySeconds
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, multiplier, delaySeconds }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        multiplier = try values.decode(Double.self, forKey: .multiplier)
        delaySeconds = try values.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? 0.18
    }

    public func validate() throws {
        guard multiplier.isFinite, (1.1...4.0).contains(multiplier),
              delaySeconds.isFinite, (0...1.5).contains(delaySeconds) else {
            throw ConfigurationError.invalidHover
        }
    }
}
