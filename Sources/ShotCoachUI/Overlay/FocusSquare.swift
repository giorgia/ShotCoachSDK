import SwiftUI

/// Animated corner-bracket focus indicator, styled after the native iOS camera focus square.
///
/// Appears at the tap point with a scale-in entrance and fades out when `focusPoint` is
/// cleared (wrap the nil assignment in `withAnimation` at the call site).
struct FocusSquare: View {

    /// Tap location in view-local coordinates, or `nil` when hidden.
    let focusPoint: CGPoint?
    let size: CGSize   // kept for interface compatibility; layout is self-contained

    var body: some View {
        if let point = focusPoint {
            bracketsShape
                .position(point)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 1.25).combined(with: .opacity),
                        removal:   .opacity
                    )
                )
        }
    }

    // MARK: - Private

    private var bracketsShape: some View {
        Canvas { context, _ in
            // Canvas coordinate space: (0,0) top-left → (side,side) bottom-right.
            // Previous implementation used origin = (-half,-half) which placed all paths
            // outside the canvas bounds and rendered nothing.
            let side: CGFloat      = 72
            let arm:  CGFloat      = 18
            let lineWidth: CGFloat = 2.5

            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                // top-left
                (CGPoint(x: 0,        y: arm),
                 CGPoint(x: 0,        y: 0),
                 CGPoint(x: arm,      y: 0)),
                // top-right
                (CGPoint(x: side - arm, y: 0),
                 CGPoint(x: side,       y: 0),
                 CGPoint(x: side,       y: arm)),
                // bottom-right
                (CGPoint(x: side,       y: side - arm),
                 CGPoint(x: side,       y: side),
                 CGPoint(x: side - arm, y: side)),
                // bottom-left
                (CGPoint(x: arm,  y: side),
                 CGPoint(x: 0,    y: side),
                 CGPoint(x: 0,    y: side - arm)),
            ]

            // Native camera uses a warm amber/gold — approximate with the system yellow.
            let color = Color(red: 1.0, green: 0.82, blue: 0.0)
            for (a, b, c) in corners {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                path.addLine(to: c)
                context.stroke(path,
                               with: .color(color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
            }
        }
        .frame(width: 72, height: 72)
    }
}
