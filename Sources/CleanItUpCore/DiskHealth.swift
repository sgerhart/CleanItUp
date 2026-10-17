import Foundation

public enum SMARTStatus: String, Sendable {
    case verified
    case failing
    case notSupported
    case unknown

    init(diskutilValue: String?) {
        switch diskutilValue?.lowercased() {
        case "verified": self = .verified
        case "failing": self = .failing
        case "not supported": self = .notSupported
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .verified: return "Verified"
        case .failing: return "Failing"
        case .notSupported: return "Not supported"
        case .unknown: return "Unknown"
        }
    }
}

/// Detailed health counters reported by NVMe drives (all Apple SSDs).
public struct NVMeHealth: Sendable, Equatable {
    public var passed: Bool?
    public var temperatureCelsius: Int?
    /// Manufacturer's estimate of life used. 100 means the rated endurance is reached, not that the drive is dead.
    public var percentageUsed: Int?
    public var availableSparePercent: Int?
    public var dataReadBytes: UInt64?
    public var dataWrittenBytes: UInt64?
    public var powerOnHours: Int?
    public var powerCycles: Int?
    public var unsafeShutdowns: Int?
    public var mediaErrors: Int?
    public var criticalWarning: Int?
    public var source: String

    public init(source: String) {
        self.source = source
    }
}

public struct PhysicalDisk: Identifiable, Sendable {
    public var id: String { deviceIdentifier }
    public let deviceIdentifier: String
    public let name: String
    public let sizeBytes: Int64
    public let isSolidState: Bool
    public let isInternal: Bool
    public let busProtocol: String
    public let smart: SMARTStatus
    public var details: NVMeHealth?
}

public enum DiskHealthReader {
    static let diskutil = "/usr/sbin/diskutil"
    /// NVMe reports data in units of 1000 × 512-byte blocks.
    static let nvmeDataUnit: UInt64 = 512_000

    public static var smartctlPath: String? {
        ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/opt/homebrew/sbin/smartctl", "/usr/local/sbin/smartctl"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Reads SMART status for every physical disk. Slow (runs diskutil), so call off the main thread.
    public static func readAll() -> [PhysicalDisk] {
        guard let listData = Shell.run(diskutil, ["list", "-plist", "physical"]) else { return [] }
        let smartctl = smartctlPath
        return wholeDisks(fromListPlist: listData).compactMap { identifier in
            guard let infoData = Shell.run(diskutil, ["info", "-plist", identifier]),
                  var disk = disk(fromInfoPlist: infoData)
            else { return nil }
            if let smartctl, let json = Shell.run(smartctl, ["-a", "-j", identifier]),
               let health = nvmeHealth(fromSmartctlJSON: json) {
                disk.details = health
            }
            return disk
        }
    }

    static func plistDictionary(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func wholeDisks(fromListPlist data: Data) -> [String] {
        plistDictionary(data)?["WholeDisks"] as? [String] ?? []
    }

    static func disk(fromInfoPlist data: Data) -> PhysicalDisk? {
        guard let info = plistDictionary(data), let identifier = info["DeviceIdentifier"] as? String else { return nil }
        let size = (info["TotalSize"] as? NSNumber) ?? (info["Size"] as? NSNumber)
        var disk = PhysicalDisk(
            deviceIdentifier: identifier,
            name: (info["MediaName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? identifier,
            sizeBytes: size?.int64Value ?? 0,
            isSolidState: info["SolidState"] as? Bool ?? false,
            isInternal: info["Internal"] as? Bool ?? false,
            busProtocol: info["BusProtocol"] as? String ?? "",
            smart: SMARTStatus(diskutilValue: info["SMARTStatus"] as? String)
        )
        // Recent macOS versions expose NVMe counters directly; the key name warns they may change.
        if let keys = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] {
            disk.details = nvmeHealth(fromDiskutilKeys: keys)
        }
        return disk
    }

    static func nvmeHealth(fromDiskutilKeys keys: [String: Any]) -> NVMeHealth? {
        func int(_ key: String) -> Int? { (keys[key] as? NSNumber)?.intValue }
        func uint(_ key: String) -> UInt64? { (keys[key] as? NSNumber)?.uint64Value }
        func units(_ prefix: String) -> UInt64? {
            // Counters are 128-bit, split into _0 (low) and _1 (high) halves. The high half is zero in practice.
            guard let low = uint(prefix + "_0") else { return nil }
            let (bytes, overflow) = low.multipliedReportingOverflow(by: nvmeDataUnit)
            return overflow ? UInt64.max : bytes
        }

        var health = NVMeHealth(source: "macOS")
        if let raw = int("TEMPERATURE") {
            // NVMe reports Kelvin.
            health.temperatureCelsius = raw > 200 ? raw - 273 : raw
        }
        health.percentageUsed = int("PERCENTAGE_USED")
        health.availableSparePercent = int("AVAILABLE_SPARE")
        health.dataReadBytes = units("DATA_UNITS_READ")
        health.dataWrittenBytes = units("DATA_UNITS_WRITTEN")
        health.powerOnHours = int("POWER_ON_HOURS_0")
        health.powerCycles = int("POWER_CYCLES_0")
        health.unsafeShutdowns = int("UNSAFE_SHUTDOWNS_0")
        health.mediaErrors = int("MEDIA_ERRORS_0")
        health.criticalWarning = int("CRITICAL_WARNING")
        if let warning = health.criticalWarning {
            health.passed = warning == 0
        }
        return health == NVMeHealth(source: "macOS") ? nil : health
    }

    static func nvmeHealth(fromSmartctlJSON data: Data) -> NVMeHealth? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var health = NVMeHealth(source: "smartctl")
        health.passed = (json["smart_status"] as? [String: Any])?["passed"] as? Bool
        health.temperatureCelsius = ((json["temperature"] as? [String: Any])?["current"] as? NSNumber)?.intValue
        health.powerOnHours = ((json["power_on_time"] as? [String: Any])?["hours"] as? NSNumber)?.intValue
        health.powerCycles = (json["power_cycle_count"] as? NSNumber)?.intValue

        if let log = json["nvme_smart_health_information_log"] as? [String: Any] {
            func int(_ key: String) -> Int? { (log[key] as? NSNumber)?.intValue }
            func bytes(_ key: String) -> UInt64? {
                guard let units = (log[key] as? NSNumber)?.uint64Value else { return nil }
                let (value, overflow) = units.multipliedReportingOverflow(by: nvmeDataUnit)
                return overflow ? UInt64.max : value
            }
            health.criticalWarning = int("critical_warning")
            health.temperatureCelsius = health.temperatureCelsius ?? int("temperature")
            health.availableSparePercent = int("available_spare")
            health.percentageUsed = int("percentage_used")
            health.dataReadBytes = bytes("data_units_read")
            health.dataWrittenBytes = bytes("data_units_written")
            health.powerCycles = int("power_cycles") ?? health.powerCycles
            health.powerOnHours = int("power_on_hours") ?? health.powerOnHours
            health.unsafeShutdowns = int("unsafe_shutdowns")
            health.mediaErrors = int("media_errors")
        }
        return health == NVMeHealth(source: "smartctl") ? nil : health
    }
}
