package com.piano.app

/**
 * Compile-time feature flags matching iOS implementation.
 */
object FeatureFlags {
    /** Shows note names on the white keys. */
    const val SHOW_KEY_LABELS = false

    /** Shows the name of the first visible note next to the shift stepper. */
    const val SHOW_START_NOTE_NAME = false

    /** Shows the visible white key count next to the zoom stepper. */
    const val SHOW_ZOOM_LABEL = false

    /** Plays real piano samples (bundled SoundFont) instead of the built-in synthesizer. */
    const val USE_SAMPLED_PIANO = true
}
