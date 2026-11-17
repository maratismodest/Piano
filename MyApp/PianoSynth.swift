import Foundation
import AVFoundation
import os

/// Polyphonic voice state shared between the UI and the real-time audio thread.
/// Uses fixed-size arrays (one slot per MIDI note) so the render callback never allocates.
nonisolated final class VoiceBank: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var phase = [Double](repeating: 0, count: 128)
    private var level = [Double](repeating: 0, count: 128)
    private var gate = [Bool](repeating: false, count: 128)
    private var active = [Bool](repeating: false, count: 128)

    func noteOn(_ note: Int) {
        guard (0..<128).contains(note) else { return }
        os_unfair_lock_lock(&lock)
        phase[note] = 0
        level[note] = 1
        gate[note] = true
        active[note] = true
        os_unfair_lock_unlock(&lock)
    }

    func noteOff(_ note: Int) {
        guard (0..<128).contains(note) else { return }
        os_unfair_lock_lock(&lock)
        gate[note] = false
        os_unfair_lock_unlock(&lock)
    }

    /// Creates the source node. Built in a nonisolated context so the render
    /// block does not inherit main-actor isolation.
    func makeSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        let twoPi = 2 * Double.pi
        // Per-sample multipliers: slow decay while held (like a struck string), faster on release.
        let sustainDecay = pow(0.001, 1 / (sampleRate * 3.0))
        let releaseDecay = pow(0.001, 1 / (sampleRate * 0.25))

        return AVAudioSourceNode { [self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            os_unfair_lock_lock(&lock)
            for frame in 0..<Int(frameCount) {
                var sample = 0.0
                for note in 0..<128 where active[note] {
                    let p = phase[note]
                    // Fundamental plus a few harmonics for a warmer, piano-like timbre.
                    let tone = sin(p) + 0.5 * sin(2 * p) + 0.25 * sin(3 * p) + 0.1 * sin(4 * p)
                    sample += tone * level[note]

                    let freq = 440.0 * pow(2.0, Double(note - 69) / 12.0)
                    phase[note] = (p + twoPi * freq / sampleRate).truncatingRemainder(dividingBy: twoPi)
                    level[note] *= gate[note] ? sustainDecay : releaseDecay
                    if level[note] < 0.0001 { active[note] = false }
                }
                let value = Float(tanh(sample * 0.15))
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            os_unfair_lock_unlock(&lock)
            return noErr
        }
    }
}

/// Owns the audio engine and exposes simple note on/off controls.
final class PianoSynth {
    private let engine = AVAudioEngine()
    private let voices = VoiceBank()

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let output = engine.outputNode
        let hwFormat = output.inputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let source = voices.makeSourceNode(sampleRate: sampleRate)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.8

        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func noteOn(_ note: Int) { voices.noteOn(note) }
    func noteOff(_ note: Int) { voices.noteOff(note) }
}
