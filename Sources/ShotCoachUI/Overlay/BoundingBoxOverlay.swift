import SwiftUI

/// Draws normalized bounding boxes over a view's frame.
/// Coordinates are in unit space (0...1) on both axes, anchored to the view's bounds,
/// with the **top-left as the origin** (UIKit/SwiftUI convention).
///
/// > Important: Vision framework observations use a **bottom-left** origin. Flip the Y-axis
/// > before passing Vision rects:
/// > ```swift
/// > let flipped = obs.boundingBox.applying(
/// >     CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1))
/// > ```
///
/// ```swift
/// cameraPreview
///     .overlay(BoundingBoxOverlay(boxes: normalizedRects, color: .yellow))
/// ```
public struct BoundingBoxOverlay: View {

    let boxes: [CGRect]
    let color: Color

    /// - Parameters:
    ///   - boxes: Bounding rects in normalized unit space (0...1), top-left origin.
    ///   - color: Stroke color for the boxes. Default: `.yellow`.
    public init(boxes: [CGRect], color: Color = .yellow) {
        self.boxes = boxes
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            ForEach(boxes.indices, id: \.self) { i in
                let box  = boxes[i]
                let rect = CGRect(
                    x:      box.minX  * geo.size.width,
                    y:      box.minY  * geo.size.height,
                    width:  box.width * geo.size.width,
                    height: box.height * geo.size.height
                )
                Rectangle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}
