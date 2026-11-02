import CubeCore
import Foundation

/// An anonymous metadata-only request. Redirects and shared cookie/credential stores are disabled.
final class ReleaseNoticeClient: @unchecked Sendable {
    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private let session: URLSession
    private let version: String
    init(version: String, configuration: URLSessionConfiguration = .ephemeral) {
        let settings = configuration.copy() as! URLSessionConfiguration
        settings.httpAdditionalHeaders = nil
        settings.httpCookieAcceptPolicy = .never
        settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil; settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 15; settings.timeoutIntervalForResource = 15
        settings.waitsForConnectivity = false
        self.version = ReleaseVersion(version)?.description ?? "0.0.0"
        session = URLSession(configuration: settings, delegate: RejectRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func fetch(now: Date = Date()) async throws -> ReleaseNotice {
        var request = URLRequest(url: ReleaseNotice.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("T-Cube-VersionReminder/\(version)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.url == ReleaseNotice.endpoint else { throw ReleaseNoticeError.invalidResponse }
        if http.statusCode == 429 || (http.statusCode == 403 && (http.value(forHTTPHeaderField: "Retry-After") != nil || http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0")) {
            var delays: [TimeInterval] = []
            if let retry = http.value(forHTTPHeaderField: "Retry-After") {
                if let seconds = Double(retry), seconds.isFinite, seconds >= 0 { delays.append(seconds) }
                else {
                    let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
                    format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    if let date = format.date(from: retry), date >= now { delays.append(date.timeIntervalSince(now)) }
                }
            }
            if let raw = http.value(forHTTPHeaderField: "X-RateLimit-Reset"), let epoch = Double(raw), epoch.isFinite,
               epoch >= now.timeIntervalSince1970 { delays.append(epoch - now.timeIntervalSince1970) }
            let delay = delays.max() ?? 3600
            throw ReleaseNoticeError.rateLimited(until: now.addingTimeInterval(max(60, min(86_400, delay))))
        }
        guard http.statusCode == 200 else { throw ReleaseNoticeError.unavailable }
        guard response.expectedContentLength <= ReleaseNotice.maximumResponseBytes else { throw ReleaseNoticeError.invalidResponse }
        var data = Data(); data.reserveCapacity(16_384)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < ReleaseNotice.maximumResponseBytes else { throw ReleaseNoticeError.invalidResponse }
            data.append(byte)
        }
        return try ReleaseNotice.decode(data)
    }
}
