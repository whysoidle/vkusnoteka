package ru.recipevault.recipe_vault

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Short repeated signal using the alarm volume, with bounded playback and cleanup. */
class TimerAlarm(context: Context, private val channel: MethodChannel) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private var tone: ToneGenerator? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    try {
                        play()
                        result.success(null)
                    } catch (error: Exception) {
                        stop()
                        result.error("TIMER_SOUND_FAILED", error.message, null)
                    }
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun play() {
        stop()
        if (audio.getStreamVolume(AudioManager.STREAM_ALARM) == 0) {
            throw IllegalStateException("Громкость будильника установлена на ноль. Увеличьте её в настройках звука Android.")
        }
        tone = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        if (tone?.startTone(ToneGenerator.TONE_PROP_BEEP2, 500) != true) {
            throw IllegalStateException("Не удалось воспроизвести сигнал таймера.")
        }
        for (repeat in 1..7) {
            handler.postDelayed({
                runCatching { tone?.startTone(ToneGenerator.TONE_PROP_BEEP2, 500) }
            }, repeat * 800L)
        }
        handler.postDelayed({ stop() }, 6500L)
    }

    private fun stop() {
        handler.removeCallbacksAndMessages(null)
        val current = tone
        tone = null
        runCatching { current?.stopTone() }
        runCatching { current?.release() }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        stop()
    }
}
