import GarakutaCore
import XCTest

// XCTest rather than Swift Testing: the Testing module ships with Xcode, not with Command Line Tools.
final class EventBusTests: XCTestCase {
    @MainActor
    func testEventBusDeliversToSubscribers() {
        let bus = EventBus()
        var received: [AppEvent] = []
        bus.subscribe { received.append($0) }
        bus.publish(.screenParametersChanged)
        XCTAssertEqual(received.count, 1)
    }
}
