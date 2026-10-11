import Darwin
import Foundation

public struct ProcessIO: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let path: String
    /// Bytes this process has read from and written to disk since it started.
    public let totalRead: UInt64
    public let totalWritten: UInt64
    /// Bytes per second since the previous sample.
    public let readRate: Double
    public let writeRate: Double
}

/// Per-process disk I/O. Without admin rights macOS only reports processes owned by the current user,
/// which covers apps, terminals and agents the user started.
public final class ProcessIOMonitor {
    private typealias Counters = (read: UInt64, written: UInt64)

    private var previous: [Int32: Counters] = [:]
    private var lastSample: Date?
    private var identities: [Int32: (name: String, path: String)] = [:]

    public init() {}

    public func sample() -> [ProcessIO] {
        let now = Date()
        let interval = lastSample.map { now.timeIntervalSince($0) } ?? 0
        var current: [Int32: Counters] = [:]
        var result: [ProcessIO] = []

        for pid in Self.allPIDs() {
            guard let usage = Self.diskUsage(pid) else { continue }
            current[pid] = usage

            var readRate = 0.0
            var writeRate = 0.0
            if interval > 0, let prior = previous[pid] {
                readRate = Double(usage.read >= prior.read ? usage.read - prior.read : 0) / interval
                writeRate = Double(usage.written >= prior.written ? usage.written - prior.written : 0) / interval
            }
            guard usage.read > 0 || usage.written > 0 else { continue }

            let identity = identities[pid] ?? Self.identity(pid)
            identities[pid] = identity
            result.append(ProcessIO(
                pid: pid, name: identity.name, path: identity.path,
                totalRead: usage.read, totalWritten: usage.written,
                readRate: readRate, writeRate: writeRate
            ))
        }

        identities = identities.filter { current[$0.key] != nil }
        previous = current
        lastSample = now
        return result.sorted {
            ($0.writeRate + $0.readRate, $0.totalWritten) > ($1.writeRate + $1.readRate, $1.totalWritten)
        }
    }

    static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private static func diskUsage(_ pid: Int32) -> Counters? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return nil }
        return (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
    }

    static func identity(_ pid: Int32) -> (name: String, path: String) {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : ""
        return (displayName(forExecutablePath: path, pid: pid), path)
    }

    /// "Google Chrome Helper" inside Chrome.app reads as "Google Chrome › Google Chrome Helper".
    static func displayName(forExecutablePath path: String, pid: Int32) -> String {
        guard !path.isEmpty else { return "Process \(pid)" }
        let components = path.split(separator: "/").map(String.init)
        let executable = components.last ?? path
        guard let app = components.first(where: { $0.hasSuffix(".app") }) else { return executable }
        let appName = String(app.dropLast(4))
        return appName == executable ? appName : "\(appName) › \(executable)"
    }
}
