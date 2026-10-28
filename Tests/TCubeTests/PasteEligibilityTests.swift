import Testing
@testable import TCube

struct PasteEligibilityTests {
    @Test func onlyPastesBackIntoTheOriginalExternalField() {
        #expect(PasteEligibility.allows(target: 42, frontmost: 42, own: 7, trusted: true, sameField: true))
        #expect(!PasteEligibility.allows(target: 42, frontmost: 11, own: 7, trusted: true, sameField: true))
        #expect(!PasteEligibility.allows(target: 7, frontmost: 7, own: 7, trusted: true, sameField: true))
        #expect(!PasteEligibility.allows(target: 42, frontmost: 42, own: 7, trusted: false, sameField: true))
        #expect(!PasteEligibility.allows(target: 42, frontmost: 42, own: 7, trusted: true, sameField: false))
        #expect(!PasteEligibility.allows(target: nil, frontmost: 42, own: 7, trusted: true, sameField: true))
    }
}
