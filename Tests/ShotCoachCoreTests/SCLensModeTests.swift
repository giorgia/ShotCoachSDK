import XCTest
@testable import ShotCoachCore

final class SCLensModeTests: XCTestCase {

    func test_rawValues_areStable() {
        // Raw values are used for Codable serialisation — must never change.
        XCTAssertEqual(SCLensMode.main.rawValue,      "main")
        XCTAssertEqual(SCLensMode.ultraWide.rawValue, "ultraWide")
    }

    func test_allCases_count() {
        XCTAssertEqual(SCLensMode.allCases.count, 2)
    }

    func test_codable_roundTrip() throws {
        for mode in SCLensMode.allCases {
            let data    = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SCLensMode.self, from: data)
            XCTAssertEqual(decoded, mode, "Round-trip failed for \(mode)")
        }
    }

    func test_sendable_conformance() {
        // Compile-time check: SCLensMode must cross actor boundaries without warning.
        let _: @Sendable () -> SCLensMode = { .ultraWide }
    }
}
