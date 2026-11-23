import Foundation
import Testing
@testable import TCube

@Suite(.serialized)
struct WebsiteIconHTTPTests {
    @Test func iconTransportDropsInheritedCredentialsAndRejectsOversizedBodies() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebsiteIconProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "test-private", "Cookie": "test-cookie"]
        WebsiteIconHTTPFixture.shared.reset(code: 200, bytes: Data([1, 2, 3]), headers: [:])
        let result = await WebsiteIconHTTP.load(URL(string: "https://example.test/favicon.ico")!, limit: 16, configuration: configuration)
        #expect(result?.data == Data([1, 2, 3]))
        let request = try #require(WebsiteIconHTTPFixture.shared.request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        for (code, body, headers): (Int, Data, [String: String]) in [
            (404, Data([1]), [:]), (200, Data(repeating: 1, count: 32), [:]),
            (200, Data([1]), ["Content-Length": "1000000"])
        ] {
            WebsiteIconHTTPFixture.shared.reset(code: code, bytes: body, headers: headers)
            #expect(await WebsiteIconHTTP.load(URL(string: "https://example.test/favicon.ico")!, limit: 16, configuration: configuration) == nil)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_LIVE_WEBSITE_ICON"] == "1"))
    func publicProductSiteIconIsDiscoveredAndDecoded() async throws {
        let data = try #require(await WebsiteIconFetcher().icon(for: URL(string: ProcessInfo.processInfo.environment["TCUBE_LIVE_WEBSITE_ICON_URL"] ?? "https://tcube.gd306.cn/")!))
        #expect(data.count > 100)
        print("Verified a public website icon through the anonymous bounded transport: \(data.count) PNG bytes")
    }
}

private final class WebsiteIconHTTPFixture: @unchecked Sendable {
    static let shared = WebsiteIconHTTPFixture()
    private let lock = NSLock()
    private var response = (200, Data(), [String: String]())
    private var received: URLRequest?
    var request: URLRequest? { lock.withLock { received } }
    func reset(code: Int, bytes: Data, headers: [String: String]) { lock.withLock { response = (code, bytes, headers); received = nil } }
    func read(_ request: URLRequest) -> (Int, Data, [String: String]) { lock.withLock { received = request; return response } }
}
private final class WebsiteIconProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body, headers) = WebsiteIconHTTPFixture.shared.read(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
