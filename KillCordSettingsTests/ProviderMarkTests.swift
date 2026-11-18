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
        // The balance services have no sourced mark yet and show a letter instead; custom shows braces.
        XCTAssertEqual(ProviderID.allCases.filter { $0.markAssetName == nil },
                       [.openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid, .custom])
    }
}
