import Foundation

/// Runs all SCFrameRule instances concurrently against incoming camera frames.
/// Throttled to 1500ms intervals via actor-isolated timestamp.
public actor SCFrameAnalyzer {
    public init() {}
}
