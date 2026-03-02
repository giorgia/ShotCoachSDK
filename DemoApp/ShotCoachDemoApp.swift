import SwiftUI
import ShotCoachCore

@main
struct ShotCoachDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - ContentView

/// Root view. Surfaces `APIKeySetupView` on first launch when no key is stored.
/// The user can skip key setup — live on-device analysis always runs without a key.
private struct ContentView: View {

    @State private var showKeySetup = SCKeychainService.load(key: "openai_api_key") == nil

    var body: some View {
        CategoryPickerView()
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showKeySetup) {
                APIKeySetupView { showKeySetup = false }
            }
    }
}
