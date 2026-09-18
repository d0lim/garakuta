import XCTest
@testable import WindowSwitcherKit

final class SwitcherSettingsTests: XCTestCase {
    func testLegacySimpleModeBecomesTheTitlesStyle() throws {
        let json = """
        {"simpleMode": true, "thumbnailWidth": 220, "trigger": {"keyCode": 48, "modifiers": 2048}}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(SwitcherSettings.self, from: json)
        XCTAssertEqual(settings.style, .titles)
        XCTAssertTrue(settings.simpleMode)
        XCTAssertEqual(settings.windowOrder, .recentlyFocused)
    }

    func testUnknownValuesFallBackToDefaults() throws {
        let json = """
        {"style": "holograms", "windowOrder": "random", "appRules": {"com.example": "nonsense", "com.vm": "passShortcutThrough"}}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(SwitcherSettings.self, from: json)
        XCTAssertEqual(settings.style, .thumbnails)
        XCTAssertEqual(settings.windowOrder, .recentlyFocused)
        XCTAssertEqual(settings.appRules, ["com.vm": .passShortcutThrough])
    }

    func testRoundTrip() throws {
        var settings = SwitcherSettings()
        settings.style = .appIcons
        settings.previewSelectedWindow = true
        settings.appWindowsTrigger = SwitcherSettings.reverse(of: settings.trigger)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SwitcherSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
