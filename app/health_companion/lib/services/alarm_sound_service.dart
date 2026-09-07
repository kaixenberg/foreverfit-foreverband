import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Loops a siren sound through Android's alarm audio stream (not the
/// ringer/media stream) and temporarily forces that stream to max volume,
/// so imminent-hazard warnings are audible even when the phone is on
/// silent or in Do Not Disturb — the same mechanism alarm-clock apps use.
class AlarmSoundService {
  static const _channel = MethodChannel('com.example.health_companion/alarm_volume');

  final AudioPlayer _player = AudioPlayer();
  int? _previousAlarmVolume;
  bool _playing = false;

  Future<void> start() async {
    if (_playing) return;
    _playing = true;

    try {
      _previousAlarmVolume = await _channel.invokeMethod<int>('boostAlarmVolume');
    } catch (_) {
      // Non-Android platform or channel unavailable — playback still
      // proceeds at whatever volume the platform allows.
    }

    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    await _player.play(AssetSource('sounds/alarm_siren.wav'));
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _player.stop();
    if (_previousAlarmVolume != null) {
      try {
        await _channel.invokeMethod('restoreAlarmVolume', _previousAlarmVolume);
      } catch (_) {}
      _previousAlarmVolume = null;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
