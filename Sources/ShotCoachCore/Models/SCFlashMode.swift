/// Controls the camera flash used when capturing a still photo.
public enum SCFlashMode: String, Codable, Sendable, CaseIterable {
    case off
    case auto
    case on

    /// SF Symbol name representing this flash state.
    public var symbolName: String {
        switch self {
        case .off:  return "bolt.slash.fill"
        case .auto: return "bolt.badge.a.fill"
        case .on:   return "bolt.fill"
        }
    }
}
