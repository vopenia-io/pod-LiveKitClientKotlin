// Copyright 2026
// SPDX-License-Identifier: GPL-3.0-or-later

import BBBACore
import Foundation
import LiveKitClient

/// LiveKit capture-post audio processor backed by the BigBlueBetterAudio native
/// core (RNNoise voice isolation + VAD gate + Faust aesthetic chain), via the
/// ObjC++ `BBBAEngine` façade.
///
/// Mirrors `LiveKitKrispNoiseFilter`: installed on
/// `AudioManager.shared.capturePostProcessingDelegate`. WebRTC delivers
/// full-band mono float frames in int16 scale (±32768); `BBBAEngine` handles
/// the ±32768 ⇄ [-1,1] conversion. RNNoise requires 48 kHz — other rates are
/// bypassed in V1 (resampling is a follow-up). Pure pass-through while disabled.
@objc
public final class BbbaNoiseFilter: NSObject, AudioCustomProcessingDelegate {

    private let lock = NSLock()
    private var engine: BBBAEngine?
    private var sampleRate: Int = 0
    private var frameCount: Int = 0

    // Parameter defaults — must match the BBBA web reference UI
    // (BigBlueBetterAudio/web/index.html sliders). The bbba-core / Faust DSP
    // ships with weaker defaults (mb_strength=60, sb_strength=60,
    // leveler_target=-18 dB), which produces a noticeably quieter aesthetic
    // chain than what BBBA web users hear. Push the web defaults
    // explicitly when the engine is constructed so mobile sounds identical.
    private var intensity: Float = 100
    private var mbStrength: Float = 100
    private var sbStrength: Float = 100
    private var levelerTarget: Float = -23   // dB

    // Default true to match `LocalParticipant.noiseReductionEnabledState`
    // (Kotlin commonMain) which is initialized to `true`. If the native side
    // stays false here, the toggle shows ON in the UI but BBBA stays OFF
    // until the user manually flips it — confusing discrepancy.
    @objc public var enabled: Bool = true {
        didSet {
            // INFO-level (NSLog) so the user can confirm at a glance that the
            // Swift filter flipped state — independent of audioProcessingProcess
            // actually being called (it isn't, until LiveKit's capturer hands us
            // a buffer).
            NSLog("[BBBA-iOS] BBBA %@ (engine=%@, intensity=%.1f)",
                  enabled ? "ON " : "OFF",
                  engine == nil ? "nil" : "ready",
                  intensity)
        }
    }

    /// Toggle entry point used by the Kotlin bridge. An OFF -> ON transition
    /// rebuilds the engine first: the disabled window freezes the DSP's
    /// adaptive state (VAD gate envelope, RNNoise noise model, and above all
    /// the Faust leveler/multiband integrators), and resuming on that stale
    /// state squashes the outgoing level until the engine is recreated —
    /// users had to kill the app to recover. The rebuild happens while still
    /// disabled, so no capture callback is inside the old engine.
    /// (Swift-only on purpose: an @objc method here would collide with the
    /// `enabled` property's generated `setEnabled:` selector.)
    public func setEnabled(_ on: Bool) {
        if on && !enabled { rebuildEngine() }
        enabled = on
    }

    private func rebuildEngine() {
        lock.lock()
        let sr = sampleRate
        let hadEngine = engine != nil
        lock.unlock()
        guard hadEngine, sr == 48000 else { return }

        // Construct outside the lock (rnnoise + Faust init), swap under it.
        let e = BBBAEngine(sampleRate: Int32(sr))
        e?.setParam("intensity", value: intensity)
        e?.setParam("mb_strength", value: mbStrength)
        e?.setParam("sb_strength", value: sbStrength)
        e?.setParam("leveler_target", value: levelerTarget)

        lock.lock(); engine = e; lock.unlock()
        NSLog("[BBBA-iOS] re-enable: engine rebuilt (engine=%@)", e == nil ? "nil" : "ready")
    }

    public var audioProcessingName: String { "bigbluebetteraudio" }

    public func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {
        lock.lock(); defer { lock.unlock() }
        sampleRate = sampleRateHz
        guard sampleRateHz == 48000 else {
            NSLog("[BBBA-iOS] bypassed: RNNoise requires 48kHz, got %d", sampleRateHz)
            engine = nil
            return
        }
        let e = BBBAEngine(sampleRate: Int32(sampleRateHz))
        // Push the BBBA web reference parameters explicitly. The Faust DSP's
        // bare defaults are weaker (mb=60, sb=60, leveler=-18) — without
        // these overrides the aesthetic chain barely lifts the post-RNNoise
        // signal and users perceive almost no difference vs the raw mic.
        e?.setParam("intensity", value: intensity)
        e?.setParam("mb_strength", value: mbStrength)
        e?.setParam("sb_strength", value: sbStrength)
        e?.setParam("leveler_target", value: levelerTarget)
        engine = e
        NSLog("[BBBA-iOS] initialized @ %dHz × %d ch (engine=%@, intensity=%.1f, mb=%.1f, sb=%.1f, leveler=%.1fdB, enabled=%@)",
              sampleRateHz, channels,
              e == nil ? "nil" : "ready",
              intensity, mbStrength, sbStrength, levelerTarget,
              enabled ? "true" : "false")
    }

    public func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        guard enabled else { return }
        lock.lock(); let e = engine; lock.unlock()
        guard let engine = e, audioBuffer.channels > 0 else { return }
        let ptr = audioBuffer.rawBuffer(forChannel: 0)
        engine.process(inPlace: ptr, frames: Int32(audioBuffer.frames))
        // Lightweight liveness heartbeat — every 500 frames (~5s @ 48k/10ms).
        // Helps distinguish "BBBA ON but no audio reaching it" from "BBBA ON
        // and actively processing". Frequency low enough not to spam.
        frameCount += 1
        if frameCount % 500 == 0 {
            NSLog("[BBBA-iOS] processAudio heartbeat: frames=%d ch=%d frames/buf=%d",
                  frameCount, audioBuffer.channels, audioBuffer.frames)
        }
    }

    public func audioProcessingRelease() {
        lock.lock(); engine = nil; lock.unlock()
        NSLog("[BBBA-iOS] audioProcessingRelease — engine torn down")
    }

    @objc public func setIntensity(_ value: Float) {
        lock.lock(); defer { lock.unlock() }
        intensity = value
        engine?.setParam("intensity", value: value)
        NSLog("[BBBA-iOS] setIntensity(%.1f)", value)
    }
}
