import AppKit
import Charts
import CleanItUpCore
import SwiftUI

struct StorageView: View {
    let model: StorageModel
    @State private var pendingTrash: SizedItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                volumesSection
                Divider()
                scanSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Storage")
        .onAppear {
            model.refreshVolumes()
            if model.result == nil && !model.isScanning {
                model.scan(model.root)
            }
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { item in
            Button("Move \(item.name) to Trash", role: .destructive) { model.trash(item) }
        } message: { item in
            Text("\(ByteFormat.string(item.size)) will move to the Trash. You can put it back from there until you empty the Trash.")
        }
    }

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disks").font(.title2.bold())
            ForEach(model.volumes) { volume in
                VolumeRow(volume: volume)
            }
        }
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(model.history.isEmpty || model.isScanning)
                VStack(alignment: .leading) {
                    Text(model.root.lastPathComponent.isEmpty ? model.root.path : model.root.lastPathComponent)
                        .font(.title2.bold())
                    Text(model.root.path).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose Folder…") { chooseFolder() }
                if model.isScanning {
                    Button("Stop") { model.cancel() }
                } else {
                    Button("Rescan") { model.scan(model.root) }
                }
            }

            if let message = model.message {
                Text(message).foregroundStyle(.secondary)
            }

            if model.isScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    if let progress = model.progress {
                        Text("\(progress.itemsSeen.formatted()) items, \(ByteFormat.string(progress.bytesCounted)) so far")
                            .monospacedDigit()
                    } else {
                        Text("Scanning…")
                    }
                }
                .foregroundStyle(.secondary)
            }

            if let result = model.result {
                results(result)
            }
        }
    }

    @ViewBuilder
    private func results(_ result: ScanResult) -> some View {
        if result.unreadableCount > 0 {
            FullDiskAccessBanner(unreadableCount: result.unreadableCount)
        }
        Text("\(ByteFormat.string(result.totalBytes)) in \(result.fileCount.formatted()) files")
            .foregroundStyle(.secondary)

        let top = Array(result.children.prefix(12).filter { $0.size > 0 })
        if !top.isEmpty {
            Chart(top) { item in
                BarMark(
                    x: .value("Size (GB)", Double(item.size) / 1_000_000_000),
                    y: .value("Item", item.name)
                )
                .foregroundStyle(item.isDirectory ? Color.accentColor : Color.orange)
            }
            .chartXAxisLabel("GB")
            .frame(height: CGFloat(top.count) * 26 + 30)
        }

        Text("Contents").font(.headline).padding(.top, 8)
        VStack(spacing: 0) {
            ForEach(result.children.filter { $0.size > 0 }) { item in
                ItemRow(item: item, total: result.totalBytes, onOpen: item.isDirectory ? { model.open(item.url) } : nil, onTrash: { pendingTrash = item })
                Divider()
            }
        }

        if !result.largestFiles.isEmpty {
            Text("Largest files").font(.headline).padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(result.largestFiles) { item in
                    ItemRow(item: item, total: result.totalBytes, showPath: true, onOpen: nil, onTrash: { pendingTrash = item })
                    Divider()
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.root
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url)
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                Text(volume.name).bold()
                Spacer()
                Text("\(ByteFormat.string(volume.availableBytes)) free of \(ByteFormat.string(volume.totalBytes))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: volume.usedFraction)
                .tint(volume.usedFraction > 0.9 ? Color.red : volume.usedFraction > 0.75 ? Color.orange : Color.accentColor)
        }
    }
}

struct ItemRow: View {
    let item: SizedItem
    let total: Int64
    var showPath = false
    let onOpen: (() -> Void)?
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                if showPath {
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if total > 0 {
                Text(Double(item.size) / Double(total), format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(ByteFormat.string(item.size))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Menu {
                if let onOpen { Button("Look Inside", action: onOpen) }
                Button("Show in Finder") { revealInFinder(item.url) }
                Divider()
                Button("Move to Trash…", role: .destructive, action: onTrash)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen?() }
    }
}
