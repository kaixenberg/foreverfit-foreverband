package com.example.health_companion

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Bridges to Android's alarm audio stream (STREAM_ALARM) so the
/// imminent-disaster warning can be heard even when the phone's ringer is
/// silenced — alarm volume is a separate control from the ringer/media
/// volume the "silent mode" toggle affects.
class MainActivity : FlutterActivity() {
    private val channelName = "com.example.health_companion/alarm_volume"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "boostAlarmVolume" -> {
                        val previous = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
                        result.success(previous)
                    }
                    "restoreAlarmVolume" -> {
                        val previous = call.arguments as Int
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, previous, 0)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
