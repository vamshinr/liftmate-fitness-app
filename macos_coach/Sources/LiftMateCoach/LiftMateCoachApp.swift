import SwiftUI

@main
struct LiftMateCoachApp: App {
    var body: some Scene {
        WindowGroup("LiftMate Coach") {
            ContentView()
                .frame(minWidth: 720, minHeight: 1100)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}
