import Testing
@testable import MoleKit

@Test func packageBuildsAndExposesVersion() {
    #expect(MoleKitInfo.version == "0.1.0")
}
