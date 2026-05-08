import XCTest
@testable import ICalBridge

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
