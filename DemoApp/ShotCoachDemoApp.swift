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

/// Root view. `CategoryPickerView` owns first-launch key-setup presentation
/// so there is only one sheet controller for the API key in the hierarchy.
private struct ContentView: View {
    var body: some View {
        CategoryPickerView()
            .preferredColorScheme(.dark)
    }
}
