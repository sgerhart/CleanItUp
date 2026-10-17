import SwiftUI

@main
struct CleanItUpApp: App {
    var body: some Scene {
        WindowGroup("CleanItUp") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1150, height: 780)
    }
}
