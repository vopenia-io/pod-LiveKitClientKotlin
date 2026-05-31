import AVFAudio
import AVFoundation
import Foundation
import LiveKitClient

/// Thin Swift bridge exposing LiveKit `LocalParticipant` async/throwing methods
/// (and Swift-only initialisers) as Objective-C completion-handler signatures
/// so they're consumable from Kotlin/Native via cinterop.
///
/// Two reasons this layer exists:
/// 1. `LocalParticipant.set(attributes:)` is async/throws Swift-only — not visible to ObjC.
/// 2. `DataPublishOptions.init` is `SWIFT_UNAVAILABLE` from ObjC so Kotlin/Native cannot
///    construct it directly. We build it on the Swift side.
@objc
public class LocalParticipantKotlin: NSObject {

    /// Replace this participant's attributes with the supplied dictionary.
    /// Mirrors LiveKit's `LocalParticipant.set(attributes:)` async method.
    @objc
    public static func setAttributes(
        participant: LocalParticipant,
        attributes: [String: String],
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                try await participant.set(attributes: attributes)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    /// LiveKit Components convention topic for chat over text streams.
    /// Matches `useChat()` from `@livekit/components-react` v2+ which Meet Web uses.
    public static let chatTextTopic: String = "lk.chat"

    /// Send a chat message over the LiveKit text stream API. Cross-platform
    /// interop with Meet Web (`useChat()`) requires this transport — the legacy
    /// `publishData` channel that older docs reference is not consumed by
    /// modern Components React chat hooks.
    @objc
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    public static func sendChatText(
        participant: LocalParticipant,
        text: String,
        completionHandler: @escaping (String?, Int64, Error?) -> Void
    ) {
        Task {
            do {
                let info = try await participant.sendText(text, for: chatTextTopic)
                let tsMs = Int64(info.timestamp.timeIntervalSince1970 * 1000.0)
                completionHandler(info.id, tsMs, nil)
            } catch {
                completionHandler(nil, 0, error)
            }
        }
    }

    /// Register a text-stream handler on the room for the chat topic. The
    /// handler is invoked for every incoming chat message routed through
    /// `lk.chat`. Called once after Room connection is established (called
    /// from RoomDelegate.kt where we have a direct Room handle).
    @objc
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    public static func registerChatHandler(
        room: Room,
        onText: @escaping (String, String?) -> Void
    ) {
        Task {
            do {
                try await room.registerTextStreamHandler(for: chatTextTopic) { reader, identity in
                    do {
                        let text = try await reader.readAll()
                        onText(text, identity.stringValue)
                    } catch {
                        print("[CHAT-iOS] text reader failed: \(error)")
                    }
                }
                print("[CHAT-iOS] registered text stream handler for topic '\(chatTextTopic)'")
            } catch {
                print("[CHAT-iOS] registerTextStreamHandler failed: \(error)")
            }
        }
    }

    /// Publish a raw data packet on the LiveKit data channel. The Swift side
    /// constructs the `DataPublishOptions` since its initialiser is not
    /// available from Objective-C / Kotlin/Native.
    @objc
    public static func publishData(
        participant: LocalParticipant,
        data: Data,
        reliable: Bool,
        topic: String?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let options = DataPublishOptions(
            name: nil,
            destinationIdentities: [],
            topic: topic,
            reliable: reliable
        )
        Task {
            do {
                try await participant.publish(data: data, options: options)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    /// Enable / disable the camera, optionally pinning a specific position.
    /// We build `CameraCaptureOptions` on the Swift side because its full
    /// initialiser requires `Dimensions` which is awkward to instantiate
    /// from Kotlin/Native.
    @objc
    public static func setCameraEnabled(
        participant: LocalParticipant,
        enabled: Bool,
        position: AVCaptureDevice.Position,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let options: CameraCaptureOptions? = enabled
            ? CameraCaptureOptions(position: position)
            : nil
        Task {
            do {
                _ = try await participant.setCamera(
                    enabled: enabled,
                    captureOptions: options,
                    publishOptions: nil
                )
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    /// Route the AVAudioSession input to the device whose `uid` is supplied
    /// (matches `AVAudioSessionPortDescription.uid`). Returns nil on success
    /// or the underlying error on failure. iOS owns audio input routing for
    /// LiveKit's capturer — picking the LiveKit `AudioCaptureOptions` is
    /// insufficient.
    @objc
    public static func setPreferredAudioInput(
        uid: String,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let session = AVAudioSession.sharedInstance()
        let target = session.availableInputs?.first { $0.uid == uid }
        guard let port = target else {
            completionHandler(NSError(
                domain: "io.vopenia.audio",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No audio input with uid \(uid)"]
            ))
            return
        }
        do {
            try session.setPreferredInput(port)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    /// Cap the receiving quality of every remote **camera** track currently
     /// subscribed in the room. Screen-share tracks are intentionally not
     /// capped. Maps a Kotlin `VideoSubscribeQuality.ordinal` (0 = Low, 1 =
     /// Standard, 2 = High) to LiveKit's `VideoQuality` enum.
    @objc
    public static func setMaxCameraReceivingQuality(
        room: Room,
        qualityRaw: Int,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let quality: VideoQuality
        switch qualityRaw {
        case 0: quality = .low
        case 1: quality = .medium
        default: quality = .high
        }
        Task {
            do {
                for participant in room.remoteParticipants.values {
                    let cameraPubs = participant.trackPublications.values
                        .compactMap { $0 as? RemoteTrackPublication }
                        .filter { $0.source == .camera }
                    for pub in cameraPubs {
                        try await pub.set(videoQuality: quality)
                    }
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    /// Restart the active camera track at the requested resolution. The Swift
    /// side constructs `CameraCaptureOptions(dimensions: ...)` because the
    /// `Dimensions` initialiser is awkward to call from Kotlin/Native.
    /// `width`/`height` should be the target pixel dimensions of the longer
    /// axis pair (e.g. 640x360, 1280x720). Caller is expected to map their
    /// preset enum to these dimensions.
    @objc
    public static func setCameraResolution(
        participant: LocalParticipant,
        width: Int32,
        height: Int32,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Inherit the currently active camera position so the user doesn't
        // see the camera flip to the system default while changing resolution.
        let publication = participant.localVideoTracks.first { $0.source == .camera }
        let currentCapturer = (publication?.track as? LocalVideoTrack)?.capturer as? CameraCapturer
        let position: AVCaptureDevice.Position = currentCapturer?.options.position ?? .front

        let options = CameraCaptureOptions(
            position: position,
            dimensions: Dimensions(width: width, height: height)
        )
        Task {
            do {
                _ = try await participant.setCamera(
                    enabled: true,
                    captureOptions: options,
                    publishOptions: nil
                )
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    /// Flip the camera between `.front` and `.back`. The current position is
    /// reported back via the completion so Kotlin can update its mirror.
    @objc
    public static func switchCamera(
        participant: LocalParticipant,
        completionHandler: @escaping (AVCaptureDevice.Position, Error?) -> Void
    ) {
        // Determine current position from the active camera capturer if any.
        let publication = participant.localVideoTracks.first { $0.source == .camera }
        let currentTrack = publication?.track as? LocalVideoTrack
        let currentCapturer = currentTrack?.capturer as? CameraCapturer
        let newPosition: AVCaptureDevice.Position = (currentCapturer?.options.position == .front) ? .back : .front

        let options = CameraCaptureOptions(position: newPosition)
        Task {
            do {
                _ = try await participant.setCamera(
                    enabled: true,
                    captureOptions: options,
                    publishOptions: nil
                )
                completionHandler(newPosition, nil)
            } catch {
                completionHandler(newPosition, error)
            }
        }
    }

    /// Enable or disable LiveKit's native `BackgroundBlurVideoProcessor` on the
    /// camera track. Works by tearing down the active camera publication and
    /// republishing a fresh track that wires the processor at creation — the
    /// only public hook LiveKit Swift exposes for this. iOS 15+ only.
    ///
    /// Returns through the completion handler; an error here means the new
    /// track failed to publish — caller should treat the effect as not applied.
    @objc
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    public static func setBackgroundBlur(
        participant: LocalParticipant,
        enabled: Bool,
        completionHandler: @escaping (Error?) -> Void
    ) {
        replaceCameraProcessor(
            participant: participant,
            processor: enabled ? LoggingBlurProcessor() : nil,
            completionHandler: completionHandler
        )
    }

    /// Apply a custom virtual background image. Pass `nil` to remove the effect.
    @objc
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    public static func setBackgroundImage(
        participant: LocalParticipant,
        image: UIImage?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let processor: BackgroundImageVideoProcessor? = image.map { BackgroundImageVideoProcessor(image: $0) }
        replaceCameraProcessor(
            participant: participant,
            processor: processor,
            completionHandler: completionHandler
        )
    }

    // Strong reference key for the currently-installed VideoProcessor.
    //
    // ROOT CAUSE this exists: `LiveKitClient.VideoCapturer.processor` is declared
    // `weak` (Pods/LiveKitClient/.../VideoCapturer.swift:92). If we assign a
    // processor we created locally (e.g. `LoggingBlurProcessor()`) and nothing
    // else retains it, ARC deallocates the instance the moment this function
    // returns. The capturer then sees `nil` on its next `_state.processor` read
    // and skips the effect — the symptom is "setBackgroundBlur completes
    // without error but the video stream looks unchanged".
    //
    // Fix: pin the processor as an associated object on the LocalParticipant
    // it's attached to. That gives it the same lifetime as the participant,
    // and lets a subsequent `setBackgroundBlur(enabled: false)` clear the
    // retention (by associating `nil`).
    private static var processorAssocKey: UInt8 = 0

    private static func retainProcessor(_ processor: VideoProcessor?, on participant: LocalParticipant) {
        objc_setAssociatedObject(participant, &processorAssocKey, processor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    private static func replaceCameraProcessor(
        participant: LocalParticipant,
        processor: VideoProcessor?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let allLocal = participant.localVideoTracks
        print("[BLUR] replaceCameraProcessor — localVideoTracks.count=\(allLocal.count)")
        for pub in allLocal {
            let t = pub.track
            print("[BLUR]   publication source=\(pub.source) track=\(t.map { String(describing: type(of: $0)) } ?? "nil") publication=\(type(of: pub))")
        }

        // Retain strong BEFORE assigning to the weak `processor` property —
        // otherwise the new processor is deallocated before the capturer
        // reads it back. See the note on `processorAssocKey` above.
        retainProcessor(processor, on: participant)

        // Prefer the in-place setter exposed by LiveKitClient
        // (`LocalVideoTrack.processor`) so the camera doesn't get torn down
        // and re-published on every toggle. Falls back to publish-with-processor
        // when no camera track is currently active.
        if let publication = participant.localVideoTracks.first(where: { $0.source == .camera }),
           let track = publication.track as? LocalVideoTrack {
            print("[BLUR] in-place setter on existing camera track, processor=\(processor.map { String(describing: type(of: $0)) } ?? "nil")")
            track.processor = processor
            let after = track.processor
            print("[BLUR] after set: track.processor=\(after.map { String(describing: type(of: $0)) } ?? "nil")")
            completionHandler(nil)
            return
        }
        print("[BLUR] no existing camera publication — falling back to publish-with-processor")
        Task {
            do {
                let track: LocalVideoTrack
                if let processor = processor {
                    track = LocalVideoTrack.createCameraTrack(
                        name: nil,
                        options: nil,
                        reportStatistics: false,
                        processor: processor
                    )
                } else {
                    track = LocalVideoTrack.createCameraTrack()
                }
                _ = try await participant.publish(videoTrack: track)
                print("[BLUR] fallback publish succeeded")
                completionHandler(nil)
            } catch {
                print("[BLUR] fallback publish failed: \(error)")
                completionHandler(error)
            }
        }
    }
}
