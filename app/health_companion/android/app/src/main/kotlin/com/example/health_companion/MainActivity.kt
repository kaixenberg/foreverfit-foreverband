package com.example.health_companion

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.SmsManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Bridges to Android's alarm audio stream (STREAM_ALARM) so the
/// imminent-disaster warning can be heard even when the phone's ringer is
/// silenced — alarm volume is a separate control from the ringer/media
/// volume the "silent mode" toggle affects.
class MainActivity : FlutterActivity() {
    private val alarmVolumeChannelName = "com.example.health_companion/alarm_volume"
    private val telephonyChannelName = "com.example.health_companion/telephony"
    private val telephonyEventsChannelName = "com.example.health_companion/telephony_events"

    // Only one of these is ever non-null, depending on API level — see
    // startCallStateWatch(). Kept as fields so stopCallStateWatch() can
    // unregister the same listener instance later.
    private var legacyCallStateListener: PhoneStateListener? = null
    private var modernCallStateListener: TelephonyCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alarmVolumeChannelName)
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

        // All emergency-call telephony primitives live in this one channel —
        // see ARCHITECTURE.md for why this is hand-rolled Kotlin rather than
        // a third-party call/SMS plugin. Every branch is defensive
        // (try/catch → result.error) since a missing runtime permission
        // must surface as a clean Dart-side error, not a native crash.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, telephonyChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getEmergencyNumbers" -> result.success(getEmergencyNumbers(telephonyManager))
                    "dialEmergencyNumber" -> {
                        val number = call.argument<String>("number")
                        if (number == null) {
                            result.error("BAD_ARGS", "Missing number", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("DIAL_FAILED", e.message, null)
                        }
                    }
                    "callContact" -> {
                        val number = call.argument<String>("number")
                        if (number == null) {
                            result.error("BAD_ARGS", "Missing number", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION_DENIED", e.message, null)
                        } catch (e: Exception) {
                            result.error("CALL_FAILED", e.message, null)
                        }
                    }
                    "setSpeakerphoneOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        try {
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = on
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SPEAKER_FAILED", e.message, null)
                        }
                    }
                    "sendSms" -> {
                        val number = call.argument<String>("number")
                        val text = call.argument<String>("text")
                        if (number == null || text == null) {
                            result.error("BAD_ARGS", "Missing number or text", null)
                            return@setMethodCallHandler
                        }
                        try {
                            @Suppress("DEPRECATION")
                            val smsManager = SmsManager.getDefault()
                            val parts = smsManager.divideMessage(text)
                            smsManager.sendMultipartTextMessage(
                                number, null, parts, null, null,
                            )
                            result.success(null)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION_DENIED", e.message, null)
                        } catch (e: Exception) {
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, telephonyEventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startCallStateWatch(telephonyManager, events)
                }

                override fun onCancel(arguments: Any?) {
                    stopCallStateWatch(telephonyManager)
                }
            })
    }

    /// API 29+ can ask the platform for the device's actual regional
    /// emergency number(s) instead of hardcoding one — falls back to "112"
    /// (India's unified number, also the GSM-standard fallback) when the
    /// API isn't available or the lookup fails for any reason.
    private fun getEmergencyNumbers(telephonyManager: TelephonyManager): List<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val bySubscription = telephonyManager.emergencyNumberList
                val numbers = bySubscription.values
                    .flatten()
                    .map { it.number }
                    .distinct()
                if (numbers.isNotEmpty()) return numbers
            } catch (_: Exception) {
                // Fall through to the static fallback below.
            }
        }
        return listOf("112")
    }

    /// Only the coarse IDLE/OFFHOOK call state is available to a normal
    /// app (see ARCHITECTURE.md) — there is no distinct "ringing" vs
    /// "active" signal for an outgoing call without READ_PRECISE_PHONE_STATE,
    /// which is system-signature-only. Version-gated because
    /// TelephonyCallback needs API 31+ and this app's minSdk is 24.
    private fun startCallStateWatch(telephonyManager: TelephonyManager, events: EventChannel.EventSink) {
        val mainHandler = Handler(Looper.getMainLooper())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    mainHandler.post { events.success(callStateName(state)) }
                }
            }
            modernCallStateListener = callback
            telephonyManager.registerTelephonyCallback(mainExecutor, callback)
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Suppress("DEPRECATION")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    mainHandler.post { events.success(callStateName(state)) }
                }
            }
            legacyCallStateListener = listener
            @Suppress("DEPRECATION")
            telephonyManager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun stopCallStateWatch(telephonyManager: TelephonyManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modernCallStateListener?.let { telephonyManager.unregisterTelephonyCallback(it) }
            modernCallStateListener = null
        } else {
            @Suppress("DEPRECATION")
            legacyCallStateListener?.let {
                telephonyManager.listen(it, PhoneStateListener.LISTEN_NONE)
            }
            legacyCallStateListener = null
        }
    }

    private fun callStateName(state: Int): String = when (state) {
        TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
        else -> "idle" // IDLE and RINGING (an incoming call, not relevant here) both collapse to idle.
    }
}
