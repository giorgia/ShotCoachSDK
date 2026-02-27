import Foundation

/// On-device frame analysis rule. Each implementation must complete in <80ms.
/// Never import SwiftUI, UIKit, or AppKit in conforming types.
public protocol SCFrameRule: Sendable {}
