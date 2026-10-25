import Foundation

public struct CubeAppearance: Codable, Equatable, Sendable {
    public var primaryHex: String
    public var secondaryHex: String
    public var glowIntensity: Double

    public init(primaryHex: String = "#65DEFF", secondaryHex: String = "#B793FF", glowIntensity: Double = 0.55) {
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.glowIntensity = glowIntensity
    }

    public func validate() throws {
        func valid(_ value: String) -> Bool {
            value.utf8.count == 7 && value.first == "#" && value.dropFirst().allSatisfy { "0123456789abcdefABCDEF".contains($0) }
        }
        guard valid(primaryHex), valid(secondaryHex), glowIntensity.isFinite, (0...1).contains(glowIntensity) else {
            throw ConfigurationError.invalidAppearance
        }
    }
}
