import SwiftUI
import AVFoundation

/// Internal `UIViewRepresentable` that renders an `AVCaptureSession` preview layer.
/// On macOS (where there is no `UIViewRepresentable`) this renders an opaque black rectangle.
#if canImport(UIKit)
import UIKit

struct AVCapturePreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session      = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {}

    // MARK: - PreviewUIView

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#else

// MARK: - macOS stub (swift build / swift test compatibility)

struct AVCapturePreviewView: View {
    let session: AVCaptureSession
    var body: some View { Color.black }
}

#endif
