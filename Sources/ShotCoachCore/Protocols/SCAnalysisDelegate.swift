import Foundation

/// Receives real-time frame analysis and post-capture cloud analysis events.
/// All callbacks are dispatched on @MainActor.
@MainActor
public protocol SCAnalysisDelegate: AnyObject {
    /// Called every time SCFrameAnalyzer produces a new aggregated frame result
    /// (throttled to ~1 call per 1500 ms).
    func analyzer(_ analyzer: SCFrameAnalyzer, didUpdate result: SCFrameResult)

    /// Called after post-capture cloud analysis completes.
    /// `cloudResult` is nil if the cloud provider was not configured or failed.
    func analyzer(_ analyzer: SCFrameAnalyzer, didComplete photo: SCPhoto, cloudResult: SCCloudResult?)
}

public extension SCAnalysisDelegate {
    func analyzer(_ analyzer: SCFrameAnalyzer, didUpdate result: SCFrameResult) {}
    func analyzer(_ analyzer: SCFrameAnalyzer, didComplete photo: SCPhoto, cloudResult: SCCloudResult?) {}
}
