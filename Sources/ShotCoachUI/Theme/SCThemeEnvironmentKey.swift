import SwiftUI

public extension EnvironmentValues {
    @Entry var scTheme: SCTheme = SCTheme()
}

public extension View {
    func theme(_ theme: SCTheme) -> some View {
        environment(\.scTheme, theme)
    }
}
