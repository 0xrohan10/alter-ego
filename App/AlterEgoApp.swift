import SwiftUI
import UIKit

@main @MainActor struct AlterEgoApp: App {
    @StateObject private var manager = JobManager()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            CheckInView(manager: manager)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true; manager.setForeground(scenePhase == .active) }
                .onChange(of: scenePhase) { phase in manager.setForeground(phase == .active) }
        }
    }
}
