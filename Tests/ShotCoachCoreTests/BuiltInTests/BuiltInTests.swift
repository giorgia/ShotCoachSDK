import XCTest
@testable import ShotCoachCore

final class BuiltInTests: XCTestCase {

    private let allCategories: [SCBuiltInCategory] = [
        .homeListing, .carListing, .productPhoto, .foodPhoto
    ]

    // MARK: - SCCategoryConfig basics

    func testBuiltIn_allCategoriesHaveNonEmptyRequiredShots() {
        for cat in allCategories {
            XCTAssertFalse(cat.requiredShots.isEmpty,
                           "\(cat.categoryID) must have at least one required shot")
        }
    }

    func testBuiltIn_allCategoriesHaveNonEmptyOnDeviceRules() {
        for cat in allCategories {
            XCTAssertFalse(cat.onDeviceRules.isEmpty,
                           "\(cat.categoryID) must have at least one on-device rule")
        }
    }

    func testBuiltIn_allCategoriesHaveNonEmptyCategoryID() {
        for cat in allCategories {
            XCTAssertFalse(cat.categoryID.isEmpty)
        }
    }

    func testBuiltIn_allCategoriesHaveNonEmptyDisplayName() {
        for cat in allCategories {
            XCTAssertFalse(cat.displayName.isEmpty)
        }
    }

    func testBuiltIn_categoryIDsAreUnique() {
        let ids = allCategories.map(\.categoryID)
        XCTAssertEqual(ids.count, Set(ids).count, "All categoryIDs must be unique")
    }

    // MARK: - Shot counts (per README table)

    func testBuiltIn_homeListingHasSixShots() {
        XCTAssertEqual(SCBuiltInCategory.homeListing.requiredShots.count, 6)
    }

    func testBuiltIn_carListingHasEightShots() {
        XCTAssertEqual(SCBuiltInCategory.carListing.requiredShots.count, 8)
    }

    func testBuiltIn_productPhotoHasSixShots() {
        XCTAssertEqual(SCBuiltInCategory.productPhoto.requiredShots.count, 6)
    }

    func testBuiltIn_foodPhotoHasFiveShots() {
        XCTAssertEqual(SCBuiltInCategory.foodPhoto.requiredShots.count, 5)
    }

    // MARK: - Cloud prompts

    func testBuiltIn_allShotsHaveNonEmptyCloudPrompt() {
        for cat in allCategories {
            for shot in cat.requiredShots {
                let prompt = cat.cloudPrompt(for: shot)
                XCTAssertFalse(prompt.isEmpty,
                               "\(cat.categoryID)/\(shot.id) must return a non-empty cloud prompt")
            }
        }
    }

    func testBuiltIn_unknownShotIDReturnsNonEmptyFallbackPrompt() {
        let unknown = SCShotType(id: "unknown_shot", displayName: "Unknown")
        for cat in allCategories {
            XCTAssertFalse(cat.cloudPrompt(for: unknown).isEmpty)
        }
    }

    // MARK: - .extending builder

    func testExtending_appendsToCloudPrompt() {
        let baseShot   = SCBuiltInCategory.homeListing.requiredShots[0]
        let basePrompt = SCBuiltInCategory.homeListing.cloudPrompt(for: baseShot)

        let extended = SCBuiltInCategory.homeListing.extending {
            $0.appendPrompt("Also check the pool area.")
        }
        let extPrompt = extended.cloudPrompt(for: baseShot)

        XCTAssertTrue(extPrompt.hasPrefix(basePrompt))
        XCTAssertTrue(extPrompt.contains("pool area"))
    }

    func testExtending_addsRequiredShot() {
        let extra = SCShotType(id: "pool", displayName: "Pool Area")
        let extended = SCBuiltInCategory.homeListing.extending {
            $0.addRequiredShot(extra)
        }
        XCTAssertEqual(extended.requiredShots.count,
                       SCBuiltInCategory.homeListing.requiredShots.count + 1)
        XCTAssertTrue(extended.requiredShots.contains(extra))
    }

    func testExtending_preservesBaseOnDeviceRules() {
        let extended = SCBuiltInCategory.homeListing.extending {
            $0.appendPrompt("Extra context.")
        }
        let baseIDs     = SCBuiltInCategory.homeListing.onDeviceRules.map(\.ruleID)
        let extendedIDs = extended.onDeviceRules.map(\.ruleID)
        XCTAssertEqual(baseIDs, extendedIDs)
    }

    func testExtending_preservesCategoryIDAndDisplayName() {
        let extended = SCBuiltInCategory.carListing.extending { _ in }
        XCTAssertEqual(extended.categoryID,   SCBuiltInCategory.carListing.categoryID)
        XCTAssertEqual(extended.displayName,  SCBuiltInCategory.carListing.displayName)
    }

    func testExtending_multipleAppendsConcatenate() {
        let extended = SCBuiltInCategory.productPhoto.extending {
            $0.appendPrompt("Focus on the label.")
            $0.appendPrompt("Check for shadow on the logo.")
        }
        let shot   = SCBuiltInCategory.productPhoto.requiredShots[0]
        let prompt = extended.cloudPrompt(for: shot)
        XCTAssertTrue(prompt.contains("label"))
        XCTAssertTrue(prompt.contains("logo"))
    }

    // MARK: - Codable round-trips

    func testBuiltIn_isCodable() throws {
        for cat in allCategories {
            let data    = try JSONEncoder().encode(cat)
            let decoded = try JSONDecoder().decode(SCBuiltInCategory.self, from: data)
            XCTAssertEqual(decoded, cat)
        }
    }

    func testExtending_isCodable() throws {
        let extended = SCBuiltInCategory.foodPhoto.extending {
            $0.appendPrompt("Emphasize steam and freshness.")
            $0.addRequiredShot(SCShotType(id: "steam_close", displayName: "Steam Close-up"))
        }
        let data    = try JSONEncoder().encode(extended)
        let decoded = try JSONDecoder().decode(SCCategoryOverride.self, from: data)
        XCTAssertEqual(decoded.categoryID,          extended.categoryID)
        XCTAssertEqual(decoded.requiredShots.count, extended.requiredShots.count)
    }
}
