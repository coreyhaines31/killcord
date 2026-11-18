import AppKit
import KillCordCore
import XCTest

/// Connecting a custom service through the model: tested once against a mock, then saved under the
/// service's own name with its own check interval. In-memory Keychain, throwaway preferences, no network.
@MainActor
final class CustomConnectTests: XCTestCase {
    private var suiteName = ""
    private var cacheFolder: URL?

    override func setUp() async throws {
        suiteName = "app.killcord.tests.\(UUID().uuidString)"
        Preferences.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        cacheFolder = folder
        SpendCache.folder = folder
    }

    override func tearDown() async throws {
        Preferences.defaults.removePersistentDomain(forName: suiteName)
        Preferences.defaults = .standard
        if let cacheFolder { try? FileManager.default.removeItem(at: cacheFolder) }
    }

    func testConnectsUnderTheServiceNameWithItsOwnInterval() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"credits":{"left":420}}"#) }
        let secrets = InMemorySecretStore()
        let model = SpendModel(secrets: secrets, http: http)
        model.start()
        let id = try await model.connect(.custom, values: [
            "serviceName": "ScrapeCreators", "url": "https://api.example.com/v1/account/credit-balance",
            "authName": "x-api-key", "authValue": "{key}", "key": "sc-TEST-key-0001",
            "remainingPath": "credits.left", "unit": "credits", "pollMinutes": "60"
        ])
        XCTAssertEqual(model.connection(id)?.name, "ScrapeCreators")
        XCTAssertEqual(model.states[id]?.refreshFloor, 3600)
        XCTAssertEqual(model.customConfig(id)?.interval, 3600)
        XCTAssertEqual(http.requests.first?.headers["x-api-key"], "sc-TEST-key-0001")
        // The whole setup is one Keychain item; nothing about it is in preferences.
        XCTAssertEqual(secrets.accounts, [id.uuidString])
        let saved = Preferences.defaults.dictionaryRepresentation().description
        XCTAssertFalse(saved.contains("sc-TEST-key-0001"))
        XCTAssertFalse(saved.contains("api.example.com"))
    }

    func testAPrivateAddressIsRefusedBeforeSaving() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"left":1}"#) }
        http.resolver = { _ in ["192.168.1.20"] }
        let secrets = InMemorySecretStore()
        let model = SpendModel(secrets: secrets, http: http)
        model.start()
        do {
            _ = try await model.connect(.custom, values: [
                "serviceName": "Router", "url": "https://router.example.com/balance", "key": "k-TEST",
                "remainingPath": "left"
            ])
            XCTFail("connected to a private address")
        } catch let error as SpendError {
            XCTAssertEqual(error.shortLabel, "Needs setup")
        }
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertTrue(secrets.accounts.isEmpty)
        XCTAssertTrue(model.connections.isEmpty)
    }
}
