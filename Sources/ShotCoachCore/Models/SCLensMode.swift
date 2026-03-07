/// The physical camera lens to use for capture and preview.
///
/// `ultraWide` maps to `AVCaptureDevice.DeviceType.builtInUltraWideCamera`
/// (available on iPhone 11 and later). On devices that lack an ultra-wide lens,
/// `ShotCoach.switchLens(_:)` is a no-op and the SDK stays on `.main`.
public enum SCLensMode: String, Codable, Sendable, CaseIterable {
    /// Primary (1×) wide-angle lens. Always available.
    case main
    /// Ultra-wide (0.5×) lens. Available on iPhone 11+.
    case ultraWide
}
