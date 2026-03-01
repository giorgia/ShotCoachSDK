import SwiftUI

/// A pulsing green ring that appears when the frame is ready to capture.
/// The animation starts when `isReady` becomes `true` and stops when it becomes `false`.
public struct ReadyIndicator: View {

    let isReady: Bool

    @State private var pulsing = false

    public init(isReady: Bool) {
        self.isReady = isReady
    }

    public var body: some View {
        Circle()
            .strokeBorder(Color.green, lineWidth: 3)
            .frame(width: 72, height: 72)
            .scaleEffect(pulsing ? 1.1 : 1.0)
            .opacity(isReady ? 1 : 0)
            .task(id: isReady) {
                if isReady {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                } else {
                    withAnimation(.default) {
                        pulsing = false
                    }
                }
            }
    }
}
