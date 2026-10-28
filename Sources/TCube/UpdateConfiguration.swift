import Foundation

struct UpdateConfiguration {
    let feedURL: String?
    let publicKey: String?

    var issue: String? {
        guard let feedURL,
              let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return "此构建未配置有效的 HTTPS 更新源。请前往发布页面查看版本。"
        }
        guard let publicKey,
              let decoded = Data(base64Encoded: publicKey), decoded.count == 32 else {
            return "此构建未配置更新签名公钥，已停用应用内更新。请前往发布页面查看版本。"
        }
        return nil
    }
}
