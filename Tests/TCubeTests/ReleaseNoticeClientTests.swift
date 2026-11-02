import CubeCore
import Foundation
import Testing
@testable import TCube

@Suite(.serialized)
struct ReleaseNoticeClientTests {
    @Test func clientReadsBoundedPublicMetadataWithoutInheritedCredentials() async throws {
        let fixture = try ReleaseHTTPFixture.success()
        ReleaseHTTPRegistry.shared.reset(fixture)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStubProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "owned-secret-fixture", "Cookie": "owned-cookie-fixture"]
        let client = ReleaseNoticeClient(version: "0.19.0", configuration: configuration)
        let notice = try await client.fetch()
        #expect(notice.version.description == "0.20.0")
        let request = try #require(ReleaseHTTPRegistry.shared.requests.first)
        #expect(request.url == URL(string: "https://api.github.com/repos/gd0306/t-cube/releases/latest"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "T-Cube-VersionReminder/0.19.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test func redirectsHttpErrorsAndOversizeBodiesCannotBecomeReleaseNotices() async throws {
        for fixture in [ReleaseHTTPFixture(code: 302, data: Data(), headers: ["Location": "https://evil.example"]),
            ReleaseHTTPFixture(code: 500, data: Data("owned remote failure".utf8)),
            ReleaseHTTPFixture(code: 200, data: Data(repeating: 32, count: 524289)),
            ReleaseHTTPFixture(code: 200, data: Data(), headers: ["Content-Length": "99999999"])] {
            ReleaseHTTPRegistry.shared.reset(fixture)
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ReleaseStubProtocol.self]
            let client = ReleaseNoticeClient(version: "0.19.0", configuration: configuration)
            await #expect(throws: (any Error).self) { try await client.fetch() }
            #expect(ReleaseHTTPRegistry.shared.requests.count == 1)
        }
    }

    @Test func rateLimitResponsesRespectRetryHeadersAndHaveABoundedDefault() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for (headers, delay): ([String: String], TimeInterval) in [(["Retry-After": "120"], 120),
            (["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1000600"], 600),
            (["Retry-After": "invalid", "X-RateLimit-Reset": "1000600"], 600),
            (["Retry-After": "120", "X-RateLimit-Reset": "1000600"], 600), ([:], 3600), (["Retry-After": "999999999"], 86400)] {
            ReleaseHTTPRegistry.shared.reset(ReleaseHTTPFixture(code: 429, data: Data(), headers: headers))
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ReleaseStubProtocol.self]
            let client = ReleaseNoticeClient(version: "0.19.0", configuration: configuration)
            do { _ = try await client.fetch(now: now); Issue.record("A rate limit must not return a release") }
            catch ReleaseNoticeError.rateLimited(let until) { #expect(until.timeIntervalSince(now) == delay) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TCUBE_LIVE_RELEASE_CHECK"] == "1"))
    func liveAnonymousReleaseEndpointProvidesValidatedMetadataOnly() async throws {
        let notice = try await ReleaseNoticeClient(version: "0.19.0").fetch()
        #expect(notice.pageURL.absoluteString.hasPrefix("https://github.com/gd0306/t-cube/releases/tag/"))
        print("Anonymous release metadata verified for version \(notice.version)")
    }
}

private struct ReleaseHTTPFixture: Sendable {
    var code: Int
    var data: Data
    var headers: [String: String] = [:]
    static func success() throws -> Self {
        Self(code: 200, data: try JSONSerialization.data(withJSONObject: ["tag_name": "v0.20.0", "draft": false, "prerelease": false,
            "html_url": "https://github.com/gd0306/t-cube/releases/tag/v0.20.0"]))
    }
}
/// URLProtocol callbacks run on URLSession threads; serialize this test-only fixture registry.
private final class ReleaseHTTPRegistry: @unchecked Sendable {
    static let shared = ReleaseHTTPRegistry()
    private let lock = NSLock()
    private var fixture = ReleaseHTTPFixture(code: 500, data: Data())
    private var received: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { received } }
    func reset(_ fixture: ReleaseHTTPFixture) { lock.withLock { self.fixture = fixture; received = [] } }
    func response(for request: URLRequest) -> ReleaseHTTPFixture { lock.withLock { received.append(request); return fixture } }
}
private final class ReleaseStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = ReleaseHTTPRegistry.shared.response(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.code, httpVersion: "HTTP/1.1", headerFields: fixture.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
