import Foundation
import CoreVideo

/// A camera frame passed to on-device analysis rules.
public struct SCFrame: @unchecked Sendable {
    public let timestamp: Double
    public let pixelBuffer: CVPixelBuffer

    public init(timestamp: Double, pixelBuffer: CVPixelBuffer) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
    }
}
