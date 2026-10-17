import Foundation

public struct ICloudFolder: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let isDirectory: Bool
    /// Full size of the files, whether or not they're on this Mac.
    public let logicalBytes: Int64
    /// Space the files actually take on this Mac.
    public let localBytes: Int64
    public let cloudOnlyCount: Int
    public let fileCount: Int

    public var name: String { url.lastPathComponent }
}

public struct ICloudSummary: Sendable {
    public let root: URL
    public let isAvailable: Bool
    public let desktopAndDocumentsSynced: Bool
    public let logicalBytes: Int64
    public let localBytes: Int64
    public let fileCount: Int
    public let cloudOnlyCount: Int
    public let folders: [ICloudFolder]
    public let unreadableCount: Int
}

public enum ICloudDrive {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    public static func scan(isCancelled: () -> Bool = { false }) -> ICloudSummary {
        let root = root
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ICloudSummary(root: root, isAvailable: false, desktopAndDocumentsSynced: false, logicalBytes: 0, localBytes: 0, fileCount: 0, cloudOnlyCount: 0, folders: [], unreadableCount: 0)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        let keySet = Set(keys)
        var unreadable = 0
        struct Tally { var url: URL; var isDirectory: Bool; var logical: Int64 = 0; var local: Int64 = 0; var cloudOnly = 0; var files = 0 }
        var tallies: [String: Tally] = [:]
        var currentTop: String?
        var seen = 0

        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in
            unreadable += 1
            return true
        })
        while let url = enumerator?.nextObject() as? URL {
            seen += 1
            if seen % 500 == 0, isCancelled() { break }
            let values = try? url.resourceValues(forKeys: keySet)
            let name = url.lastPathComponent

            if enumerator?.level == 1 {
                currentTop = name
                tallies[name] = Tally(url: url, isDirectory: values?.isDirectory == true)
            }
            guard values?.isRegularFile == true, let top = currentTop else { continue }

            // Older macOS versions show files that aren't downloaded as hidden ".name.icloud" placeholders.
            let isPlaceholder = name.hasPrefix(".") && name.hasSuffix(".icloud")
            let isCloudOnly = isPlaceholder || values?.ubiquitousItemDownloadingStatus == .notDownloaded
            tallies[top]?.files += 1
            tallies[top]?.logical += Int64(values?.fileSize ?? 0)
            tallies[top]?.local += isCloudOnly ? 0 : Int64(values?.totalFileAllocatedSize ?? 0)
            if isCloudOnly { tallies[top]?.cloudOnly += 1 }
        }

        let folders = tallies.values.map {
            ICloudFolder(url: $0.url, isDirectory: $0.isDirectory, logicalBytes: $0.logical, localBytes: $0.local, cloudOnlyCount: $0.cloudOnly, fileCount: $0.files)
        }
        .sorted { $0.logicalBytes > $1.logicalBytes }

        return ICloudSummary(
            root: root,
            isAvailable: true,
            desktopAndDocumentsSynced: fileManager.fileExists(atPath: root.appendingPathComponent("Desktop").path)
                && fileManager.fileExists(atPath: root.appendingPathComponent("Documents").path),
            logicalBytes: folders.reduce(0) { $0 + $1.logicalBytes },
            localBytes: folders.reduce(0) { $0 + $1.localBytes },
            fileCount: folders.reduce(0) { $0 + $1.fileCount },
            cloudOnlyCount: folders.reduce(0) { $0 + $1.cloudOnlyCount },
            folders: folders,
            unreadableCount: unreadable
        )
    }

    /// Removes the local copy but keeps the file in iCloud. Nothing is lost; it downloads again when opened.
    public static func removeLocalCopy(_ url: URL) throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }

    public static func download(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
