import Foundation
import CoreVideo

/// A camera frame passed to on-device analysis rules.
/// SAFETY: @unchecked Sendable because CVPixelBuffer is a CF reference type.
/// Rules that sample pixel data must acquire a .readOnly lock via CVPixelBufferLockBaseAddress.
/// Multiple concurrent .readOnly locks on the same buffer are safe per CoreVideo documentation;
/// rules must never acquire a writable lock ([]) from within evaluate(_:).
public struct SCFrame: @unchecked Sendable, Codable {
    public let timestamp: Double
    public let pixelBuffer: CVPixelBuffer

    public init(timestamp: Double, pixelBuffer: CVPixelBuffer) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
    }

    // MARK: - Codable
    // pixelBuffer is excluded: a live capture resource cannot be round-tripped through data.

    private enum CodingKeys: String, CodingKey {
        case timestamp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(Double.self, forKey: .timestamp)
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "SCFrame cannot be decoded: CVPixelBuffer is a live capture resource"
            )
        )
    }
}
