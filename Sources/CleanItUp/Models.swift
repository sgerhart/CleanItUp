import CleanItUpCore
import Foundation
import Observation

@MainActor
@Observable
final class StorageModel {
    var volumes: [VolumeInfo] = []
    var root: URL = FileManager.default.homeDirectoryForCurrentUser
    var history: [URL] = []
    var result: ScanResult?
    var progress: ScanProgress?
    var isScanning = false
    var message: String?

    private var cancelFlag = CancelFlag()

    func refreshVolumes() {
        volumes = VolumeInfo.mounted()
    }

    func scan(_ url: URL) {
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag
        root = url
        result = nil
        progress = nil
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let result = DirectoryScanner.scan(url, progress: { progress in
                Task { @MainActor in
                    if !flag.isCancelled { self.progress = progress }
                }
            }, isCancelled: { flag.isCancelled })
            await MainActor.run {
                guard !flag.isCancelled else { return }
                self.result = result
                self.isScanning = false
            }
        }
    }

    func open(_ folder: URL) {
        history.append(root)
        scan(folder)
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        scan(previous)
    }

    func cancel() {
        cancelFlag.cancel()
        isScanning = false
    }

    func trash(_ item: SizedItem) {
        let outcome = Trasher.moveToTrash([(url: item.url, size: item.size)])
        message = outcome.summary
        refreshVolumes()
        guard outcome.trashedCount > 0, let current = result else { return }
        result = ScanResult(
            root: current.root,
            totalBytes: current.totalBytes - item.size,
            fileCount: current.fileCount,
            children: current.children.filter { $0.url != item.url },
            largestFiles: current.largestFiles.filter { $0.url != item.url },
            unreadableCount: current.unreadableCount,
            wasCancelled: current.wasCancelled
        )
    }
}

@MainActor
@Observable
final class HealthModel {
    var disks: [PhysicalDisk] = []
    var isLoading = false
    var hasSmartctl = DiskHealthReader.smartctlPath != nil

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let disks = DiskHealthReader.readAll()
            await MainActor.run {
                self.disks = disks
                self.isLoading = false
                self.hasSmartctl = DiskHealthReader.smartctlPath != nil
            }
        }
    }
}

struct ActivitySample: Identifiable {
    let id = UUID()
    let date: Date
    let readRate: Double
    let writeRate: Double
}

@MainActor
@Observable
final class ActivityModel {
    var samples: [ActivitySample] = []
    var processes: [ProcessIO] = []
    var totals = DiskIOCounters()

    private var lastCounters: DiskIOCounters?
    private var lastDate: Date?
    private let processMonitor = ProcessIOMonitor()
    private var task: Task<Void, Never>?
    private var tick = 0
    private let historyLength = 90

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func sample() {
        let now = Date()
        let counters = DiskIOMonitor.totals()
        totals = counters
        if let last = lastCounters, let lastDate {
            let interval = now.timeIntervalSince(lastDate)
            if interval > 0 {
                let read = counters.bytesRead >= last.bytesRead ? Double(counters.bytesRead - last.bytesRead) / interval : 0
                let written = counters.bytesWritten >= last.bytesWritten ? Double(counters.bytesWritten - last.bytesWritten) / interval : 0
                samples.append(ActivitySample(date: now, readRate: read, writeRate: written))
                if samples.count > historyLength {
                    samples.removeFirst(samples.count - historyLength)
                }
            }
        }
        lastCounters = counters
        lastDate = now

        // Per-process numbers are noisier; refresh them every other second.
        if tick % 2 == 0 {
            processes = processMonitor.sample()
        }
        tick += 1
    }
}

@MainActor
@Observable
final class CleanupModel {
    var items: [CleanupItem] = []
    var selected: Set<URL> = []
    var isScanning = false
    var phase = ""
    var message: String?
    var hasScanned = false

    private var cancelFlag = CancelFlag()

    func items(in category: CleanupCategory) -> [CleanupItem] {
        items.filter { $0.category == category }
    }

    var selectedBytes: Int64 {
        items.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        cancelFlag.cancel()
        let flag = CancelFlag()
        cancelFlag = flag
        isScanning = true
        message = nil
        Task.detached(priority: .userInitiated) {
            let found = CleanupScanner().scan(progress: { phase in
                Task { @MainActor in self.phase = phase }
            }, isCancelled: { flag.isCancelled })
            await MainActor.run {
                guard !flag.isCancelled else { return }
                self.items = found.sorted { $0.size > $1.size }
                // Pre-select only what rebuilds itself; anything that might matter starts unchecked.
                self.selected = Set(found.filter { $0.category.safety == .regenerates && $0.category != .projectDependencies }.map(\.url))
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func cancel() {
        cancelFlag.cancel()
        isScanning = false
    }

    func toggleAll(in category: CleanupCategory, on: Bool) {
        for item in items(in: category) {
            if on { selected.insert(item.url) } else { selected.remove(item.url) }
        }
    }

    func trashSelected() {
        let chosen = items.filter { selected.contains($0.url) }
        let outcome = Trasher.moveToTrash(chosen.map { (url: $0.url, size: $0.size) })
        let removed = Set(outcome.trashed)
        items.removeAll { removed.contains($0.url) }
        selected.subtract(removed)
        message = outcome.summary
    }
}

@MainActor
@Observable
final class ICloudModel {
    var summary: ICloudSummary?
    var isScanning = false
    var message: String?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let summary = ICloudDrive.scan()
            await MainActor.run {
                self.summary = summary
                self.isScanning = false
            }
        }
    }

    func removeLocalCopy(_ folder: ICloudFolder) {
        do {
            try ICloudDrive.removeLocalCopy(folder.url)
            message = "\(folder.name) is now stored in iCloud only. It downloads again when you open it."
            scan()
        } catch {
            message = "Couldn't free up \(folder.name): \(error.localizedDescription)"
        }
    }

    func download(_ folder: ICloudFolder) {
        do {
            try ICloudDrive.download(folder.url)
            message = "Downloading \(folder.name) from iCloud."
        } catch {
            message = "Couldn't download \(folder.name): \(error.localizedDescription)"
        }
    }
}
