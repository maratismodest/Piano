import SwiftUI

/// Compile-time feature flags.
enum FeatureFlags {
    /// Shows note names on the white keys.
    static let showKeyLabels = false
    /// Shows the name of the first visible note next to the shift stepper.
    static let showStartNoteName = false
    /// Shows the visible white key count next to the zoom stepper.
    static let showZoomLabel = false
    /// Plays real piano samples (bundled SoundFont) instead of the built-in synthesizer.
    static let useSampledPiano = true
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
    /// The note under each finger currently on the keyboard.
    @State private var touchNotes: [SpatialEventCollection.Event.ID: Int] = [:]
    /// Default keyboard position (35 = C4) and zoom, restored by the reset button.
    private static let defaultStartWhite = 35
    private static let defaultVisibleWhiteKeys = 14

    /// Absolute index of the leftmost white key. Persisted between launches.
    @AppStorage("startWhite") private var startWhite = defaultStartWhite
    /// How many white keys fit on screen; fewer keys means wider keys (zoom in). Persisted between launches.
    @AppStorage("visibleWhiteKeys") private var visibleWhiteKeys = defaultVisibleWhiteKeys

    /// Maximum keyboard height as a fraction of its width in portrait orientation.
    private let maxPortraitKeyboardRatio: CGFloat = 0.6

    /// Black key size relative to a white key.
    private let blackWidthRatio: CGFloat = 0.6
    private let blackHeightRatio: CGFloat = 0.6

    /// Notes currently sounding; several fingers may hold the same note.
    private var pressed: Set<Int> { Set(touchNotes.values) }

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
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                // Inverted so "+" zooms in (fewer, wider keys), matching the magnifier icon.
                let zoomStepper = Stepper("Keys: \(visibleWhiteKeys)") {
                    visibleWhiteKeys = max(visibleWhiteKeys - 1, visibleWhiteKeysRange.lowerBound)
                } onDecrement: {
                    visibleWhiteKeys = min(visibleWhiteKeys + 1, visibleWhiteKeysRange.upperBound)
                }
                .fixedSize()
                if FeatureFlags.showZoomLabel {
                    zoomStepper
                } else {
                    zoomStepper.labelsHidden()
                }
                Image(systemName: "arrow.left.and.right")
                    .padding(.leading, 8)
                    .accessibilityHidden(true)
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
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    visibleWhiteKeys = Self.defaultVisibleWhiteKeys
                    startWhite = Self.defaultStartWhite
                }
                .labelStyle(.iconOnly)
                .padding(.leading, 8)
                .disabled(visibleWhiteKeys == Self.defaultVisibleWhiteKeys && startWhite == Self.defaultStartWhite)
            }
            .padding(.horizontal)

            GeometryReader { geo in
                // In portrait (e.g. iPad held upright) a full-height keyboard makes the keys
                // absurdly long, so cap its height and keep it at the bottom, near the hands.
                let isPortrait = geo.size.height > geo.size.width
                let height = isPortrait ? min(geo.size.height, geo.size.width * maxPortraitKeyboardRatio) : geo.size.height
                keyboard
                    .frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
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

    /// Release any held notes when the visible keys change or all fingers lift.
    private func releaseAll() {
        pressed.forEach { synth.noteOff($0) }
        touchNotes.removeAll()
    }

    /// Moves a finger to `note` (or off the keyboard when `nil`), so sliding across keys
    /// plays each one in turn. A note only stops once no finger is holding it.
    private func updateTouch(_ id: SpatialEventCollection.Event.ID, to note: Int?) {
        let oldNote = touchNotes[id]
        guard oldNote != note else { return }
        let wasHeld = note.map { pressed.contains($0) } ?? false
        touchNotes[id] = note
        if let oldNote, !pressed.contains(oldNote) { synth.noteOff(oldNote) }
        if let note, !wasHeld { synth.noteOn(note) }
    }

    /// The key at `point` in the keyboard's local coordinates; black keys sit on top of white ones.
    private func note(at point: CGPoint, in size: CGSize) -> Int? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y < size.height else { return nil }
        let whiteWidth = size.width / CGFloat(visibleWhiteKeys)
        let blackWidth = whiteWidth * blackWidthRatio
        if point.y < size.height * blackHeightRatio,
           let black = keys.first(where: { $0.isBlack && abs(point.x - CGFloat($0.whiteIndex) * whiteWidth) < blackWidth / 2 }) {
            return black.note
        }
        // +1 skips the off-screen buffer key on the left.
        let whiteIndex = Int(point.x / whiteWidth) + 1
        return keys.first { !$0.isBlack && $0.whiteIndex == whiteIndex }?.note
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(visibleWhiteKeys)
            let blackWidth = whiteWidth * blackWidthRatio
            let blackHeight = geo.size.height * blackHeightRatio
            let whiteKeys = keys.filter { !$0.isBlack }
            let blackKeys = keys.filter { $0.isBlack }
            // Shift by one so the off-screen buffer key sits just past the left edge.
            let whiteX = { (key: PianoKey) in CGFloat(key.whiteIndex - 1) * whiteWidth }
            let blackX = { (key: PianoKey) in CGFloat(key.whiteIndex) * whiteWidth - blackWidth / 2 }

            ZStack(alignment: .topLeading) {
                // Keys are positioned by offset and identified by note, so changing `startWhite`
                // slides the same keys left or right instead of redrawing them in place.
                // Off-screen buffer keys are hidden from VoiceOver.
                ForEach(whiteKeys) { key in
                    let x = whiteX(key)
                    keyView(key, width: whiteWidth, height: geo.size.height)
                        .offset(x: x)
                        .accessibilityHidden(x < 0 || x >= geo.size.width)
                }
                ForEach(blackKeys) { key in
                    let x = blackX(key)
                    keyView(key, width: blackWidth, height: blackHeight)
                        .offset(x: x)
                        .accessibilityHidden(x + blackWidth <= 0 || x >= geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            // One gesture for the whole keyboard tracks every finger separately, which allows
            // both chords and glissando (sliding a finger across keys).
            .gesture(
                SpatialEventGesture()
                    .onChanged { events in
                        for event in events {
                            let isActive = event.phase == .active
                            updateTouch(event.id, to: isActive ? note(at: event.location, in: geo.size) : nil)
                        }
                    }
                    .onEnded { _ in releaseAll() }
            )
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
            .accessibilityLabel(key.name)
            .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ContentView()
}
