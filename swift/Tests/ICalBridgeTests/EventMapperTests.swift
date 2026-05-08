import XCTest
@testable import ICalBridge

final class EventMapperParseISOTests: XCTestCase {
    func testParseISOWithOffset() throws {
        let d = try EventMapper.parseISO("2026-05-08T09:00:00-07:00")
        // 2026-05-08 16:00:00 UTC == 1778256000
        XCTAssertEqual(d.timeIntervalSince1970, 1778256000, accuracy: 1.0)
    }

    func testParseISOWithZ() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00Z")
        XCTAssertEqual(d.timeIntervalSince1970, 1778256000, accuracy: 1.0)
    }

    func testParseISOWithFractionalSeconds() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00.123Z")
        XCTAssertEqual(d.timeIntervalSince1970, 1778256000.123, accuracy: 0.01)
    }

    func testParseISORejectsGarbage() {
        XCTAssertThrowsError(try EventMapper.parseISO("not-a-date")) { err in
            guard case BridgeError.invalidInput(let detail) = err else {
                return XCTFail("Expected invalidInput, got \(err)")
            }
            XCTAssertTrue(detail.contains("not-a-date"))
        }
    }

    func testFormatISORoundTrip() throws {
        let d = try EventMapper.parseISO("2026-05-08T16:00:00Z")
        let s = EventMapper.formatISO(d)
        let d2 = try EventMapper.parseISO(s)
        XCTAssertEqual(d.timeIntervalSince1970, d2.timeIntervalSince1970, accuracy: 1.0)
    }
}
