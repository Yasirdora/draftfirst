import Foundation
import XCTest
@testable import eDraft

/// Appearance follows the device unless the writer says otherwise. The old
/// build forced Dark on every window regardless of the system setting — a
/// HIG deviation that reads as the app ignoring you, in both directions.
@MainActor
final class AppearancePreferenceTests: XCTestCase {

    private let key = AppearancePreference.storageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testSystemIsTheDefaultAndLeadsTheMenu() {
        XCTAssertEqual(AppearancePreference.default, .system)
        XCTAssertEqual(AppearancePreference.allCases.first, .system)
        XCTAssertEqual(AppearancePreference.allCases.count, 3)
    }

    /// The regression itself: nothing stored must mean "follow the device",
    /// never "dark".
    func testUnsetPreferenceFollowsTheDevice() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .system)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .unspecified)
    }

    func testGarbageValueFallsBackToSystem() {
        UserDefaults.standard.set("chartreuse", forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .system)
    }

    /// An explicit choice is still absolute — that was the point of the
    /// window-level override in the first place.
    func testExplicitChoiceIsHonoured() {
        UserDefaults.standard.set(AppearancePreference.light.rawValue, forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .light)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .light)

        UserDefaults.standard.set(AppearancePreference.dark.rawValue, forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .dark)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .dark)
    }

    func testEveryOptionCarriesATitleAndSymbol() {
        for option in AppearancePreference.allCases {
            XCTAssertFalse(option.title.isEmpty, "\(option) has no title")
            XCTAssertNotNil(UIImage(systemName: option.symbol), "\(option) has no valid symbol")
        }
    }
}
