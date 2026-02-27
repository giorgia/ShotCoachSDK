import Foundation

/// Receives real-time frame analysis and post-capture cloud analysis events.
/// All callbacks are dispatched on @MainActor.
@MainActor
public protocol SCAnalysisDelegate: AnyObject {}
