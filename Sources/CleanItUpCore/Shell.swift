import Foundation

enum Shell {
    /// Runs a tool and returns its standard output, or nil if it couldn't be launched.
    /// The exit status is ignored because tools like smartctl use non-zero codes for warnings.
    static func run(_ path: String, _ arguments: [String]) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
