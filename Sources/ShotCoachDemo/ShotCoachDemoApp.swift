import SwiftUI
import ShotCoachCore
import ShotCoachUI

@main
struct ShotCoachDemoApp: App {

    /// One shared session store threaded through the whole app via environment.
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

// MARK: - ContentView

/// Root view: always shows the main UI.
/// On first launch (no key stored) it surfaces APIKeySetupView as a dismissable
/// sheet — the user can skip it and still use all on-device analysis features.
private struct ContentView: View {

    /// True on first launch when no key is stored; becomes false once dismissed.
    @State private var showKeySetup = SCKeychainService.load(key: "openai_api_key") == nil

    var body: some View {
        MainTabView()
            .sheet(isPresented: $showKeySetup) {
                APIKeySetupView { showKeySetup = false }
            }
    }
}

// MARK: - MainTabView

/// Two-tab shell: Shoot (category picker) → camera, Gallery → results.
private struct MainTabView: View {
    var body: some View {
        TabView {
            CategoryPickerView()
                .tabItem { Label("Shoot", systemImage: "camera.fill") }

            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.stack.fill") }
        }
    }
}
