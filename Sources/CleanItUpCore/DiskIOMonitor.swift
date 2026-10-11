import Foundation
import IOKit

public struct DiskIOCounters: Sendable, Equatable {
    public var bytesRead: UInt64 = 0
    public var bytesWritten: UInt64 = 0
    public var readOperations: UInt64 = 0
    public var writeOperations: UInt64 = 0

    public init() {}
}

/// Cumulative read/write counters per physical disk, from the kernel's block storage drivers.
public enum DiskIOMonitor {
    public static func counters() -> [String: DiskIOCounters] {
        var result: [String: DiskIOCounters] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var index = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any],
               let statistics = dictionary["Statistics"] as? [String: Any] {
                func value(_ key: String) -> UInt64 { (statistics[key] as? NSNumber)?.uint64Value ?? 0 }
                var counters = DiskIOCounters()
                counters.bytesRead = value("Bytes (Read)")
                counters.bytesWritten = value("Bytes (Write)")
                counters.readOperations = value("Operations (Read)")
                counters.writeOperations = value("Operations (Write)")

                let bsdName = IORegistryEntrySearchCFProperty(
                    service, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateRecursively)
                ) as? String
                result[bsdName ?? "disk-\(index)"] = counters
            }
            index += 1
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    /// Sum across all disks.
    public static func totals() -> DiskIOCounters {
        counters().values.reduce(into: DiskIOCounters()) { sum, disk in
            sum.bytesRead &+= disk.bytesRead
            sum.bytesWritten &+= disk.bytesWritten
            sum.readOperations &+= disk.readOperations
            sum.writeOperations &+= disk.writeOperations
        }
    }
}
