import Foundation

/// Guards every removal. The app never deletes permanently: items go to the Trash, where the user can restore them.
public enum TrashSafety {
    /// Folders that must never be removed as a whole, relative to home.
    static let protectedFolders: Set<String> = [
        "Library", "Library/Caches", "Library/Logs", "Library/Developer", "Library/Developer/Xcode",
        "Library/Application Support", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/Mobile Documents", "Library/Mobile Documents/com~apple~CloudDocs",
        "Library/CloudStorage", "Library/Mail", "Library/Messages", "Library/Photos",
        "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
        ".cache", ".Trash", "Developer",
    ]

    /// Folders whose contents must never be touched.
    static let protectedTrees: [String] = ["Library/Keychains", ".ssh", ".gnupg", ".Trash", "Library/Mobile Documents"]

    /// Returns why `path` must not be moved to the Trash, or nil when it's allowed.
    public static func refusalReason(path: String, isDirectory: Bool, homePath: String) -> String? {
        let home = (homePath as NSString).standardizingPath
        let target = (path as NSString).standardizingPath
        guard target.hasPrefix(home + "/") else {
            return "It's outside your home folder."
        }
        let relative = String(target.dropFirst(home.count + 1))
        if protectedFolders.contains(relative) {
            return "\(relative) is a system folder."
        }
        for tree in protectedTrees where relative == tree || relative.hasPrefix(tree + "/") {
            return "Items in \(tree) are protected."
        }
        let depth = relative.split(separator: "/").count
        if depth == 1, isDirectory || relative.hasPrefix(".") {
            return "Top-level folders and settings in your home folder are protected."
        }
        return nil
    }
}

public struct TrashOutcome: Sendable {
    public var trashedCount = 0
    public var freedBytes: Int64 = 0
    public var trashed: [URL] = []
    public var failures: [(url: URL, reason: String)] = []

    public var summary: String {
        var text = trashedCount == 0 ? "Nothing was moved." : "Moved \(trashedCount) item\(trashedCount == 1 ? "" : "s") (\(ByteFormat.string(freedBytes))) to the Trash."
        if !failures.isEmpty {
            text += " \(failures.count) couldn't be moved: " + failures.prefix(3).map { "\($0.url.lastPathComponent) (\($0.reason))" }.joined(separator: ", ")
            if failures.count > 3 { text += "…" }
        }
        return text
    }
}

public enum Trasher {
    public static func moveToTrash(_ items: [(url: URL, size: Int64)], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> TrashOutcome {
        var outcome = TrashOutcome()
        for item in items {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirectory) else {
                outcome.failures.append((item.url, "it no longer exists"))
                continue
            }
            if let reason = TrashSafety.refusalReason(path: item.url.path, isDirectory: isDirectory.boolValue, homePath: home.path) {
                outcome.failures.append((item.url, reason))
                continue
            }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                outcome.trashedCount += 1
                outcome.freedBytes += item.size
                outcome.trashed.append(item.url)
            } catch {
                outcome.failures.append((item.url, error.localizedDescription))
            }
        }
        return outcome
    }
}
