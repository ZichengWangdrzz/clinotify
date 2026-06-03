import XCTest
@testable import CLINotifyShared

final class SoundFileValidatorTests: XCTestCase {
    func testSupportedExtensions() {
        XCTAssertTrue(SoundFileValidator.isSupportedExtension("mp3"))
        XCTAssertTrue(SoundFileValidator.isSupportedExtension("WAV"))
        XCTAssertTrue(SoundFileValidator.isSupportedExtension("m4a"))
        XCTAssertFalse(SoundFileValidator.isSupportedExtension("txt"))
    }

    func testUnsupportedExtensionFailsBeforeFileLookup() async {
        let url = URL(fileURLWithPath: "/tmp/not-real.txt")

        do {
            try await SoundFileValidator.validate(url: url)
            XCTFail("Expected validation failure")
        } catch let error as SoundFileValidationError {
            XCTAssertEqual(error, .unsupportedExtension("txt"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
