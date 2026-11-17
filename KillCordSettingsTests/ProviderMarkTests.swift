import AppKit
import KillCordCore
import XCTest

/// Every provider that names a mark ships it as a template image, so it draws in label ink.
final class ProviderMarkTests: XCTestCase {
    func testEveryNamedMarkIsATemplateImage() throws {
        let bundle = Bundle(for: Self.self)
        let named = ProviderID.allCases.compactMap(\.markAssetName)
        XCTAssertFalse(named.isEmpty)
        for name in named {
            let image = try XCTUnwrap(bundle.image(forResource: name), name)
            XCTAssertTrue(image.isTemplate, "\(name) must be a template image")
        }
    }

    func testMarkNamesAreUnique() {
        let named = ProviderID.allCases.compactMap(\.markAssetName)
        XCTAssertEqual(Set(named).count, named.count)
    }
}
