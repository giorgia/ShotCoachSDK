import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit

/// Internal `UIViewRepresentable` that renders an `AVCaptureSession` preview layer.
struct AVCapturePreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    /// Called with `(layerPoint, devicePoint)`:
    /// - `layerPoint` — tap location in view/screen coordinates, use directly for UI.
    /// - `devicePoint` — normalized (0–1) AVFoundation device-space point, use for focus.
    var onTap: ((CGPoint, CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session      = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let gr = UITapGestureRecognizer(target: context.coordinator,
                                        action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(gr)
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: AVCapturePreviewView

        init(parent: AVCapturePreviewView) { self.parent = parent }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let previewView = gr.view as? PreviewUIView else { return }
            let layerPoint  = gr.location(in: gr.view)
            let devicePoint = previewView.previewLayer
                .captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onTap?(layerPoint, devicePoint)
        }
    }

    // MARK: - PreviewUIView

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
