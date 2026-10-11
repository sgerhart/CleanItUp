import AppKit
import CleanItUpCore
import SwiftUI

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.hasScanned && !model.isScanning {
                ContentUnavailableView {
                    Label("Find space to free up", systemImage: "sparkles")
                } description: {
                    Text("CleanItUp looks for caches, build leftovers, package downloads and old files. You choose what goes, and everything moves to the Trash so you can put it back.")
                } actions: {
                    Button("Scan") { model.scan() }.buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
        .navigationTitle("Cleanup")
        .toolbar {
            if model.isScanning {
                Button("Stop") { model.cancel() }
            } else {
                Button("Scan Again") { model.scan() }.disabled(!model.hasScanned)
            }
        }
        .confirmationDialog("Move \(model.selected.count) items to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { model.trashSelected() }
        } message: {
            Text("This frees \(ByteFormat.string(model.selectedBytes)) once you empty the Trash. Until then you can put anything back from the Trash.")
        }
    }

    private var list: some View {
        List {
            if model.isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking \(model.phase.lowercased())…").foregroundStyle(.secondary)
                }
            }
            if let message = model.message {
                Text(message).foregroundStyle(.secondary)
            }
            ForEach(CleanupCategory.allCases) { category in
                let items = model.items(in: category)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            CleanupRow(item: item, isOn: Binding(
                                get: { model.selected.contains(item.url) },
                                set: { on in
                                    if on { model.selected.insert(item.url) } else { model.selected.remove(item.url) }
                                }
                            ))
                        }
                    } header: {
                        CategoryHeader(category: category, items: items, model: model)
                    }
                }
            }
            if model.hasScanned && !model.isScanning && model.items.isEmpty {
                Text("Nothing worth cleaning was found.").foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(model.selected.count) selected · \(ByteFormat.string(model.selectedBytes))")
                    .monospacedDigit()
                Spacer()
                Button("Move to Trash…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty || model.isScanning)
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct CategoryHeader: View {
    let category: CleanupCategory
    let items: [CleanupItem]
    let model: CleanupModel

    var body: some View {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let allOn = items.allSatisfy { model.selected.contains($0.url) }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(category.title).font(.headline)
                if category.safety == .review {
                    Text("Review first").font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text(ByteFormat.string(total)).monospacedDigit()
                Button(allOn ? "Select None" : "Select All") { model.toggleAll(in: category, on: !allOn) }
                    .buttonStyle(.link)
            }
            Text(category.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CleanupRow: View {
    let item: CleanupItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.note.map { "\(item.name) — \($0)" } ?? item.name).lineLimit(1)
                Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let modified = item.modified {
                Text(modified, format: .dateTime.year().month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(ByteFormat.string(item.size))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Button { revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
    }
}
