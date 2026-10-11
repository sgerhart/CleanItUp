import Foundation

public enum CleanupSafety: Sendable {
    /// Apps and tools rebuild this automatically. Removing it costs a re-download or rebuild, not data.
    case regenerates
    /// Might be something the user wants. Look before removing.
    case review
}

public enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case appCaches
    case logs
    case xcode
    case developerCaches
    case projectDependencies
    case oldDownloads

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appCaches: return "App caches"
        case .logs: return "Logs"
        case .xcode: return "Xcode and simulators"
        case .developerCaches: return "Package manager caches"
        case .projectDependencies: return "Project dependencies"
        case .oldDownloads: return "Old downloads"
        }
    }

    public var detail: String {
        switch self {
        case .appCaches: return "Files apps keep to load faster. They are rebuilt as needed."
        case .logs: return "Diagnostic logs written by apps."
        case .xcode: return "Build products, archives and simulator caches."
        case .developerCaches: return "Downloaded packages for npm, pip, Hugging Face, Cargo, Go and others."
        case .projectDependencies: return "node_modules, Python virtual environments and build folders inside your projects. Reinstall with npm install, pip install or cargo build."
        case .oldDownloads: return "Items in Downloads you haven't touched in a while."
        }
    }

    public var safety: CleanupSafety {
        switch self {
        case .oldDownloads: return .review
        default: return .regenerates
        }
    }
}

public struct CleanupItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let category: CleanupCategory
    public let size: Int64
    public let modified: Date?
    public let note: String?

    public var name: String { url.lastPathComponent }
}

public struct CleanupScanner {
    public let home: URL
    public var downloadsAgeDays: Int = 90
    /// Items smaller than this are left out to keep the list useful.
    public var minimumSize: Int64 = 1_000_000

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Folders searched for project dependencies. Searching all of home would be slow and touch private folders.
    static let projectRoots = [
        "Developer", "Projects", "projects", "Code", "code", "src", "repos", "Repos", "GitHub", "git",
        "dev", "work", "Work", "Sites", "Documents", "Desktop",
    ]

    public func scan(progress: (String) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> [CleanupItem] {
        var items: [CleanupItem] = []
        let library = home.appendingPathComponent("Library")

        progress("App caches")
        items += children(of: library.appendingPathComponent("Caches"), category: .appCaches, isCancelled: isCancelled)
        if isCancelled() { return items }

        progress("Logs")
        items += children(of: library.appendingPathComponent("Logs"), category: .logs, isCancelled: isCancelled)
        if isCancelled() { return items }

        progress("Xcode")
        let developer = library.appendingPathComponent("Developer")
        items += children(of: developer.appendingPathComponent("Xcode/DerivedData"), category: .xcode, note: "Xcode build products", isCancelled: isCancelled)
        items += children(of: developer.appendingPathComponent("Xcode/iOS DeviceSupport"), category: .xcode, note: "Device symbols, re-downloaded when a device connects", isCancelled: isCancelled)
        items += children(of: developer.appendingPathComponent("Xcode/Archives"), category: .xcode, note: "App archives. Keep any you may need to re-submit", isCancelled: isCancelled)
        items += single(developer.appendingPathComponent("CoreSimulator/Caches"), category: .xcode, note: "Simulator caches", isCancelled: isCancelled)
        if isCancelled() { return items }

        progress("Package manager caches")
        let developerCaches: [(String, String)] = [
            (".npm/_cacache", "npm"),
            (".yarn/berry/cache", "Yarn"),
            (".bun/install/cache", "Bun"),
            ("Library/pnpm/store", "pnpm"),
            (".gradle/caches", "Gradle"),
            (".m2/repository", "Maven"),
            (".cargo/registry", "Cargo"),
            ("go/pkg/mod", "Go modules"),
            (".cocoapods/repos", "CocoaPods"),
        ]
        for (path, note) in developerCaches {
            items += single(home.appendingPathComponent(path), category: .developerCaches, note: note, isCancelled: isCancelled)
        }
        // ~/.cache holds pip, uv, Hugging Face models and more, one folder per tool.
        items += children(of: home.appendingPathComponent(".cache"), category: .developerCaches, isCancelled: isCancelled)
        if isCancelled() { return items }

        progress("Project dependencies")
        for root in Self.projectRoots {
            items += projectDependencies(under: home.appendingPathComponent(root), isCancelled: isCancelled)
            if isCancelled() { return items }
        }

        progress("Downloads")
        items += oldDownloads()

        // A project folder can be reachable from two roots (for example Documents and a symlink); keep one copy.
        var seen = Set<String>()
        return items.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private func children(of folder: URL, category: CleanupCategory, note: String? = nil, isCancelled: () -> Bool) -> [CleanupItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        return contents.compactMap { url in
            if isCancelled() { return nil }
            let size = DirectoryScanner.allocatedSize(of: url, isCancelled: isCancelled)
            guard size >= minimumSize else { return nil }
            let modified = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
            return CleanupItem(url: url, category: category, size: size, modified: modified, note: note)
        }
    }

    private func single(_ url: URL, category: CleanupCategory, note: String?, isCancelled: () -> Bool) -> [CleanupItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = DirectoryScanner.allocatedSize(of: url, isCancelled: isCancelled)
        guard size >= minimumSize else { return [] }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return [CleanupItem(url: url, category: category, size: size, modified: modified, note: note)]
    }

    /// Finds dependency folders that a project tool can recreate, only when the matching project file sits next to them.
    func projectDependencies(under root: URL, maxDepth: Int = 6, isCancelled: () -> Bool) -> [CleanupItem] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else {
            return []
        }

        var found: [CleanupItem] = []
        var seen = 0
        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen % 500 == 0, isCancelled() { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { continue }

            let name = url.lastPathComponent
            if name == ".git" || name == "Library" {
                enumerator.skipDescendants()
                continue
            }
            if let note = Self.dependencyNote(name: name, folder: url, parent: url.deletingLastPathComponent()) {
                enumerator.skipDescendants()
                let size = DirectoryScanner.allocatedSize(of: url, isCancelled: isCancelled)
                if size >= minimumSize {
                    let project = url.deletingLastPathComponent().lastPathComponent
                    found.append(CleanupItem(url: url, category: .projectDependencies, size: size, modified: values.contentModificationDate, note: "\(note) in \(project)"))
                }
                continue
            }
            if enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }
        return found
    }

    static func dependencyNote(name: String, folder: URL, parent: URL) -> String? {
        let fileManager = FileManager.default
        func parentHas(_ file: String) -> Bool { fileManager.fileExists(atPath: parent.appendingPathComponent(file).path) }
        switch name {
        case "node_modules":
            return parentHas("package.json") ? "Node packages" : nil
        case ".venv", "venv", "env":
            return fileManager.fileExists(atPath: folder.appendingPathComponent("pyvenv.cfg").path) ? "Python environment" : nil
        case "target":
            return parentHas("Cargo.toml") ? "Rust build output" : nil
        case ".next":
            return parentHas("package.json") ? "Next.js build output" : nil
        case ".build":
            return parentHas("Package.swift") ? "Swift build output" : nil
        default:
            return nil
        }
    }

    private func oldDownloads() -> [CleanupItem] {
        let downloads = home.appendingPathComponent("Downloads")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-Double(downloadsAgeDays) * 86_400)
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let lastTouched = [values.contentModificationDate, values.contentAccessDate, values.addedToDirectoryDate]
                .compactMap { $0 }
                .max()
            guard let lastTouched, lastTouched < cutoff else { return nil }
            let size = DirectoryScanner.allocatedSize(of: url)
            guard size >= minimumSize else { return nil }
            let days = Int(Date().timeIntervalSince(lastTouched) / 86_400)
            return CleanupItem(url: url, category: .oldDownloads, size: size, modified: values.contentModificationDate, note: "Last used \(days) days ago")
        }
    }
}
