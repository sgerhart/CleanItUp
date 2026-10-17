import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case storage, health, cleanup, icloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storage: return "Storage"
        case .health: return "Disk Health"
        case .cleanup: return "Cleanup"
        case .icloud: return "iCloud Drive"
        }
    }

    var systemImage: String {
        switch self {
        case .storage: return "internaldrive"
        case .health: return "heart.text.square"
        case .cleanup: return "trash"
        case .icloud: return "icloud"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .storage
    // Models live here so results survive switching between sections.
    @State private var storage = StorageModel()
    @State private var health = HealthModel()
    @State private var activity = ActivityModel()
    @State private var cleanup = CleanupModel()
    @State private var icloud = ICloudModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            switch selection ?? .storage {
            case .storage: StorageView(model: storage)
            case .health: HealthView(health: health, activity: activity)
            case .cleanup: CleanupView(model: cleanup)
            case .icloud: ICloudView(model: icloud)
            }
        }
    }
}

enum SystemSettings {
    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FullDiskAccessBanner: View {
    let unreadableCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(unreadableCount) folder\(unreadableCount == 1 ? "" : "s") couldn't be read").bold()
                Text("Give CleanItUp Full Disk Access in System Settings, then scan again to see everything.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { SystemSettings.openFullDiskAccess() }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
