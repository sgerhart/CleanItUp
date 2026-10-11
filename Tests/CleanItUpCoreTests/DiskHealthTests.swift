@testable import CleanItUpCore
import XCTest

final class DiskHealthTests: XCTestCase {
    func testParsesWholeDisks() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>WholeDisks</key><array><string>disk0</string><string>disk4</string></array>
        </dict></plist>
        """
        XCTAssertEqual(DiskHealthReader.wholeDisks(fromListPlist: Data(plist.utf8)), ["disk0", "disk4"])
    }

    func testParsesDiskInfoWithNVMeKeys() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>disk0</string>
          <key>MediaName</key><string>APPLE SSD AP1024Z</string>
          <key>TotalSize</key><integer>1000555581440</integer>
          <key>SolidState</key><true/>
          <key>Internal</key><true/>
          <key>BusProtocol</key><string>Apple Fabric</string>
          <key>SMARTStatus</key><string>Verified</string>
          <key>SMARTDeviceSpecificKeysMayVaryNotGuaranteed</key>
          <dict>
            <key>TEMPERATURE</key><integer>309</integer>
            <key>PERCENTAGE_USED</key><integer>3</integer>
            <key>AVAILABLE_SPARE</key><integer>100</integer>
            <key>DATA_UNITS_WRITTEN_0</key><integer>100000000</integer>
            <key>DATA_UNITS_WRITTEN_1</key><integer>0</integer>
            <key>POWER_ON_HOURS_0</key><integer>1234</integer>
            <key>MEDIA_ERRORS_0</key><integer>0</integer>
            <key>CRITICAL_WARNING</key><integer>0</integer>
          </dict>
        </dict></plist>
        """
        let disk = try XCTUnwrap(DiskHealthReader.disk(fromInfoPlist: Data(plist.utf8)))
        XCTAssertEqual(disk.deviceIdentifier, "disk0")
        XCTAssertEqual(disk.name, "APPLE SSD AP1024Z")
        XCTAssertEqual(disk.smart, .verified)
        XCTAssertTrue(disk.isSolidState)
        let details = try XCTUnwrap(disk.details)
        XCTAssertEqual(details.temperatureCelsius, 36)
        XCTAssertEqual(details.percentageUsed, 3)
        XCTAssertEqual(details.dataWrittenBytes, 51_200_000_000_000)
        XCTAssertEqual(details.powerOnHours, 1234)
        XCTAssertEqual(details.passed, true)
    }

    func testDiskWithoutSMART() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>disk4</string>
          <key>MediaName</key><string></string>
          <key>Size</key><integer>500000000000</integer>
          <key>SMARTStatus</key><string>Not Supported</string>
        </dict></plist>
        """
        let disk = try XCTUnwrap(DiskHealthReader.disk(fromInfoPlist: Data(plist.utf8)))
        XCTAssertEqual(disk.name, "disk4")
        XCTAssertEqual(disk.smart, .notSupported)
        XCTAssertNil(disk.details)
    }

    func testParsesSmartctlJSON() throws {
        let json = """
        {
          "smart_status": {"passed": true},
          "temperature": {"current": 41},
          "power_on_time": {"hours": 2000},
          "nvme_smart_health_information_log": {
            "critical_warning": 0, "temperature": 41, "available_spare": 99,
            "percentage_used": 12, "data_units_read": 2000, "data_units_written": 1000,
            "power_cycles": 300, "power_on_hours": 2000, "unsafe_shutdowns": 7, "media_errors": 0
          }
        }
        """
        let health = try XCTUnwrap(DiskHealthReader.nvmeHealth(fromSmartctlJSON: Data(json.utf8)))
        XCTAssertEqual(health.passed, true)
        XCTAssertEqual(health.temperatureCelsius, 41)
        XCTAssertEqual(health.percentageUsed, 12)
        XCTAssertEqual(health.dataWrittenBytes, 512_000_000)
        XCTAssertEqual(health.unsafeShutdowns, 7)
        XCTAssertEqual(health.source, "smartctl")
    }
}
