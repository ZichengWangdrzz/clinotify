import Foundation
import XCTest
@testable import CLINotifyShared

final class LemonSqueezyLicenseClientTests: XCTestCase {
    func testActivationResponseDecodesAndMapsLifetimeRecord() throws {
        let data = """
        {
          "activated": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "active",
            "key": "38b1460a-5104-4067-a91d-77b872934d51",
            "activation_limit": 2,
            "activation_usage": 1,
            "created_at": "2026-01-24T14:15:07.000000Z",
            "expires_at": null
          },
          "instance": {
            "id": "instance-1",
            "name": "Mac",
            "created_at": "2026-01-24T14:15:07.000000Z"
          },
          "meta": {
            "product_id": 4,
            "product_name": "CLINotify",
            "variant_id": 5,
            "variant_name": "Lifetime"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LemonSqueezyLicenseResponse.self, from: data)
        let record = LicenseManager.record(
            from: response,
            licenseKey: "38b1460a-5104-4067-a91d-77b872934d51",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(response.activated, true)
        XCTAssertEqual(response.instance?.id, "instance-1")
        XCTAssertEqual(record.state, .lifetime)
        XCTAssertEqual(record.instanceID, "instance-1")
        XCTAssertEqual(record.licenseKeyTail, "934d51")
    }

    func testValidateResponseWithFutureExpirationMapsSubscription() throws {
        let response = LemonSqueezyLicenseResponse(
            valid: true,
            licenseKey: LemonSqueezyLicenseKey(
                status: "active",
                expiresAt: "2099-01-24T14:15:07.000000Z"
            ),
            instance: LemonSqueezyLicenseInstance(id: "instance-2")
        )

        let record = LicenseManager.record(
            from: response,
            licenseKey: "LS-SUB-123456",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(record.state, .activeSubscription)
        XCTAssertEqual(record.instanceID, "instance-2")
    }
}
