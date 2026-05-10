import XCTest
@testable import ICSBridge

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

final class AvailabilityMergeTests: XCTestCase {
    private func d(_ minutes: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(minutes * 60))
    }

    func testMergeNonOverlapping() {
        let busy = [
            BusyInterval(start: d(60), end: d(90), title: "A"),
            BusyInterval(start: d(120), end: d(150), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeOverlapping() {
        let busy = [
            BusyInterval(start: d(60), end: d(120), title: "A"),
            BusyInterval(start: d(90), end: d(150), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, d(60))
        XCTAssertEqual(merged[0].end, d(150))
    }

    func testMergeAdjacentWithinGranularity() {
        // Gap of 15 minutes < granularity 30 => merge
        let busy = [
            BusyInterval(start: d(60), end: d(90), title: "A"),
            BusyInterval(start: d(105), end: d(135), title: "B")
        ]
        let merged = Availability.merge(busy: busy, granularityMinutes: 30)
        XCTAssertEqual(merged.count, 1)
    }

    func testFreeBlocksFromBusy() {
        let busy = [
            BusyInterval(start: d(120), end: d(150), title: "A")
        ]
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: busy)
        XCTAssertEqual(free.count, 2)
        XCTAssertEqual(free[0].start, d(60))
        XCTAssertEqual(free[0].end, d(120))
        XCTAssertEqual(free[1].start, d(150))
        XCTAssertEqual(free[1].end, d(180))
    }

    func testFreeBlocksNoBusy() {
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: [])
        XCTAssertEqual(free.count, 1)
        XCTAssertEqual(free[0].start, d(60))
        XCTAssertEqual(free[0].end, d(180))
    }

    func testFreeBlocksFullyBusy() {
        let busy = [BusyInterval(start: d(60), end: d(180), title: nil)]
        let free = Availability.freeBlocks(rangeStart: d(60), rangeEnd: d(180), merged: busy)
        XCTAssertEqual(free.count, 0)
    }
}
