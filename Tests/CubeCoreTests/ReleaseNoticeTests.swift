import Foundation
import Testing
@testable import CubeCore

struct ReleaseNoticeTests {
    @Test func versionsCompareNumericallyAndRejectUnstableOrAmbiguousTags() throws {
        #expect(try #require(ReleaseVersion("v0.10.0")) > #require(ReleaseVersion("0.9.99")))
        #expect(ReleaseVersion("0.19.0") == ReleaseVersion("v0.19.0"))
        for value in ["", "1.2", "1.2.3.4", "01.2.3", "1.2.3-beta", "1.2.3+build", " 1.2.3", "1.2.3\n", "１.2.3", "9007199254740992.0.0"] {
            #expect(ReleaseVersion(value) == nil, "Reject \(value)")
        }
    }

    @Test func onlyStableReleaseMetadataAndItsPinnedRepositoryPageAreAccepted() throws {
        func data(_ changes: [String: Any] = [:]) throws -> Data {
            var document: [String: Any] = ["tag_name": "v0.20.0", "draft": false, "prerelease": false,
                "html_url": "https://github.com/gd0306/t-cube/releases/tag/v0.20.0"]
            document.merge(changes) { _, new in new }
            return try JSONSerialization.data(withJSONObject: document)
        }
        let notice = try ReleaseNotice.decode(data())
        #expect(notice.version.description == "0.20.0")
        #expect(notice.pageURL.absoluteString == "https://github.com/gd0306/t-cube/releases/tag/v0.20.0")
        for change: [String: Any] in [["draft": true], ["prerelease": true], ["draft": "false"], ["tag_name": "v0.20.0-rc.1"],
            ["html_url": "https://evil.example/releases/tag/v0.20.0"], ["html_url": "https://github.com/other/repo/releases/tag/v0.20.0"],
            ["html_url": "https://github.com/gd0306/t-cube/releases/tag/v0.20.0?token=x"]] {
            #expect(throws: (any Error).self) { try ReleaseNotice.decode(data(change)) }
        }
        #expect(throws: (any Error).self) { try ReleaseNotice.decode(Data(repeating: 32, count: 524289)) }
    }
}
