import SwiftUI

/// Compile-time feature flags.
enum FeatureFlags {
    /// Shows note names on the white keys.
    static let showKeyLabels = false
    /// Shows the name of the first visible note next to the shift stepper.
    static let showStartNoteName = false
    /// Shows the visible white key count next to the zoom stepper.
    static let showZoomLabel = false
}

/// A single piano key description.
struct PianoKey: Identifiable {
    let note: Int          // MIDI note number
    let isBlack: Bool
    let whiteIndex: Int    // index of the white key this key sits on (or to the left of, for black keys)
    var id: Int { note }

    var name: String {
        let names: [String] = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[note % 12]
    }

    /// Note name with octave number in scientific pitch notation, e.g. "C4".
    var fullName: String { "\(name)\(note / 12 - 1)" }

    /// Semitone offsets of the white keys within an octave.
    private static let whiteSemitones = [0, 2, 4, 5, 7, 9, 11]

    /// MIDI note of the white key with the given absolute index (0 = C-1).
    static func whiteNote(at index: Int) -> Int {
        (index / 7) * 12 + whiteSemitones[index % 7]
    }

    /// Builds `whiteCount` white keys (plus the black keys between and right after them)
    /// starting at `startNote`, which must be a white key.
    static func keys(startNote: Int, whiteCount: Int) -> [PianoKey] {
        var result: [PianoKey] = []
        var whites = 0
        var note = startNote
        while note <= 127 {
            if whiteSemitones.contains(note % 12) {
                guard whites < whiteCount else { break }
                result.append(PianoKey(note: note, isBlack: false, whiteIndex: whites))
                whites += 1
            } else {
                result.append(PianoKey(note: note, isBlack: true, whiteIndex: whites - 1))
            }
            note += 1
        }
        return result
    }
}

struct ContentView: View {
    @State private var synth = PianoSynth()
    @State private var pressed: Set<Int> = []
    /// Absolute index of the leftmost white key (35 = C4).
    @State private var startWhite = 35
    /// How many white keys fit on screen; fewer keys means wider keys (zoom in).
    @State private var visibleWhiteKeys = 14

    /// Zoom limits: from one octave to two octaves of white keys.
    private let visibleWhiteKeysRange = 7...14

    /// Allowed range for `startWhite`: from C1 up to keeping C8 as the last visible key.
    private var startWhiteRange: ClosedRange<Int> { 14...(63 - visibleWhiteKeys + 1) }

    /// Visible keys plus one off-screen white key on each side, so keys can slide in and out
    /// when the keyboard shifts. `whiteIndex` 0 is the off-screen key on the left.
    private var keys: [PianoKey] {
        PianoKey.keys(startNote: PianoKey.whiteNote(at: startWhite - 1), whiteCount: visibleWhiteKeys + 2)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("🎹 Piano")
                    .font(.largeTitle.bold())
                Spacer()
                let zoomStepper = Stepper("Keys: \(visibleWhiteKeys)", value: $visibleWhiteKeys, in: visibleWhiteKeysRange)
                    .fixedSize()
                if FeatureFlags.showZoomLabel {
                    zoomStepper
                } else {
                    zoomStepper.labelsHidden()
                }
                let shiftStepper = Stepper(
                    "Start: \(PianoKey(note: PianoKey.whiteNote(at: startWhite), isBlack: false, whiteIndex: 0).fullName)",
                    value: $startWhite,
                    in: startWhiteRange
                )
                .fixedSize()
                // The label stays available to VoiceOver even when hidden.
                if FeatureFlags.showStartNoteName {
                    shiftStepper
                } else {
                    shiftStepper.labelsHidden()
                }
            }
            .padding(.horizontal)

            keyboard
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .padding(.top)
        .background(Color(white: 0.12))
        .foregroundStyle(.white)
        .onChange(of: startWhite) { releaseAll() }
        .onChange(of: visibleWhiteKeys) {
            releaseAll()
            // Keep the keyboard within range after zooming out.
            startWhite = min(startWhite, startWhiteRange.upperBound)
        }
    }

    /// Release any held notes when the visible keys change.
    private func releaseAll() {
        pressed.forEach { synth.noteOff($0) }
        pressed.removeAll()
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(visibleWhiteKeys)
            let blackWidth = whiteWidth * 0.6
            let blackHeight = geo.size.height * 0.6
            let whiteKeys = keys.filter { !$0.isBlack }
            let blackKeys = keys.filter { $0.isBlack }
            // Shift by one so the off-screen buffer key sits just past the left edge.
            let whiteX = { (key: PianoKey) in CGFloat(key.whiteIndex - 1) * whiteWidth }
            let blackX = { (key: PianoKey) in CGFloat(key.whiteIndex) * whiteWidth - blackWidth / 2 }

            ZStack(alignment: .topLeading) {
                // Keys are positioned by offset and identified by note, so changing `startWhite`
                // slides the same keys left or right instead of redrawing them in place.
                ForEach(whiteKeys) { key in
                    let x = whiteX(key)
                    keyView(key, width: whiteWidth, height: geo.size.height)
                        .offset(x: x)
                        .allowsHitTesting(x >= 0 && x < geo.size.width)
                }
                ForEach(blackKeys) { key in
                    let x = blackX(key)
                    keyView(key, width: blackWidth, height: blackHeight)
                        .offset(x: x)
                        .allowsHitTesting(x + blackWidth > 0 && x < geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: startWhite)
        }
    }

    private func keyView(_ key: PianoKey, width: CGFloat, height: CGFloat) -> some View {
        let isPressed = pressed.contains(key.note)
        let fill: Color = key.isBlack
            ? (isPressed ? Color(white: 0.35) : .black)
            : (isPressed ? Color(white: 0.8) : .white)

        return RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if FeatureFlags.showKeyLabels && !key.isBlack {
                    Text(key.name)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            // Zero-distance drag gives press/release events and supports multi-touch chords.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed.contains(key.note) {
                            pressed.insert(key.note)
                            synth.noteOn(key.note)
                        }
                    }
                    .onEnded { _ in
                        pressed.remove(key.note)
                        synth.noteOff(key.note)
                    }
            )
            .accessibilityLabel(key.name)
            .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ContentView()
}
