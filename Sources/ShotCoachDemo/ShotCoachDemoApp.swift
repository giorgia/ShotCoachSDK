import SwiftUI
import ShotCoachCore
import ShotCoachUI

// Add @main when compiling as a standalone iOS app target in Xcode.
struct ShotCoachDemoApp: App {
    var body: some Scene {
        WindowGroup {
            CategoryPickerView()
        }
    }
}
