import Foundation
import XCTest
@testable import CLINotifyShared

final class PathEnvironmentTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Users/test/.local/bin")

    func testBinDirectoryIsLocalBinUnderHome() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        XCTAssertEqual(PathEnvironment.binDirectory(home: home).path, "/Users/test/.local/bin")
    }

    func testIsOnPathMatchesAColonSeparatedEntry() {
        XCTAssertTrue(PathEnvironment.isOnPath(dir, pathValue: "/usr/bin:/Users/test/.local/bin:/bin"))
        XCTAssertFalse(PathEnvironment.isOnPath(dir, pathValue: "/usr/bin:/bin"))
        XCTAssertFalse(PathEnvironment.isOnPath(dir, pathValue: ""))
    }

    func testHintIsNilWhenAlreadyOnPath() {
        XCTAssertNil(PathEnvironment.pathExportHint(for: dir, pathValue: "/Users/test/.local/bin:/usr/bin"))
    }

    func testHintForZshUsesZshrcAndExport() throws {
        let hint = try XCTUnwrap(PathEnvironment.pathExportHint(
            for: dir, pathValue: "/usr/bin", command: "clinotify", shell: "/bin/zsh"))
        XCTAssertTrue(hint.contains("~/.zshrc"))
        XCTAssertTrue(hint.contains(#"export PATH="/Users/test/.local/bin:$PATH""#))
        XCTAssertTrue(hint.contains("`clinotify`"))
        XCTAssertTrue(hint.contains("/Users/test/.local/bin is not on your PATH"))
    }

    func testHintForBashUsesBashProfile() throws {
        let hint = try XCTUnwrap(PathEnvironment.pathExportHint(
            for: dir, pathValue: "/usr/bin", shell: "/bin/bash"))
        XCTAssertTrue(hint.contains("~/.bash_profile"))
        XCTAssertTrue(hint.contains("export PATH="))
    }

    func testHintForFishUsesFishAddPathAndChannelCommand() throws {
        let hint = try XCTUnwrap(PathEnvironment.pathExportHint(
            for: dir, pathValue: "/usr/bin", command: "clinotify-dev", shell: "/usr/local/bin/fish"))
        XCTAssertTrue(hint.contains("~/.config/fish/config.fish"))
        XCTAssertTrue(hint.contains("fish_add_path /Users/test/.local/bin"))
        XCTAssertTrue(hint.contains("`clinotify-dev`"))
    }
}
