import Charts
import CleanItUpCore
import SwiftUI

struct HealthView: View {
    let health: HealthModel
    let activity: ActivityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Drive health").font(.title2.bold())
                    Spacer()
                    if health.isLoading { ProgressView().controlSize(.small) }
                    Button("Refresh") { health.refresh() }.disabled(health.isLoading)
                }
                ForEach(health.disks) { disk in
                    DiskCard(disk: disk)
                }
                if !health.isLoading && health.disks.isEmpty {
                    Text("No physical disks found.").foregroundStyle(.secondary)
                }
                if !health.hasSmartctl && health.disks.contains(where: { $0.details == nil }) {
                    Text("For wear, temperature and lifetime writes on drives macOS doesn't report, install smartmontools with `brew install smartmontools` and refresh.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Divider()
                activitySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Disk Health")
        .onAppear {
            if health.disks.isEmpty { health.refresh() }
            activity.start()
        }
        .onDisappear { activity.stop() }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live activity").font(.title2.bold())
            let latest = activity.samples.last
            HStack(spacing: 32) {
                Stat(title: "Reading", value: ByteFormat.rate(latest?.readRate ?? 0), color: .blue)
                Stat(title: "Writing", value: ByteFormat.rate(latest?.writeRate ?? 0), color: .orange)
                Stat(title: "Written since startup", value: ByteFormat.string(activity.totals.bytesWritten), color: .secondary)
            }
            Chart {
                ForEach(activity.samples) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("MB/s", sample.readRate / 1_000_000), series: .value("Kind", "Read"))
                        .foregroundStyle(by: .value("Kind", "Read"))
                    LineMark(x: .value("Time", sample.date), y: .value("MB/s", sample.writeRate / 1_000_000), series: .value("Kind", "Write"))
                        .foregroundStyle(by: .value("Kind", "Write"))
                }
            }
            .chartForegroundStyleScale(["Read": Color.blue, "Write": Color.orange])
            .chartYAxisLabel("MB/s")
            .frame(height: 180)

            Text("Which apps and agents are using the disk").font(.headline).padding(.top, 8)
            Text("Processes you started, busiest first. Totals count since each process launched.")
                .font(.callout).foregroundStyle(.secondary)
            Table(Array(activity.processes.prefix(30))) {
                TableColumn("Process") { process in
                    Text(process.name).help(process.path)
                }
                TableColumn("Reading") { process in
                    Text(ByteFormat.rate(process.readRate)).monospacedDigit()
                }
                .width(90)
                TableColumn("Writing") { process in
                    Text(ByteFormat.rate(process.writeRate)).monospacedDigit()
                }
                .width(90)
                TableColumn("Total read") { process in
                    Text(ByteFormat.string(process.totalRead)).monospacedDigit()
                }
                .width(90)
                TableColumn("Total written") { process in
                    Text(ByteFormat.string(process.totalWritten)).monospacedDigit()
                }
                .width(100)
            }
            .frame(minHeight: 320)
        }
    }
}

struct Stat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
        }
    }
}

struct DiskCard: View {
    let disk: PhysicalDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                Text(disk.name).font(.headline)
                Text("\(disk.deviceIdentifier) · \(ByteFormat.string(disk.sizeBytes))\(disk.busProtocol.isEmpty ? "" : " · " + disk.busProtocol)\(disk.isSolidState ? " · SSD" : "")")
                    .foregroundStyle(.secondary)
                Spacer()
                SmartBadge(status: disk.smart)
            }
            Text(verdict).foregroundStyle(.secondary)

            if let details = disk.details {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        Metric(title: "Life used", value: details.percentageUsed.map { "\($0)%" }, warn: (details.percentageUsed ?? 0) >= 80)
                        Metric(title: "Spare blocks", value: details.availableSparePercent.map { "\($0)%" }, warn: (details.availableSparePercent ?? 100) < 20)
                        Metric(title: "Temperature", value: details.temperatureCelsius.map { "\($0) °C" }, warn: (details.temperatureCelsius ?? 0) >= 70)
                    }
                    GridRow {
                        Metric(title: "Written over lifetime", value: details.dataWrittenBytes.map { ByteFormat.string($0) })
                        Metric(title: "Read over lifetime", value: details.dataReadBytes.map { ByteFormat.string($0) })
                        Metric(title: "Powered on", value: details.powerOnHours.map { "\($0.formatted()) hours" })
                    }
                    GridRow {
                        Metric(title: "Media errors", value: details.mediaErrors.map { "\($0)" }, warn: (details.mediaErrors ?? 0) > 0)
                        Metric(title: "Unsafe shutdowns", value: details.unsafeShutdowns.map { "\($0.formatted())" })
                        Metric(title: "Power cycles", value: details.powerCycles.map { "\($0.formatted())" })
                    }
                }
                Text("Source: \(details.source)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var verdict: String {
        if disk.smart == .failing || disk.details?.passed == false || (disk.details?.criticalWarning ?? 0) != 0 {
            return "This drive is reporting a problem. Back up now and plan to replace it."
        }
        if let used = disk.details?.percentageUsed, used >= 80 {
            return "Healthy, but it has used most of its rated write endurance. Keep backups current."
        }
        switch disk.smart {
        case .verified: return "Healthy. The drive's self-check passes."
        case .notSupported: return "This drive doesn't report SMART status to macOS. External USB drives often don't."
        default: return "Health status unavailable."
        }
    }
}

struct SmartBadge: View {
    let status: SMARTStatus

    var body: some View {
        Label("SMART: \(status.label)", systemImage: icon)
            .font(.callout.bold())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var icon: String {
        switch status {
        case .verified: return "checkmark.seal.fill"
        case .failing: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .verified: return .green
        case .failing: return .red
        default: return .secondary
        }
    }
}

struct Metric: View {
    let title: String
    let value: String?
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").monospacedDigit().foregroundStyle(warn ? Color.red : Color.primary)
        }
    }
}
