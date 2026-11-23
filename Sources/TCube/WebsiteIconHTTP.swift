import Foundation
import CubeCore

/// One bounded, cookie-free request. Delegate and cancellation state share a lock.
private final class WebsiteIconRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let limit: Int
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<WebsiteIconResource?, Never>?
    private var bytes = Data()
    private var responseURL: URL?
    private var cancelled = false
    private var redirects = 0

    init(url: URL, limit: Int, configuration: URLSessionConfiguration) {
        self.url = url; self.limit = limit
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    func start(_ continuation: CheckedContinuation<WebsiteIconResource?, Never>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(returning: nil); return }
        self.continuation = continuation
        let config = configuration
        config.httpAdditionalHeaders = nil
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("T-Cube Website Icons", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); redirects += 1; let count = redirects; lock.unlock()
        guard count <= 4, let next = request.url, WebsiteTarget.isValid(next),
              url.scheme?.lowercased() != "https" || next.scheme?.lowercased() == "https" else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= limit, let finalURL = response.url,
              WebsiteTarget.isValid(finalURL) else { completionHandler(.cancel); return }
        lock.lock(); responseURL = finalURL; lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let tooLarge = data.count > limit - bytes.count
        if !tooLarge { bytes.append(data) }
        lock.unlock()
        if tooLarge { cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let value = error == nil && !cancelled ? responseURL.map { WebsiteIconResource(data: bytes, url: $0) } : nil
        let continuation = continuation
        self.continuation = nil
        self.task = nil
        self.session = nil
        lock.unlock()
        continuation?.resume(returning: value)
        session.finishTasksAndInvalidate()
    }
}

enum WebsiteIconHTTP {
    static func load(_ url: URL, limit: Int, configuration: URLSessionConfiguration = .ephemeral) async -> WebsiteIconResource? {
        guard WebsiteTarget.isValid(url) else { return nil }
        let request = WebsiteIconRequest(url: url, limit: limit, configuration: configuration)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { request.start($0) }
        } onCancel: { request.cancel() }
    }
}
