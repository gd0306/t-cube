import AppKit
import SwiftUI

/// Shared desktop text roles. Auxiliary information uses the system's small font,
/// rather than shrinking paths and state messages to a fixed 10 pt.
enum InterfaceTypography {
    static let title = Font.title2.weight(.semibold)
    static let body = Font.body
    static let detail = Font.system(size: NSFont.smallSystemFontSize)
    static let value = detail.monospacedDigit()
}
