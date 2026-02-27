import Foundation

/// A captured photo with its on-device frame result and optional cloud analysis.
public struct SCPhoto: Codable, Sendable {
    public let imageData: Data
    public let frameResult: SCFrameResult?
    public let cloudResult: SCCloudResult?

    public init(imageData: Data, frameResult: SCFrameResult? = nil, cloudResult: SCCloudResult? = nil) {
        self.imageData = imageData
        self.frameResult = frameResult
        self.cloudResult = cloudResult
    }
}
