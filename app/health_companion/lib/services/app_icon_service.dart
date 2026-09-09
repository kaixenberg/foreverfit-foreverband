import 'package:flutter/services.dart';

/// Reads the app's actual currently-installed launcher icon from the OS
/// (see MainActivity.kt's `getAppIconPng`) instead of bundling a second
/// copy of it as a Flutter asset — so the loading screen's icon always
/// matches the real one, with nothing to keep in sync when it changes.
class AppIconService {
  static const _channel =
      MethodChannel('com.example.health_companion/app_icon');

  /// PNG bytes of the launcher icon, or null on any platform/plugin error
  /// (e.g. running on a non-Android platform) — callers fall back to a
  /// static icon in that case.
  static Future<Uint8List?> loadIconPng() async {
    try {
      return await _channel.invokeMethod<Uint8List>('getIconPng');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
