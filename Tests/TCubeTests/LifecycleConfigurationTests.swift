import Foundation
import Testing
@testable import TCube

struct LifecycleConfigurationTests {
    private let key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    @Test func updaterRemainsUnavailableWithoutAValidSigningKey() {
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: nil).issue != nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "not-a-key").issue != nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "YWJj").issue != nil)
    }

    @Test func updaterRequiresAnHTTPSFeedWithAHost() {
        #expect(UpdateConfiguration(feedURL: nil, publicKey: key).issue != nil)
        #expect(UpdateConfiguration(feedURL: "http://example.com/appcast.xml", publicKey: key).issue != nil)
        #expect(UpdateConfiguration(feedURL: "https:///appcast.xml", publicKey: key).issue != nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: key).issue == nil)
    }
}
