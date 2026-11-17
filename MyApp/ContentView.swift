import SwiftUI

/// A single piano key description.
struct PianoKey: Identifiable {
    let note: Int          // MIDI note number
    let isBlack: Bool
    let whiteIndex: Int    // index of the white key this key sits on (or to the left of, for black keys)
    var id: Int { note }

    var name: String {
        let names = ["До", "До♯", "Ре", "Ре♯", "Ми", "Фа", "Фа♯", "Соль", "Соль♯", "Ля", "Ля♯", "Си"]
        return names[note % 12]
    }

    /// Builds keys for the given number of octaves starting at `startNote` (should be a C).
    static func keys(startNote: Int, octaves: Int) -> [PianoKey] {
        let blackSemitones: Set<Int> = [1, 3, 6, 8, 10]
        var result: [PianoKey] = []
        var whiteCount = 0
        for note in startNote..<(startNote + octaves * 12) {
            let isBlack = blackSemitones.contains(note % 12)
            if isBlack {
                result.append(PianoKey(note: note, isBlack: true, whiteIndex: whiteCount - 1))
            } else {
                result.append(PianoKey(note: note, isBlack: false, whiteIndex: whiteCount))
                whiteCount += 1
            }
        }
        return result
    }
}

struct ContentView: View {
    @State private var synth = PianoSynth()
    @State private var pressed: Set<Int> = []
    @State private var octave = 4

    private var keys: [PianoKey] { PianoKey.keys(startNote: (octave + 1) * 12, octaves: 2) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("🎹 Пианино")
                    .font(.largeTitle.bold())
                Spacer()
                Stepper("Октава: \(octave)", value: $octave, in: 1...6)
                    .fixedSize()
            }
            .padding(.horizontal)

            keyboard
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .padding(.top)
        .background(Color(white: 0.12))
        .foregroundStyle(.white)
        .onChange(of: octave) {
            // Release any held notes when shifting octaves.
            pressed.forEach { synth.noteOff($0) }
            pressed.removeAll()
        }
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whiteKeys = keys.filter { !$0.isBlack }
            let blackKeys = keys.filter { $0.isBlack }
            let whiteWidth = geo.size.width / CGFloat(whiteKeys.count)
            let blackWidth = whiteWidth * 0.6
            let blackHeight = geo.size.height * 0.6

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteKeys) { key in
                        keyView(key, width: whiteWidth, height: geo.size.height)
                    }
                }
                ForEach(blackKeys) { key in
                    keyView(key, width: blackWidth, height: blackHeight)
                        .offset(x: CGFloat(key.whiteIndex + 1) * whiteWidth - blackWidth / 2)
                }
            }
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
                if !key.isBlack {
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
