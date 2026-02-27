import Foundation

/// Evaluates frame luminance using Vision.framework. Fails on under- or over-exposed frames.
public struct SCBrightnessRule: SCFrameRule {
    public init() {}
}
