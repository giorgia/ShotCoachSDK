import Foundation
import CoreVideo

/// A camera frame passed to on-device analysis rules.
/// CVPixelBuffer handling is added in the Engine implementation.
public struct SCFrame: Sendable {
    public let timestamp: Double

    public init(timestamp: Double) {
        self.timestamp = timestamp
    }
}
