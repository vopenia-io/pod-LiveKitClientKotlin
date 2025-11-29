import Foundation
import LiveKitClient

@objc
public class AudioSessionWrapper: NSObject {
    public override init () {
        // 
    }

    @objc
    public func audioSessionDidActivate(audioSession: AVAudioSession) {
        LKRTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    }

    @objc
    public func audioSessionDidDeactivate(audioSession: AVAudioSession) {
        LKRTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }
}