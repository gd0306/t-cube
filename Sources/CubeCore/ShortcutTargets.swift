import Foundation

public enum WebsiteTarget {
    public static func isValid(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" }),
              components.user == nil, components.password == nil else { return false }
        if let port = components.port, !(1...65535).contains(port) { return false }
        return true
    }

    public static func item(title: String, address: String) throws -> LauncherItem {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text) else { throw ConfigurationError.invalidItem }
        let item = LauncherItem(url: url, name: title.trimmingCharacters(in: .whitespacesAndNewlines), kind: .website)
        try item.validate()
        return item
    }
}

/// Fixed macOS 15+ settings destinations. Values match the system's settings extension IDs.
public enum SystemSettingsTarget: String, CaseIterable, Identifiable, Sendable {
    case wifi, bluetooth, displays, sound, privacy, keyboard
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .bluetooth: "蓝牙"
        case .displays: "显示器"
        case .sound: "声音"
        case .privacy: "隐私与安全性"
        case .keyboard: "键盘"
        }
    }
    public var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .displays: "display"
        case .sound: "speaker.wave.2.fill"
        case .privacy: "hand.raised.fill"
        case .keyboard: "keyboard"
        }
    }
    public var url: URL {
        let identifier: String = switch self {
        case .wifi: "com.apple.wifi-settings-extension"
        case .bluetooth: "com.apple.BluetoothSettings"
        case .displays: "com.apple.Displays-Settings.extension"
        case .sound: "com.apple.Sound-Settings.extension"
        case .privacy: "com.apple.settings.PrivacySecurity.extension"
        case .keyboard: "com.apple.Keyboard-Settings.extension"
        }
        return URL(string: "x-apple.systempreferences:\(identifier)")!
    }
    public var item: LauncherItem { LauncherItem(url: url, name: title, kind: .systemSettings) }
}
