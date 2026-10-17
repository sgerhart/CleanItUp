import Foundation

public struct SizedItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let isDirectory: Bool
    public let modified: Date?

    public var name: String { url.lastPathComponent }

    public init(url: URL, size: Int64, isDirectory: Bool, modified: Date?) {
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.modified = modified
    }
}

public struct ScanResult: Sendable {
    public let root: URL
    public let totalBytes: Int64
    public let fileCount: Int
    /// Immediate children of the root, largest first, with the size of everything inside them.
    public let children: [SizedItem]
    /// Largest individual files anywhere under the root.
    public let largestFiles: [SizedItem]
    /// Folders macOS wouldn't let us read, usually because the app lacks Full Disk Access.
    public let unreadableCount: Int
    public let wasCancelled: Bool

    public init(root: URL, totalBytes: Int64, fileCount: Int, children: [SizedItem], largestFiles: [SizedItem], unreadableCount: Int, wasCancelled: Bool) {
        self.root = root
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.children = children
        self.largestFiles = largestFiles
        self.unreadableCount = unreadableCount
        self.wasCancelled = wasCancelled
    }
}

public struct ScanProgress: Sendable {
    public let itemsSeen: Int
    public let bytesCounted: Int64
    public let currentPath: String
}

public enum DirectoryScanner {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Paths that mirror other volumes; descending into them double-counts disk usage.
    static let skippedPaths: Set<String> = ["/Volumes", "/System/Volumes", "/dev", "/private/var/vm"]

    /// Walks `root` once, attributing every file's on-disk size to the top-level child that contains it.
    public static func scan(
        _ root: URL,
        largestFileLimit: Int = 50,
        progress: ((ScanProgress) -> Void)? = nil,
        isCancelled: () -> Bool = { false }
    ) -> ScanResult {
        let fileManager = FileManager.default
        let keySet = Set(keys)
        var unreadable = 0

        var childTotals: [String: Int64] = [:]
        var childInfo: [String: (url: URL, isDirectory: Bool, modified: Date?)] = [:]
        var largest: [SizedItem] = []
        var total: Int64 = 0
        var files = 0
        var seen = 0
        var cancelled = false

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else {
            return ScanResult(root: root, totalBytes: 0, fileCount: 0, children: [], largestFiles: [], unreadableCount: 1, wasCancelled: false)
        }

        // The enumerator is depth-first, so every item after a level-1 entry belongs to it
        // until the next level-1 entry appears.
        var currentTop: String?

        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen % 500 == 0 {
                if isCancelled() {
                    cancelled = true
                    break
                }
                progress?(ScanProgress(itemsSeen: seen, bytesCounted: total, currentPath: url.path))
            }

            let values = try? url.resourceValues(forKeys: keySet)
            let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true

            if enumerator.level == 1 {
                let name = url.lastPathComponent
                currentTop = name
                if childTotals[name] == nil { childTotals[name] = 0 }
                childInfo[name] = (url, isDirectory, values?.contentModificationDate)
            }

            if isDirectory, skippedPaths.contains(url.path) {
                enumerator.skipDescendants()
                continue
            }

            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            files += 1
            total += size
            if let top = currentTop {
                childTotals[top, default: 0] += size
            }

            if largestFileLimit > 0, largest.count < largestFileLimit || size > (largest.last?.size ?? 0) {
                largest.append(SizedItem(url: url, size: size, isDirectory: false, modified: values?.contentModificationDate))
                largest.sort { $0.size > $1.size }
                if largest.count > largestFileLimit {
                    largest.removeLast()
                }
            }
        }

        let children = childTotals.compactMap { name, size -> SizedItem? in
            guard let info = childInfo[name] else { return nil }
            return SizedItem(url: info.url, size: size, isDirectory: info.isDirectory, modified: info.modified)
        }
        .sorted { $0.size > $1.size }

        return ScanResult(
            root: root,
            totalBytes: total,
            fileCount: files,
            children: children,
            largestFiles: largest,
            unreadableCount: unreadable,
            wasCancelled: cancelled
        )
    }

    /// Total on-disk size of a file or folder.
    public static func allocatedSize(of url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let keySet = Set(keys)
        guard let values = try? url.resourceValues(forKeys: keySet) else { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard values.isDirectory == true, values.isSymbolicLink != true,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var total: Int64 = 0
        var seen = 0
        while let child = enumerator.nextObject() as? URL {
            seen += 1
            if seen % 1000 == 0, isCancelled() { break }
            guard let childValues = try? child.resourceValues(forKeys: keySet), childValues.isRegularFile == true else { continue }
            total += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? 0)
        }
        return total
    }
}
