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
                DimensionsRelayout.follow(videoView, track: track as? Track)
            }
        } else {
            // nothing
        }
    }

    @objc
    public func remove(videoView videoViewParam: NSObject) {
        guard let videoView = videoViewParam as? VideoView else { return }
        videoView.track = nil
        DispatchQueue.main.async {
            DimensionsRelayout.follow(videoView, track: nil)
        }
    }
}

/// Lays a VideoView out again whenever its track's dimensions change.
///
/// LiveKit 2.6.0's VideoView sizes its renderer from the track dimensions, but only lays out
/// on its own state changes (view size, first frame, track). Rotating the phone lays the
/// self-view out for the new window size first; the camera frames flip orientation a moment
/// later, nothing lays out again, and the renderer keeps the previous orientation's aspect:
/// the picture stays stretched. Upstream lays out on every dimension change since
/// client-sdk-swift#950; this does the same from outside the view.
private final class DimensionsRelayout: NSObject, TrackDelegate {
    private static var key: UInt8 = 0

    private weak var videoView: VideoView?
    private weak var track: Track?

    private init(videoView: VideoView) {
        self.videoView = videoView
    }

    /// Main thread only. Retained by the view itself, so it lives exactly as long as the view.
    static func follow(_ videoView: VideoView, track: Track?) {
        let relayout: DimensionsRelayout
        if let existing = objc_getAssociatedObject(videoView, &key) as? DimensionsRelayout {
            relayout = existing
        } else {
            relayout = DimensionsRelayout(videoView: videoView)
            objc_setAssociatedObject(videoView, &key, relayout, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard relayout.track !== track else { return }
        relayout.track?.remove(delegate: relayout)
        relayout.track = track
        track?.add(delegate: relayout)
    }

    func track(_: VideoTrack, didUpdateDimensions _: Dimensions?) {
        DispatchQueue.main.async { [weak self] in
            self?.videoView?.setNeedsLayout()
        }
    }
}
