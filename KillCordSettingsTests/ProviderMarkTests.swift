import AppKit
import KillCordCore
import XCTest

/// Every provider ships its mark as a template image, so it draws in label ink.
final class ProviderMarkTests: XCTestCase {
    func testEveryProviderMarkIsATemplateImage() throws {
        let bundle = Bundle(for: Self.self)
        for provider in ProviderID.allCases {
            guard let name = provider.markAssetName else { continue }
            let image = try XCTUnwrap(bundle.image(forResource: name), name)
            XCTAssertTrue(image.isTemplate, "\(name) must be a template image")
        }
        for preset in ManualPreset.all {
            guard let name = preset.markAssetName else { continue }
            let image = try XCTUnwrap(bundle.image(forResource: name), name)
            XCTAssertTrue(image.isTemplate, "\(name) must be a template image")
        }
        // Every vendor with an official symbol has its mark; custom and manual connections draw a symbol, and
        // Bright Data and ScrapeCreators (no usable symbol) and Stability AI (permission first) their letter.
        XCTAssertEqual(ProviderID.allCases.filter { $0.markAssetName == nil },
                       [.brightdata, .scrapecreators, .stability, .moonshot, .telnyx, .custom, .manual])
    }
}
