// Copyright 2026
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import LiveKitClient

/// Kotlin/Native-facing bridge for the BigBlueBetterAudio noise filter.
///
/// `AudioManager.shared.capturePostProcessingDelegate` is Swift-only API; this
/// `@objc` helper exposes simple static toggles so `InternalLocalParticipant`
/// (Kotlin/Native, iosMain) can drive it. The delegate is installed lazily on
/// first enable and left installed (pass-through when disabled).
@objc
public final class BbbaNoiseFilterKotlin: NSObject {

    private static let filter = BbbaNoiseFilter()
    private static var installed = false

    /// Install the capture-post delegate on AudioManager.shared. Must be
    /// called BEFORE LiveKit's audio capture pipeline initializes — i.e.
    /// before `Room.connect()` publishes the first audio track. Otherwise
    /// LiveKit fires `audioProcessingInitialize` on its internal adapter
    /// while its target is still nil (the lazy `AudioManager.capturePost…`
    /// getter), our `BbbaNoiseFilter.audioProcessingInitialize` is never
    /// called, no `BBBAEngine` is constructed, and `engine` stays nil
    /// forever (symptom: `[BBBA-iOS] BBBA ON (engine=nil)` in logs, no
    /// processAudio heartbeat). Idempotent.
    @objc
    public static func install() {
        if installed { return }
        AudioManager.shared.capturePostProcessingDelegate = filter
        installed = true
        NSLog("[BBBA-iOS] capture-post delegate installed on AudioManager.shared (pre-connect)")
    }

    /// Enable/disable noise suppression live. Falls back to installing the
    /// delegate if `install()` wasn't called pre-connect — note that lazy
    /// install misses the `audioProcessingInitialize` callback fired earlier
    /// by LiveKit, so suppression will be a pass-through until the audio
    /// pipeline resets (e.g. next call). Prefer calling `install()` from
    /// `Room.connect`.
    @objc
    public static func setEnabled(_ enabled: Bool) {
        NSLog("[BBBA-iOS] setEnabled(%@) — installed=%@",
              enabled ? "true" : "false",
              installed ? "true" : "false")
        if !installed {
            install()
            NSLog("[BBBA-iOS] WARNING: setEnabled called before install() — first session may bypass")
        }
        // Method (not the bare property): an OFF -> ON transition rebuilds
        // the engine so processing never resumes on the stale DSP state
        // frozen during the disabled window (outgoing level squash).
        filter.setEnabled(enabled)
    }

    /// RNNoise dry/wet intensity, 0..100 (% wet).
    @objc
    public static func setIntensity(_ value: Float) {
        NSLog("[BBBA-iOS] setIntensity(%.1f)", value)
        filter.setIntensity(value)
    }
}
