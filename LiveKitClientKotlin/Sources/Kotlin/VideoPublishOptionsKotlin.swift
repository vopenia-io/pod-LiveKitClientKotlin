// Copyright 2026
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LiveKitClient

/// Kotlin/Native-facing builder for the room's default `VideoPublishOptions`.
///
/// `VideoPublishOptions.init` is not exposed to Objective-C, so the Kotlin SDK can only
/// reuse the default instance. These helpers return a copy with the changes Kotlin cannot
/// make itself.
@objc
public final class VideoPublishOptionsKotlin: NSObject {

    /// `options` with a screen share low layer that keeps the full frame rate.
    ///
    /// LiveKit 2.6.0 simulcasts a screen share as the full frame plus a half-resolution
    /// layer capped at 3 fps. A receiver that gets that layer (a small view, or a downlink
    /// the SFU finds too tight for the full one) watches a slideshow. Upstream fixed it in
    /// 2.13.0 (client-sdk-swift#935) by giving the half layer the full layer's frame rate;
    /// this sets the same layer explicitly. Camera publishing is unchanged.
    @objc
    public static func smoothScreenShare(_ options: VideoPublishOptions) -> VideoPublishOptions {
        VideoPublishOptions(
            name: options.name,
            encoding: options.encoding,
            screenShareEncoding: options.screenShareEncoding,
            simulcast: options.simulcast,
            simulcastLayers: options.simulcastLayers,
            screenShareSimulcastLayers: [halfScreenShareLayer],
            preferredCodec: options.preferredCodec,
            preferredBackupCodec: options.preferredBackupCodec,
            degradationPreference: options.degradationPreference,
            streamName: options.streamName
        )
    }

    /// The broadcast capturer fits the screen into 1920 px, for which LiveKit picks the
    /// H1080FPS15 preset (2.5 Mbps, 15 fps). LiveKit scales a layer by the ratio of the
    /// longest sides, so a 960 px layer is exactly half; its bitrate is a quarter of the
    /// preset's, as upstream computes it.
    private static let halfScreenShareLayer = VideoParameters(
        dimensions: Dimensions(width: 960, height: 540),
        encoding: VideoEncoding(maxBitrate: 625_000, maxFps: 15)
    )
}
