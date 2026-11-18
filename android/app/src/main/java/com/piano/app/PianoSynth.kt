package com.piano.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tanh

/**
 * Polyphonic voice state shared between the UI and the real-time audio thread.
 * Accurately implements the mathematical model of VoiceBank from iOS PianoSynth.swift:
 * - Fundamental tone + 3 harmonics (1.0 * sin(p) + 0.5 * sin(2p) + 0.25 * sin(3p) + 0.1 * sin(4p))
 * - Realtime sustain decay and release decay
 * - tanh saturation soft-clipping
 */
class VoiceBank(private val sampleRate: Double = 44100.0) {
    private val lock = Any()
    private val phase = DoubleArray(128)
    private val level = DoubleArray(128)
    private val gate = BooleanArray(128)
    private val active = BooleanArray(128)

    private val twoPi = 2.0 * PI
    private val sustainDecay = 0.001.pow(1.0 / (sampleRate * 3.0))
    private val releaseDecay = 0.001.pow(1.0 / (sampleRate * 0.25))

    fun noteOn(note: Int) {
        if (note !in 0..127) return
        synchronized(lock) {
            phase[note] = 0.0
            level[note] = 1.0
            gate[note] = true
            active[note] = true
        }
    }

    fun noteOff(note: Int) {
        if (note !in 0..127) return
        synchronized(lock) {
            gate[note] = false
        }
    }

    fun render(buffer: ShortArray, size: Int) {
        synchronized(lock) {
            for (i in 0 until size) {
                var sample = 0.0
                for (note in 0..127) {
                    if (active[note]) {
                        val p = phase[note]
                        val tone = sin(p) + 0.5 * sin(2.0 * p) + 0.25 * sin(3.0 * p) + 0.1 * sin(4.0 * p)
                        sample += tone * level[note]

                        val freq = 440.0 * 2.0.pow((note - 69).toDouble() / 12.0)
                        phase[note] = (p + twoPi * freq / sampleRate) % twoPi
                        level[note] *= if (gate[note]) sustainDecay else releaseDecay
                        if (level[note] < 0.0001) {
                            active[note] = false
                        }
                    }
                }
                val saturated = tanh(sample * 0.15)
                buffer[i] = (saturated * 32767.0).coerceIn(-32768.0, 32767.0).toInt().toShort()
            }
        }
    }
}

/**
 * Lightweight SoundFont sample extractor and player.
 * Reads PCM sample data directly from the bundled SoundFont (.sf2) file
 * if available, falling back smoothly to the mathematical synthesizer.
 */
class SoundFontSampler(context: Context, assetName: String = "UprightPianoKW.sf2") {
    private class NoteSample(
        val data: ShortArray,
        val sampleRate: Int,
        val loopStart: Int,
        val loopEnd: Int,
        val isLooped: Boolean
    )

    private val samples = arrayOfNulls<NoteSample>(128)
    var isLoaded = false
        private set

    init {
        try {
            context.assets.open(assetName).use { input ->
                parseSf2(input)
            }
            isLoaded = true
        } catch (e: Exception) {
            isLoaded = false
        }
    }

    private fun parseSf2(input: InputStream) {
        val bytes = input.readBytes()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        // Verify RIFF & sfbk
        if (bytes.size < 12) return
        val riff = ByteArray(4)
        buffer.get(riff)
        if (String(riff) != "RIFF") return
        buffer.int // skip size
        val sfbk = ByteArray(4)
        buffer.get(sfbk)
        if (String(sfbk) != "sfbk") return

        // Find LIST 'sdta' -> 'smpl' and LIST 'pdta' -> 'shdr'
        var smplOffset = -1
        var smplLength = 0
        var shdrOffset = -1
        var shdrLength = 0

        while (buffer.remaining() >= 8) {
            val chunkId = ByteArray(4)
            buffer.get(chunkId)
            val chunkSize = buffer.int
            val chunkStr = String(chunkId)

            if (chunkStr == "LIST" && buffer.remaining() >= 4) {
                val listType = ByteArray(4)
                buffer.get(listType)
                val listStr = String(listType)
                val subRemaining = chunkSize - 4
                val subEnd = buffer.position() + subRemaining

                while (buffer.position() < subEnd && buffer.remaining() >= 8) {
                    val subId = ByteArray(4)
                    buffer.get(subId)
                    val subSize = buffer.int
                    val subStr = String(subId)
                    if (subStr == "smpl") {
                        smplOffset = buffer.position()
                        smplLength = subSize
                        buffer.position(buffer.position() + subSize)
                    } else if (subStr == "shdr") {
                        shdrOffset = buffer.position()
                        shdrLength = subSize
                        buffer.position(buffer.position() + subSize)
                    } else {
                        buffer.position(buffer.position() + subSize)
                    }
                }
            } else {
                buffer.position(buffer.position() + chunkSize)
            }
        }

        if (smplOffset > 0 && shdrOffset > 0 && smplLength > 0) {
            val smplBuffer = ByteBuffer.wrap(bytes, smplOffset, smplLength).order(ByteOrder.LITTLE_ENDIAN)
            val shdrBuffer = ByteBuffer.wrap(bytes, shdrOffset, shdrLength).order(ByteOrder.LITTLE_ENDIAN)
            val headerCount = shdrLength / 46

            for (h in 0 until headerCount) {
                shdrBuffer.position(h * 46)
                val nameBytes = ByteArray(20)
                shdrBuffer.get(nameBytes)
                val start = shdrBuffer.int
                val end = shdrBuffer.int
                val startLoop = shdrBuffer.int
                val endLoop = shdrBuffer.int
                val sampleRate = shdrBuffer.int
                val originalKey = shdrBuffer.get().toInt() and 0xFF
                shdrBuffer.get() // correction
                shdrBuffer.short // sample link
                val sampleType = shdrBuffer.short.toInt()

                // sampleType: 1 = mono, 2 = right, 4 = left, 0x8001 = linked
                if (originalKey in 0..127 && (sampleType == 1 || sampleType == 4) && end > start && end * 2 <= smplLength) {
                    val frameCount = end - start
                    val pcm = ShortArray(frameCount)
                    smplBuffer.position(start * 2)
                    smplBuffer.asShortBuffer().get(pcm)
                    samples[originalKey] = NoteSample(
                        data = pcm,
                        sampleRate = sampleRate,
                        loopStart = (startLoop - start).coerceAtLeast(0),
                        loopEnd = (endLoop - start).coerceAtMost(frameCount),
                        isLooped = (startLoop in start until end) && endLoop > startLoop
                    )
                }
            }
        }
    }

    private class ActiveVoice(
        val sample: NoteSample,
        val note: Int,
        var pos: Double = 0.0,
        var level: Double = 1.0,
        var gate: Boolean = true
    )

    private val activeVoices = ArrayList<ActiveVoice>()
    private val voiceLock = Any()

    fun noteOn(note: Int) {
        val s = samples[note] ?: return
        synchronized(voiceLock) {
            activeVoices.removeAll { it.note == note }
            activeVoices.add(ActiveVoice(sample = s, note = note))
        }
    }

    fun noteOff(note: Int) {
        synchronized(voiceLock) {
            activeVoices.forEach {
                if (it.note == note) it.gate = false
            }
        }
    }

    fun render(buffer: ShortArray, size: Int, outSampleRate: Double) {
        val releaseDecay = 0.001.pow(1.0 / (outSampleRate * 0.2))
        synchronized(voiceLock) {
            for (i in 0 until size) {
                var sum = 0.0
                val iterator = activeVoices.iterator()
                while (iterator.hasNext()) {
                    val v = iterator.next()
                    val s = v.sample
                    val p = v.pos.toInt()
                    if (p >= s.data.size) {
                        iterator.remove()
                        continue
                    }
                    val sampleVal = s.data[p] / 32768.0
                    sum += sampleVal * v.level

                    val step = s.sampleRate.toDouble() / outSampleRate
                    v.pos += step
                    if (!v.gate) {
                        v.level *= releaseDecay
                        if (v.level < 0.0001) {
                            iterator.remove()
                            continue
                        }
                    }
                }
                val saturated = tanh(sum * 0.8)
                buffer[i] = (saturated * 32767.0).coerceIn(-32768.0, 32767.0).toInt().toShort()
            }
        }
    }
}

/**
 * PianoSynth manages the audio engine and provides low-latency noteOn/noteOff methods.
 * Corresponds to PianoSynth in iOS Swift code.
 */
class PianoSynth(context: Context) {
    private val sampleRate = 44100
    private val bufferSize = AudioTrack.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_OUT_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    ).coerceAtLeast(1024)

    private val audioTrack: AudioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
        )
        .setBufferSizeInBytes(bufferSize * 2)
        .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        .build()

    private val voices = VoiceBank(sampleRate.toDouble())
    private var sampler: SoundFontSampler? = null
    private val isRunning = AtomicBoolean(true)
    private var audioThread: Thread? = null

    init {
        if (FeatureFlags.USE_SAMPLED_PIANO) {
            val s = SoundFontSampler(context)
            if (s.isLoaded) {
                sampler = s
            }
        }

        audioTrack.play()
        audioThread = Thread {
            val renderBuffer = ShortArray(256)
            while (isRunning.get()) {
                val s = sampler
                if (s != null) {
                    s.render(renderBuffer, renderBuffer.size, sampleRate.toDouble())
                } else {
                    voices.render(renderBuffer, renderBuffer.size)
                }
                audioTrack.write(renderBuffer, 0, renderBuffer.size)
            }
        }.apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    fun noteOn(note: Int) {
        if (note !in 0..127) return
        sampler?.noteOn(note) ?: voices.noteOn(note)
    }

    fun noteOff(note: Int) {
        if (note !in 0..127) return
        sampler?.noteOff(note) ?: voices.noteOff(note)
    }

    fun release() {
        isRunning.set(false)
        try {
            audioThread?.join(500)
            audioTrack.stop()
            audioTrack.release()
        } catch (_: Exception) {}
    }
}
