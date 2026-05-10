import XCTest
@testable import ICSBridge
import EventKit

final class BridgeErrorTests: XCTestCase {
    func testErrorCodes() {
        XCTAssertEqual(BridgeError.permissionDenied.code, "permission_denied")
        XCTAssertEqual(BridgeError.notFound("x").code, "not_found")
        XCTAssertEqual(BridgeError.invalidInput("x").code, "invalid_input")
        XCTAssertEqual(BridgeError.readOnly("x").code, "read_only")
        XCTAssertEqual(BridgeError.saveFailed("x").code, "save_failed")
        XCTAssertEqual(BridgeError.internalError("x").code, "internal")
    }

    func testErrorMessageMentionsSystemSettings() {
        XCTAssertTrue(BridgeError.permissionDenied.message.contains("System Settings"))
    }

    func testErrorMessageEmbedsDetail() {
        XCTAssertTrue(BridgeError.notFound("calendar 42").message.contains("calendar 42"))
        XCTAssertTrue(BridgeError.invalidInput("bad date").message.contains("bad date"))
    }
}

final class BridgeResultTests: XCTestCase {
    func testSuccessEncodingNoErrorFields() throws {
        struct Payload: Encodable { let answer: Int }
        let result = BridgeResult.success(Payload(answer: 42))
        let data = try JSONEncoder().encode(result)
        let s = String(data: data, encoding: .utf8)!
        XCTAssertTrue(s.contains("\"status\":\"success\""))
        XCTAssertTrue(s.contains("\"answer\":42"))
        XCTAssertTrue(s.contains("\"error_code\":null"))
        XCTAssertTrue(s.contains("\"error_message\":null"))
    }

    func testErrorEncoding() throws {
        let result = BridgeResult<EmptyPayload>.error(.notFound("event abc"))
        let data = try JSONEncoder().encode(result)
        let s = String(data: data, encoding: .utf8)!
        XCTAssertTrue(s.contains("\"status\":\"error\""))
        XCTAssertTrue(s.contains("\"error_code\":\"not_found\""))
        XCTAssertTrue(s.contains("event abc"))
        XCTAssertTrue(s.contains("\"data\":null"))
    }

    func testEmitWritesSingleLineToStdout() {
        let payload = BridgeResult<EmptyPayload>.success(EmptyPayload())
        OutputJSON.emit(payload)
        // If we reach this point, emit() did not crash. The actual stdout capture happens in integration tests.
    }
}

struct EmptyPayload: Encodable {}

final class CalendarStoreTypeStringTests: XCTestCase {
    func testTypeStringMappings() {
        XCTAssertEqual(CalendarStore.typeString(.local), "local")
        XCTAssertEqual(CalendarStore.typeString(.calDAV), "calDAV")
        XCTAssertEqual(CalendarStore.typeString(.exchange), "exchange")
        XCTAssertEqual(CalendarStore.typeString(.subscription), "subscription")
        XCTAssertEqual(CalendarStore.typeString(.birthday), "birthday")
    }
}
