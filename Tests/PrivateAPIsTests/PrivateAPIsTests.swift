import PrivateAPIs
import XCTest

final class PrivateAPIsTests: XCTestCase {
    /// Confirms the SkyLight symbols the window switcher relies on resolve on this OS build.
    func testSkyLightSymbolsResolve() {
        XCTAssertTrue(GKPrivateAPIsLoad(), "SkyLight symbols missing on this macOS build")
        XCTAssertNotEqual(GKMainConnectionID(), 0)
    }
}
