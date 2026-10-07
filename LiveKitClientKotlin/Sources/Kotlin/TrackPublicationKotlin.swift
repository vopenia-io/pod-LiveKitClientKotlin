// Copyright 2026
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LiveKitClient

/// Kotlin/Native-facing accessors for `TrackPublication.dimensions`.
///
/// `Dimensions` is a Swift struct, so it never crosses the ObjC boundary the
/// Kotlin SDK sees. These helpers hand the published width / height (what the
/// publisher declared in its TrackInfo - a screen share's capture size) over
/// as plain integers, 0 when unknown or for audio publications.
@objc
public final class TrackPublicationKotlin: NSObject {

    @objc
    public static func width(of publication: TrackPublication) -> Int {
        Int(publication.dimensions?.width ?? 0)
    }

    @objc
    public static func height(of publication: TrackPublication) -> Int {
        Int(publication.dimensions?.height ?? 0)
    }
}
