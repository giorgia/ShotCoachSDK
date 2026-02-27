import Foundation

/// On-device frame analysis rule. Each implementation must complete in <80ms.
/// Never import SwiftUI, UIKit, or AppKit in conforming types.
public protocol SCFrameRule: Sendable {
    var ruleID: String { get }
    func evaluate(_ frame: SCFrame) async -> SCRuleResult
    var feedbackMessage: String { get }
    var severity: SCRuleSeverity { get }
}

public extension SCFrameRule {
    var feedbackMessage: String { "" }
    var severity: SCRuleSeverity { .warning }
    var ruleID: String { String(describing: type(of: self)) }
    func evaluate(_ frame: SCFrame) async -> SCRuleResult {
        SCRuleResult(passed: true, message: "", severity: severity)
    }
}
