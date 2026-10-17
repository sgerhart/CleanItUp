@testable import CleanItUpCore
import XCTest

final class ScannerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ path: String, bytes: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    func testAttributesSizesToTopLevelChildren() throws {
        try write("big/a/one.bin", bytes: 2_000_000)
        try write("big/two.bin", bytes: 1_000_000)
        try write("small/three.bin", bytes: 10_000)
        try write("loose.bin", bytes: 500_000)

        let result = DirectoryScanner.scan(root, largestFileLimit: 2)
        XCTAssertEqual(result.fileCount, 4)
        XCTAssertEqual(result.children.map(\.name), ["big", "loose.bin", "small"])
        XCTAssertTrue(result.children[0].isDirectory)
        XCTAssertGreaterThanOrEqual(result.children[0].size, 3_000_000)
        XCTAssertEqual(result.largestFiles.map(\.name), ["one.bin", "two.bin"])
        XCTAssertEqual(result.totalBytes, result.children.reduce(0) { $0 + $1.size })
    }

    func testFindsDependencyFoldersOnlyNextToProjectFiles() throws {
        try write("site/package.json", bytes: 10)
        try write("site/node_modules/react/index.js", bytes: 2_000_000)
        try write("notes/node_modules/fake.txt", bytes: 2_000_000)
        try write("tool/.venv/pyvenv.cfg", bytes: 10)
        try write("tool/.venv/lib/big.so", bytes: 2_000_000)

        let items = CleanupScanner(home: root).projectDependencies(under: root, isCancelled: { false })
        let paths = Set(items.map { $0.url.deletingLastPathComponent().lastPathComponent + "/" + $0.name })
        XCTAssertEqual(paths, ["site/node_modules", "tool/.venv"])
    }

    func testProcessDisplayName() {
        XCTAssertEqual(ProcessIOMonitor.displayName(forExecutablePath: "/Applications/Google Chrome.app/Contents/Frameworks/x/Google Chrome Helper", pid: 1), "Google Chrome › Google Chrome Helper")
        XCTAssertEqual(ProcessIOMonitor.displayName(forExecutablePath: "/Applications/Slack.app/Contents/MacOS/Slack", pid: 1), "Slack")
        XCTAssertEqual(ProcessIOMonitor.displayName(forExecutablePath: "/opt/homebrew/bin/node", pid: 1), "node")
        XCTAssertEqual(ProcessIOMonitor.displayName(forExecutablePath: "", pid: 42), "Process 42")
    }
}
