import Foundation
import LiveKitClient

/// Diagnostic wrapper around `BackgroundBlurVideoProcessor` that prints to
/// the console every 30 processed frames. Used while validating that the
/// `LocalVideoTrack.processor` hook actually delivers frames to a processor
/// installed at runtime on an already-active camera track.
///
/// Temporary — once the in-place setter is confirmed to work, this can be
/// dropped in favour of using `BackgroundBlurVideoProcessor` directly.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
@objc
public final class LoggingBlurProcessor: NSObject, @unchecked Sendable, LiveKitClient.VideoProcessor {

    private let inner = BackgroundBlurVideoProcessor()
    private var frameCount: Int = 0

    public override init() {
        super.init()
        print("[BLUR] LoggingBlurProcessor created")
    }

    public func process(frame: VideoFrame) -> VideoFrame? {
        frameCount += 1
        if frameCount == 1 || frameCount % 30 == 0 {
            print("[BLUR] processed \(frameCount) frames; dims=\(frame.dimensions.width)x\(frame.dimensions.height)")
        }
        return inner.process(frame: frame)
    }
}
