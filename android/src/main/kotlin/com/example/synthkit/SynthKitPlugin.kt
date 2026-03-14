package com.example.synthkit

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.HandlerThread
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class SynthKitPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val engine = AndroidSynthKitEngine()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "synthkit")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "getBackendName" -> result.success("native-android")
                "initialize" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    engine.initialize(args.double("masterVolume", 0.8))
                    result.success(null)
                }
                "disposeEngine" -> {
                    engine.disposeEngine()
                    result.success(null)
                }
                "setMasterVolume" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    engine.setMasterVolume(args.double("volume", 0.8))
                    result.success(null)
                }
                "createSynth" -> {
                    val args = call.arguments as? Map<*, *>
                        ?: throw IllegalArgumentException("Expected a synth config map.")
                    result.success(engine.createSynth(AndroidSynthSpec.from(args)))
                }
                "updateSynth" -> {
                    val args = call.arguments as? Map<*, *>
                        ?: throw IllegalArgumentException("Expected a synth config map.")
                    val synthId = args.requiredString("synthId")
                    engine.updateSynth(synthId, AndroidSynthSpec.from(args))
                    result.success(null)
                }
                "triggerNote" -> {
                    val args = call.arguments as? Map<*, *>
                        ?: throw IllegalArgumentException("Expected a trigger note map.")
                    val synthId = args.requiredString("synthId")
                    engine.triggerNote(
                        synthId = synthId,
                        frequencyHz = args.double("frequencyHz", 440.0),
                        durationMs = args.int("durationMs", 500),
                        velocity = args.double("velocity", 1.0),
                        delayMs = args.int("delayMs", 0),
                    )
                    result.success(null)
                }
                "cancelScheduledNotes" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    engine.cancelScheduledNotes(args["synthId"] as? String)
                    result.success(null)
                }
                "panic" -> {
                    engine.panic()
                    result.success(null)
                }
                "disposeSynth" -> {
                    val args = call.arguments as? Map<*, *>
                        ?: throw IllegalArgumentException("Expected a synth id map.")
                    engine.disposeSynth(args.requiredString("synthId"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("synthkit/error", error.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine.disposeEngine()
        channel.setMethodCallHandler(null)
    }
}

private class AndroidSynthKitEngine {
    private val sampleRate = 44_100
    private val channelCount = 2
    private val renderBufferFrames = 256
    private val synths = ConcurrentHashMap<String, AndroidSynthSpec>()
    private val scheduled = ConcurrentHashMap<String, MutableList<Runnable>>()
    private val voices = mutableListOf<Voice>()
    private val voiceLock = Any()

    @Volatile
    private var masterVolume = 0.8

    @Volatile
    private var isRunning = false

    private var nextSynthId = 1
    private var audioTrack: AudioTrack? = null
    private var renderThread: Thread? = null
    private var schedulerThread: HandlerThread? = null
    private var schedulerHandler: Handler? = null

    fun initialize(masterVolume: Double) {
        setMasterVolume(masterVolume)
        ensureScheduler()
        if (audioTrack != null) {
            return
        }

        val minimumBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val desiredBufferSize = max(minimumBufferSize, renderBufferFrames * channelCount * 2 * 4)
        audioTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .build(),
            desiredBufferSize,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
        audioTrack?.play()
        isRunning = true
        renderThread = Thread(RenderLoop(), "SynthKitRender").apply { start() }
    }

    fun disposeEngine() {
        panic()
        isRunning = false
        renderThread?.join(250)
        renderThread = null
        audioTrack?.pause()
        audioTrack?.flush()
        audioTrack?.release()
        audioTrack = null
        schedulerThread?.quitSafely()
        schedulerThread = null
        schedulerHandler = null
        synths.clear()
        scheduled.clear()
        synchronized(voiceLock) {
            voices.clear()
        }
    }

    fun setMasterVolume(volume: Double) {
        masterVolume = volume.coerceIn(0.0, 1.0)
    }

    fun createSynth(spec: AndroidSynthSpec): String {
        ensureScheduler()
        val synthId = "android_synth_${nextSynthId++}"
        synths[synthId] = spec
        return synthId
    }

    fun updateSynth(synthId: String, spec: AndroidSynthSpec) {
        require(synths.containsKey(synthId)) { "Unknown synth id: $synthId" }
        synths[synthId] = spec
    }

    fun triggerNote(
        synthId: String,
        frequencyHz: Double,
        durationMs: Int,
        velocity: Double,
        delayMs: Int,
    ) {
        val spec = synths[synthId] ?: throw IllegalArgumentException("Unknown synth id: $synthId")
        val clampedVelocity = velocity.coerceIn(0.0, 1.0)
        val playTask = object : Runnable {
            override fun run() {
                scheduled[synthId]?.removeAll { it === this }
                synchronized(voiceLock) {
                    voices.add(Voice(spec, frequencyHz, durationMs, clampedVelocity))
                }
            }
        }

        if (delayMs <= 0) {
            playTask.run()
            return
        }

        val handler = ensureScheduler()
        scheduled.getOrPut(synthId) { mutableListOf() }.add(playTask)
        handler.postDelayed(playTask, delayMs.toLong())
    }

    fun cancelScheduledNotes(synthId: String?) {
        val handler = schedulerHandler ?: return
        if (synthId != null) {
            scheduled.remove(synthId)?.forEach(handler::removeCallbacks)
            return
        }
        scheduled.values.forEach { callbacks ->
            callbacks.forEach(handler::removeCallbacks)
        }
        scheduled.clear()
    }

    fun panic() {
        cancelScheduledNotes(null)
        synchronized(voiceLock) {
            voices.clear()
        }
    }

    fun disposeSynth(synthId: String) {
        cancelScheduledNotes(synthId)
        synths.remove(synthId)
    }

    private fun ensureScheduler(): Handler {
        schedulerHandler?.let { return it }
        val thread = HandlerThread("SynthKitScheduler").also { it.start() }
        schedulerThread = thread
        return Handler(thread.looper).also { schedulerHandler = it }
    }

    private inner class RenderLoop : Runnable {
        override fun run() {
            val buffer = ShortArray(renderBufferFrames * channelCount)
            while (isRunning) {
                render(buffer, renderBufferFrames)
                audioTrack?.write(buffer, 0, buffer.size, AudioTrack.WRITE_BLOCKING)
            }
        }
    }

    private fun render(buffer: ShortArray, frameCount: Int) {
        synchronized(voiceLock) {
            for (frame in 0 until frameCount) {
                var mixed = 0.0
                val iterator = voices.iterator()
                while (iterator.hasNext()) {
                    val voice = iterator.next()
                    mixed += voice.nextSample(sampleRate)
                    if (voice.isFinished) {
                        iterator.remove()
                    }
                }
                val clamped = (mixed * masterVolume).coerceIn(-1.0, 1.0)
                val sample = (clamped * Short.MAX_VALUE).toInt().toShort()
                val index = frame * channelCount
                buffer[index] = sample
                buffer[index + 1] = sample
            }
        }
    }
}

private class Voice(
    private val spec: AndroidSynthSpec,
    private val frequencyHz: Double,
    durationMs: Int,
    velocity: Double,
) {
    private val attackSeconds = spec.envelope.attackMs / 1000.0
    private val decaySeconds = spec.envelope.decayMs / 1000.0
    private val sustainLevel = spec.envelope.sustain.coerceIn(0.0, 1.0)
    private val releaseSeconds = spec.envelope.releaseMs / 1000.0
    private val noteDurationSeconds = max(durationMs / 1000.0, 0.001)
    private val totalSeconds = noteDurationSeconds + max(releaseSeconds, 0.001)
    private val amplitude = velocity * spec.volume.coerceIn(0.0, 1.0)
    private val lowPassAlpha = if (spec.filter.enabled) {
        val dt = 1.0 / 44_100.0
        val rc = 1.0 / (2.0 * PI * spec.filter.cutoffHz.coerceAtLeast(10.0))
        dt / (rc + dt)
    } else {
        1.0
    }

    private var elapsedSeconds = 0.0
    private var phase = 0.0
    private var filterState = 0.0

    val isFinished: Boolean
        get() = elapsedSeconds >= totalSeconds

    fun nextSample(sampleRate: Int): Double {
        val envelope = envelopeAt(elapsedSeconds)
        val oscillator = when (spec.waveform) {
            "square" -> if (phase < 0.5) 1.0 else -1.0
            "triangle" -> 1.0 - 4.0 * abs(phase - 0.5)
            "sawtooth" -> (2.0 * phase) - 1.0
            else -> sin(phase * 2.0 * PI)
        }
        val dry = oscillator * envelope * amplitude
        val wet = if (spec.filter.enabled) {
            filterState += lowPassAlpha * (dry - filterState)
            filterState
        } else {
            dry
        }
        phase += frequencyHz / sampleRate.toDouble()
        if (phase >= 1.0) {
            phase -= phase.toInt()
        }
        elapsedSeconds += 1.0 / sampleRate.toDouble()
        return wet
    }

    private fun envelopeAt(timeSeconds: Double): Double {
        if (attackSeconds > 0 && timeSeconds < attackSeconds) {
            return timeSeconds / attackSeconds
        }

        val decayStart = attackSeconds
        val decayEnd = decayStart + decaySeconds
        if (decaySeconds > 0 && timeSeconds < decayEnd) {
            val progress = (timeSeconds - decayStart) / decaySeconds
            return 1.0 - ((1.0 - sustainLevel) * progress)
        }

        if (timeSeconds < noteDurationSeconds) {
            return sustainLevel
        }

        if (releaseSeconds > 0 && timeSeconds < totalSeconds) {
            val releaseProgress = (timeSeconds - noteDurationSeconds) / releaseSeconds
            return sustainLevel * (1.0 - releaseProgress.coerceIn(0.0, 1.0))
        }

        return 0.0
    }
}

private data class AndroidSynthSpec(
    val waveform: String,
    val volume: Double,
    val envelope: AndroidEnvelopeSpec,
    val filter: AndroidFilterSpec,
) {
    companion object {
        fun from(args: Map<*, *>): AndroidSynthSpec {
            val envelopeArgs = args["envelope"] as? Map<*, *> ?: emptyMap<String, Any?>()
            val filterArgs = args["filter"] as? Map<*, *> ?: emptyMap<String, Any?>()
            return AndroidSynthSpec(
                waveform = args["waveform"] as? String ?: "sine",
                volume = args.double("volume", 0.8),
                envelope = AndroidEnvelopeSpec.from(envelopeArgs),
                filter = AndroidFilterSpec.from(filterArgs),
            )
        }
    }
}

private data class AndroidEnvelopeSpec(
    val attackMs: Int,
    val decayMs: Int,
    val sustain: Double,
    val releaseMs: Int,
) {
    companion object {
        fun from(args: Map<*, *>): AndroidEnvelopeSpec {
            return AndroidEnvelopeSpec(
                attackMs = args.int("attackMs", 10),
                decayMs = args.int("decayMs", 120),
                sustain = args.double("sustain", 0.75),
                releaseMs = args.int("releaseMs", 240),
            )
        }
    }
}

private data class AndroidFilterSpec(
    val enabled: Boolean,
    val cutoffHz: Double,
) {
    companion object {
        fun from(args: Map<*, *>): AndroidFilterSpec {
            return AndroidFilterSpec(
                enabled = args["enabled"] as? Boolean ?: false,
                cutoffHz = args.double("cutoffHz", 1800.0),
            )
        }
    }
}

private fun Map<*, *>.requiredString(key: String): String {
    return this[key] as? String ?: throw IllegalArgumentException("Missing $key.")
}

private fun Map<*, *>.double(key: String, fallback: Double): Double {
    val value = this[key]
    return when (value) {
        is Double -> value
        is Int -> value.toDouble()
        is Long -> value.toDouble()
        is Float -> value.toDouble()
        is Number -> value.toDouble()
        else -> fallback
    }
}

private fun Map<*, *>.int(key: String, fallback: Int): Int {
    val value = this[key]
    return when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        is Float -> value.toInt()
        is Number -> value.toInt()
        else -> fallback
    }
}
