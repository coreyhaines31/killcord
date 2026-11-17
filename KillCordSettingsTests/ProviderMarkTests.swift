import AppKit
import KillCordCore
import XCTest

/// Every provider ships its mark as a template image, so it draws in label ink.
final class ProviderMarkTests: XCTestCase {
    func testEveryProviderMarkIsATemplateImage() throws {
        let bundle = Bundle(for: Self.self)
        for provider in ProviderID.allCases {
            let image = try XCTUnwrap(bundle.image(forResource: provider.markAssetName), provider.markAssetName)
            XCTAssertTrue(image.isTemplate, "\(provider.markAssetName) must be a template image")
        }
    }
}
