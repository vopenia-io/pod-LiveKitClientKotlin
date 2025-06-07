import Foundation
import LiveKitClient

@objc
public class VideoTrackAddKotlin: NSObject {
    public override init () {
        // 
    }

    @objc
    public func setTrack(videoView videoViewParam: NSObject,
                         videoTrack trackParam: NSObject) { // RemoteVideoTrack
        guard let videoView = videoViewParam as? VideoView else {
            return
        }

        if let track = trackParam as? VideoTrack {
            DispatchQueue.main.async {
                videoView.track = track
            }
        } else {
            // nothing
        }
    }

    @objc
    public func remove(videoView videoViewParam: NSObject) {
        guard let videoView = videoViewParam as? VideoView else { return }
        videoView.track = nil
    }
}