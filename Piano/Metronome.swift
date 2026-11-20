import Foundation
import AVFoundation
import os

/// A metronome that generates its clicks inside the audio render callback, so beats are
/// sample-accurate and don't drift the way a `Timer` would while the UI is busy.
nonisolated final class Metronome: @unchecked Sendable {
    /// Tempo range of a classic mechanical metronome, in beats per minute, and the +/- step.
    static let tempoRange = 40...208
    static let tempoStep = 4
    /// Supported beats per bar (2/4, 3/4, 4/4).
    static let beatsPerBarOptions = [2, 3, 4]

    private var lock = os_unfair_lock()
    private var isRunning = false
    private var bpm = 100.0
    private var beatsPerBar = 4
    /// Index of the next beat within the bar; 0 is the accented downbeat.
    private var nextBeat = 0
    private var samplesUntilNextBeat = 0.0
    /// State of the click currently sounding.
    private var clickPhase = 0.0
    private var clickFrequency = 0.0
    private var clickEnvelope = 0.0
    private var clickSamplesLeft = 0

    func start(bpm: Int, beatsPerBar: Int) {
        os_unfair_lock_lock(&lock)
        self.bpm = Double(bpm)
        self.beatsPerBar = beatsPerBar
        nextBeat = 0
        samplesUntilNextBeat = 0
        isRunning = true
        os_unfair_lock_unlock(&lock)
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        isRunning = false
        os_unfair_lock_unlock(&lock)
    }

    /// Changes take effect from the next beat without restarting the bar.
    func update(bpm: Int, beatsPerBar: Int) {
        os_unfair_lock_lock(&lock)
        self.bpm = Double(bpm)
        self.beatsPerBar = beatsPerBar
        nextBeat %= beatsPerBar
        os_unfair_lock_unlock(&lock)
    }

    /// Creates the source node. Built in a nonisolated context so the render
    /// block does not inherit main-actor isolation.
    func makeSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        let twoPi = 2 * Double.pi
        let clickLength = Int(sampleRate * 0.03)
        // Per-sample multiplier that fades the click out over its length.
        let clickDecay = pow(0.001, 1 / Double(clickLength))

        return AVAudioSourceNode { [self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            os_unfair_lock_lock(&lock)
            for frame in 0..<Int(frameCount) {
                if isRunning {
                    if samplesUntilNextBeat <= 0 {
                        // Higher pitch on the downbeat marks the start of each bar.
                        clickFrequency = nextBeat == 0 ? 1600 : 1000
                        clickPhase = 0
                        clickEnvelope = 1
                        clickSamplesLeft = clickLength
                        nextBeat = (nextBeat + 1) % beatsPerBar
                        samplesUntilNextBeat += sampleRate * 60 / bpm
                    }
                    samplesUntilNextBeat -= 1
                }
                var value: Float = 0
                if clickSamplesLeft > 0 {
                    value = Float(sin(clickPhase) * clickEnvelope * 0.5)
                    clickEnvelope *= clickDecay
                    clickPhase += twoPi * clickFrequency / sampleRate
                    clickSamplesLeft -= 1
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            os_unfair_lock_unlock(&lock)
            return noErr
        }
    }
}
