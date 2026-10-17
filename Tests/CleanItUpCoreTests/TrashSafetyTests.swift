@testable import CleanItUpCore
import XCTest

final class TrashSafetyTests: XCTestCase {
    let home = "/Users/steven"

    func reason(_ path: String, directory: Bool = true) -> String? {
        TrashSafety.refusalReason(path: path, isDirectory: directory, homePath: home)
    }

    func testAllowsItemsInsideCacheFolders() {
        XCTAssertNil(reason("/Users/steven/Library/Caches/com.spotify.client"))
        XCTAssertNil(reason("/Users/steven/Library/Developer/Xcode/DerivedData/App-abc"))
        XCTAssertNil(reason("/Users/steven/Projects/site/node_modules"))
        XCTAssertNil(reason("/Users/steven/Downloads/installer.dmg", directory: false))
        XCTAssertNil(reason("/Users/steven/big.iso", directory: false))
    }

    func testRefusesOutsideHome() {
        XCTAssertNotNil(reason("/System/Library"))
        XCTAssertNotNil(reason("/Applications/Safari.app"))
        XCTAssertNotNil(reason("/Users/steven"))
        XCTAssertNotNil(reason("/Users/stevenother/file", directory: false))
        XCTAssertNotNil(reason("/Users/steven/../other/file", directory: false))
    }

    func testRefusesSystemFolders() {
        XCTAssertNotNil(reason("/Users/steven/Library"))
        XCTAssertNotNil(reason("/Users/steven/Library/Caches"))
        XCTAssertNotNil(reason("/Users/steven/Documents"))
        XCTAssertNotNil(reason("/Users/steven/Projects"))
        XCTAssertNotNil(reason("/Users/steven/.zshrc", directory: false))
    }

    func testRefusesProtectedTrees() {
        XCTAssertNotNil(reason("/Users/steven/.ssh/id_ed25519", directory: false))
        XCTAssertNotNil(reason("/Users/steven/Library/Keychains/login.keychain-db", directory: false))
        XCTAssertNotNil(reason("/Users/steven/Library/Mobile Documents/com~apple~CloudDocs/Taxes"))
    }
}
