import AppKit
import CleanItUpCore
import SwiftUI

struct ICloudView: View {
    let model: ICloudModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("iCloud Drive").font(.title2.bold())
                    Spacer()
                    if model.isScanning { ProgressView().controlSize(.small) }
                    Button("Rescan") { model.scan() }.disabled(model.isScanning)
                }
                if let message = model.message {
                    Text(message).foregroundStyle(.secondary)
                }
                if let summary = model.summary {
                    content(summary)
                } else if model.isScanning {
                    Text("Reading iCloud Drive…").foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("iCloud Drive")
        .onAppear { if model.summary == nil { model.scan() } }
    }

    @ViewBuilder
    private func content(_ summary: ICloudSummary) -> some View {
        if !summary.isAvailable {
            Text("iCloud Drive isn't turned on for this Mac, or CleanItUp can't see it yet.")
                .foregroundStyle(.secondary)
        } else {
            if summary.unreadableCount > 0 {
                FullDiskAccessBanner(unreadableCount: summary.unreadableCount)
            }
            HStack(spacing: 32) {
                Stat(title: "In iCloud Drive", value: ByteFormat.string(summary.logicalBytes), color: .primary)
                Stat(title: "Taking space on this Mac", value: ByteFormat.string(summary.localBytes), color: .blue)
                Stat(title: "Stored only in iCloud", value: "\(summary.cloudOnlyCount.formatted()) files", color: .secondary)
            }
            Text(summary.desktopAndDocumentsSynced
                 ? "Your Desktop and Documents folders are synced to iCloud, so they're included here."
                 : "Desktop and Documents aren't synced to iCloud.")
                .font(.callout).foregroundStyle(.secondary)
            Text("\"Free Up Space\" keeps a file in iCloud and removes only the copy on this Mac. It downloads again when you open it.")
                .font(.callout).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(summary.folders) { folder in
                    ICloudRow(folder: folder, model: model)
                    Divider()
                }
            }
        }
    }
}

struct ICloudRow: View {
    let folder: ICloudFolder
    let model: ICloudModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                Text("\(folder.fileCount.formatted()) files · \(folder.cloudOnlyCount.formatted()) only in iCloud")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormat.string(folder.logicalBytes)).monospacedDigit()
                Text("\(ByteFormat.string(folder.localBytes)) on Mac").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 120, alignment: .trailing)
            Menu {
                Button("Free Up Space") { model.removeLocalCopy(folder) }
                    .disabled(folder.localBytes == 0)
                Button("Download Now") { model.download(folder) }
                    .disabled(folder.cloudOnlyCount == 0)
                Divider()
                Button("Show in Finder") { revealInFinder(folder.url) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}
