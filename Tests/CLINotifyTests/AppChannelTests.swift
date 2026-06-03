import Foundation
import XCTest
@testable import CLINotifyShared

final class AppChannelTests: XCTestCase {
    func testEnvVarSelectsDevAndWinsOverName() {
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify", environment: ["CLINOTIFY_CHANNEL": "dev"]), .dev)
        // env explicitly forcing production beats a -dev name
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify-dev", environment: ["CLINOTIFY_CHANNEL": "production"]), .production)
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify-dev", environment: ["CLINOTIFY_CHANNEL": "prod"]), .production)
    }

    func testInvokedNameSuffixSelectsDev() {
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify-dev", environment: [:]), .dev)
        XCTAssertEqual(AppChannel.resolve(invokedName: "/usr/local/bin/clinotify-dev", environment: [:]), .dev)
    }

    func testDefaultsToProduction() {
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify", environment: [:]), .production)
        XCTAssertEqual(AppChannel.resolve(invokedName: nil, environment: [:]), .production)
        XCTAssertEqual(AppChannel.resolve(invokedName: "clinotify", environment: ["CLINOTIFY_CHANNEL": ""]), .production)
    }

    func testChannelIdentitiesAreDistinct() {
        XCTAssertEqual(AppChannel.production.cliName, "clinotify")
        XCTAssertEqual(AppChannel.dev.cliName, "clinotify-dev")
        XCTAssertEqual(AppChannel.production.appSupportName, "CLINotify")
        XCTAssertEqual(AppChannel.dev.appSupportName, "CLINotify-Dev")
        XCTAssertNotEqual(AppChannel.production.bundleIdentifier, AppChannel.dev.bundleIdentifier)
    }
}
