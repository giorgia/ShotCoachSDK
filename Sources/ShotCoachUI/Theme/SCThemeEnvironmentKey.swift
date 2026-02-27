import SwiftUI

struct SCThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = SCTheme()
}

public extension EnvironmentValues {
    var scTheme: SCTheme {
        get { self[SCThemeEnvironmentKey.self] }
        set { self[SCThemeEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func theme(_ theme: SCTheme) -> some View {
        environment(\.scTheme, theme)
    }
}
