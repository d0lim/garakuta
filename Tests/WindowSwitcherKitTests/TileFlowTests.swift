import XCTest
@testable import WindowSwitcherKit

final class TileFlowTests: XCTestCase {
    func testWrapsWhenTheNextTileWouldCrossTheLimit() {
        let placement = TileFlow.place(widths: [100, 100, 100, 100, 100], rowHeight: 50, maxWidth: 330, spacing: 10)
        XCTAssertEqual(placement.rows, [[0, 1, 2], [3, 4]])
        XCTAssertEqual(placement.size, CGSize(width: 320, height: 110))
        XCTAssertEqual(placement.origins[3].y, 60)
    }

    func testRowsAreCentred() {
        let placement = TileFlow.place(widths: [100, 100, 100, 100], rowHeight: 50, maxWidth: 330, spacing: 10)
        XCTAssertEqual(placement.origins[0].x, 0)
        // Second row holds one 100pt tile in a 320pt grid: centred at 110.
        XCTAssertEqual(placement.origins[3].x, 110)
    }

    func testATileWiderThanTheLimitStillGetsARow() {
        let placement = TileFlow.place(widths: [500, 100], rowHeight: 50, maxWidth: 300, spacing: 10)
        XCTAssertEqual(placement.rows, [[0], [1]])
        XCTAssertEqual(placement.size.width, 500)
    }

    func testEmptyInput() {
        let placement = TileFlow.place(widths: [], rowHeight: 50, maxWidth: 300, spacing: 10)
        XCTAssertEqual(placement.size, .zero)
        XCTAssertEqual(placement.rows, [[]])
    }

    func testAutomaticSizePicksTheLargestThatFits() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        func window(_ id: UInt32, aspect: CGFloat) -> SwitcherWindow {
            SwitcherWindow(windowID: id, pid: 1, appName: "App", bundleIdentifier: nil, title: "W", frame: CGRect(x: 0, y: 0, width: 1000 * aspect, height: 1000),
                           isMinimized: false, isFullScreen: false, isAppHidden: false, isOnCurrentSpace: true, spaceIDs: [1], isAppPlaceholder: false)
        }
        let few = (0..<4).map { window(UInt32($0), aspect: 1.6) }
        let many = (0..<40).map { window(UInt32($0), aspect: 1.6) }
        let large = SwitcherMetrics.resolve(style: .thumbnails, preset: .auto, screen: screen, physicalWidthMM: 300, showsSubtitle: true, windows: few)
        let small = SwitcherMetrics.resolve(style: .thumbnails, preset: .auto, screen: screen, physicalWidthMM: 300, showsSubtitle: true, windows: many)
        XCTAssertEqual(large.preset, .large)
        XCTAssertEqual(small.preset, .small)
        XCTAssertGreaterThan(large.tileHeight, small.tileHeight)
    }

    func testComfortableWidthClampsToPhysicalSize() {
        XCTAssertEqual(SwitcherMetrics.comfortableFraction(physicalWidthMM: nil), 0.9)
        XCTAssertEqual(SwitcherMetrics.comfortableFraction(physicalWidthMM: 300), 0.9)
        XCTAssertEqual(SwitcherMetrics.comfortableFraction(physicalWidthMM: 1000), 0.6)
        XCTAssertEqual(SwitcherMetrics.comfortableFraction(physicalWidthMM: 2000), 0.45)
    }
}
