import Foundation

public struct DisplayBrightnessTarget: Identifiable, Equatable, Hashable, Sendable {
    public let id: UInt32
    public let uuid: String
    public let name: String
    public let isBuiltIn: Bool
    public init(id: UInt32, uuid: String, name: String, isBuiltIn: Bool) {
        self.id = id; self.uuid = uuid; self.name = name; self.isBuiltIn = isBuiltIn
    }
}

public enum DisplayBrightnessBackend: String, Sendable { case native, ddc }

public struct DisplayBrightnessSample: Equatable, Sendable {
    public let fraction: Double
    public let backend: DisplayBrightnessBackend
    public init(fraction: Double, backend: DisplayBrightnessBackend) {
        self.fraction = fraction; self.backend = backend
    }
}

public enum DisplayBrightnessFailure: Error, Equatable, Sendable {
    case unsupported, disconnected, readFailed, writeFailed, invalidResponse, invalidValue, verificationFailed
    public var message: String {
        switch self {
        case .unsupported: "此显示器或连接不支持硬件亮度调节"
        case .disconnected: "显示器已断开，请重新打开菜单"
        case .readFailed: "无法读取亮度，请重试"
        case .writeFailed: "亮度调节失败，请重试"
        case .invalidResponse: "显示器未返回有效亮度，请检查 DDC/CI 设置"
        case .invalidValue: "无效的亮度值"
        case .verificationFailed: "显示器未确认新的亮度，请检查屏幕设置"
        }
    }
}

public struct DDCBrightnessValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16
    public var fraction: Double { Double(current) / Double(maximum) }
}

public enum DDCBrightnessCodec {
    public static let readRequest: [UInt8] = [0x82, 0x01, 0x10, 0xAC]

    public static func writeRequest(value: UInt16) -> [UInt8] {
        let bytes: [UInt8] = [0x84, 0x03, 0x10, UInt8(value >> 8), UInt8(value & 0xFF)]
        return bytes + [bytes.reduce(UInt8(0x6E ^ 0x51), ^)]
    }

    public static func parseReply(_ bytes: [UInt8]) -> DDCBrightnessValue? {
        guard bytes.count == 11, bytes[0] == 0x6E, bytes[1] == 0x88,
              bytes[2] == 0x02, bytes[3] == 0, bytes[4] == 0x10, bytes[5] == 0,
              bytes.dropLast().reduce(UInt8(0x50), ^) == bytes[10] else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard maximum > 0, current <= maximum else { return nil }
        return DDCBrightnessValue(current: current, maximum: maximum)
    }

    public static func rawValue(fraction: Double, maximum: UInt16) -> UInt16? {
        guard fraction.isFinite, (0...1).contains(fraction), maximum > 0 else { return nil }
        return UInt16((fraction * Double(maximum)).rounded())
    }
}
