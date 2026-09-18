import XCTest
@testable import WindowSwitcherKit

final class SearchMatcherTests: XCTestCase {
    private func score(_ query: String, _ text: String) -> Int { SearchMatcher.match(query: query, in: text)?.score ?? 0 }

    func testTiersRankAsExpected() {
        XCTAssertGreaterThan(score("safari", "Safari"), score("saf", "Safari"))
        XCTAssertGreaterThan(score("saf", "Safari"), score("saf", "Unsafe Report"))
        XCTAssertGreaterThan(score("rep", "Unsafe Report"), score("rep", "Unrepaired"))
        // A contiguous run outranks initials, and initials outrank scattered letters.
        XCTAssertGreaterThan(score("am", "Programming"), score("am", "Activity Monitor"))
        XCTAssertGreaterThan(score("am", "Activity Monitor"), score("am", "Alarm"))
        XCTAssertGreaterThan(score("am", "Alarm"), 0)
    }

    func testIgnoresCaseWhitespaceAndDiacritics() {
        XCTAssertEqual(score("cafe", "Café"), score("cafe", "Cafe"))
        XCTAssertGreaterThan(score("activitymonitor", "Activity Monitor"), 0)
        XCTAssertGreaterThan(score("ACTIVITY", "activity monitor"), 0)
    }

    func testNoMatchForMissingLetters() {
        XCTAssertNil(SearchMatcher.match(query: "xyz", in: "Safari"))
        XCTAssertNil(SearchMatcher.match(query: "", in: "Safari"))
        XCTAssertNil(SearchMatcher.match(query: "a", in: ""))
    }

    func testRangesPointAtTheOriginalText() {
        let match = SearchMatcher.match(query: "am", in: "Activity Monitor")!
        XCTAssertEqual(match.ranges, [0..<1, 9..<10])
        let prefix = SearchMatcher.match(query: "act", in: "Activity Monitor")!
        XCTAssertEqual(prefix.ranges, [0..<3])
        let substring = SearchMatcher.match(query: "tor", in: "Activity Monitor")!
        XCTAssertEqual(substring.ranges, [13..<16])
    }

    func testShorterTextWinsWithinATier() {
        XCTAssertGreaterThan(score("term", "Terminal"), score("term", "Terminal — ~/Develop/garakuta"))
    }
}
