package com.piano.app

import kotlin.math.abs

/**
 * A single piano key description.
 * Matches the iOS [PianoKey] model and logic.
 */
data class PianoKey(
    val note: Int,          // MIDI note number (0..127)
    val isBlack: Boolean,
    val whiteIndex: Int     // index of the white key this key sits on (or to the left of, for black keys)
) {
    val id: Int get() = note

    val name: String
        get() {
            val names = arrayOf("C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B")
            return names[note % 12]
        }

    /** Note name with octave number in scientific pitch notation, e.g. "C4". */
    val fullName: String
        get() = "$name${(note / 12) - 1}"

    companion object {
        /** Semitone offsets of the white keys within an octave. */
        val WHITE_SEMITONES = intArrayOf(0, 2, 4, 5, 7, 9, 11)

        /** MIDI note of the white key with the given absolute index (0 = C-1). */
        fun whiteNote(index: Int): Int {
            return (index / 7) * 12 + WHITE_SEMITONES[index % 7]
        }

        /**
         * Builds [whiteCount] white keys (plus the black keys between and right after them)
         * starting at [startNote], which must be a white key.
         */
        fun keys(startNote: Int, whiteCount: Int): List<PianoKey> {
            val result = ArrayList<PianoKey>()
            var whites = 0
            var note = startNote
            while (note <= 127) {
                if (WHITE_SEMITONES.contains(note % 12)) {
                    if (whites >= whiteCount) break
                    result.add(PianoKey(note = note, isBlack = false, whiteIndex = whites))
                    whites++
                } else {
                    result.add(PianoKey(note = note, isBlack = true, whiteIndex = whites - 1))
                }
                note++
            }
            return result
        }
    }
}
