import SwiftUI

/// A pulsing green ring that appears when the frame is ready to capture.
/// The animation starts when `isReady` becomes `true` and stops cleanly when it returns `false`.
public struct ReadyIndicator: View {

    let isReady: Bool

    public init(isReady: Bool) {
        self.isReady = isReady
    }

    public var body: some View {
        Circle()
            .strokeBorder(Color.green, lineWidth: 3)
            .frame(width: 72, height: 72)
            .scaleEffect(isReady ? 1.1 : 1.0)
            .opacity(isReady ? 1 : 0)
            // Declarative animation driven by isReady — no @State needed.
            // SwiftUI restarts the repeatForever when isReady becomes true
            // and replaces it with .default when isReady becomes false.
            .animation(
                isReady
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isReady
            )
    }
}
