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

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, *)
    private static func replaceCameraProcessor(
        participant: LocalParticipant,
        processor: VideoProcessor?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Prefer the in-place setter exposed by LiveKitClient
        // (`LocalVideoTrack.processor`) so the camera doesn't get torn down
        // and re-published on every toggle. Falls back to publish-with-processor
        // when no camera track is currently active.
        if let publication = participant.localVideoTracks.first(where: { $0.source == .camera }),
           let track = publication.track as? LocalVideoTrack {
            track.processor = processor
            completionHandler(nil)
            return
        }
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
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}
