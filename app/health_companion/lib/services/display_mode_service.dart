import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// Requests the display's highest refresh rate at startup, again right
/// after the first frame is drawn, and again on every app resume —
/// Android doesn't reliably keep an app's preferred display mode across
/// every Activity lifecycle transition on some OEM skins, so re-
/// requesting on resume is a genuine retry, not just defensive
/// redundancy — same "retry on resume" shape already used for BLE
/// auto-connect (see `BleService`).
class DisplayModeService with WidgetsBindingObserver {
  DisplayModeService() {
    WidgetsBinding.instance.addObserver(this);
    // Also re-request right after the very first frame is drawn, not
    // just before runApp() — on some devices the window's surface isn't
    // fully established yet at the point main() calls apply(), so the
    // mode-change request can land before there's anything for it to
    // actually attach to. Cheap and harmless either way: apply() is a
    // no-op-equivalent if the mode is already correct.
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
  }

  /// Requests the display's highest refresh rate. Best-effort only, not
  /// a guarantee: some Android OEM skins — Xiaomi's HyperOS/MIUI chief
  /// among them — run their own refresh-rate governor on top of the
  /// standard Android API this plugin wraps, and can silently keep
  /// rendering at 60Hz regardless of what's requested here. This is a
  /// live, currently-unresolved issue across many Flutter apps on
  /// certain Xiaomi/POCO models specifically (see
  /// github.com/flutter/flutter/issues/160952, which names the Poco F5
  /// among affected devices), not something specific to this app or
  /// fixable purely from Dart/app code. If the app still looks capped
  /// at 60Hz after this, check the device's own Settings > Display >
  /// Refresh rate — several HyperOS/MIUI builds only apply their own
  /// adaptive-rate heuristic, which doesn't always promote regular
  /// (non-allowlisted) apps, while left on "Default"/"Auto"; switching
  /// it to a fixed 120Hz/"Custom" setting is the one thing confirmed to
  /// force it in reports of this same issue on other apps.
  Future<void> apply() async {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      final active = await FlutterDisplayMode.active;
      debugPrint('[DisplayMode] active mode after request: $active');
    } catch (e) {
      debugPrint('[DisplayMode] setHighRefreshRate failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) apply();
  }
}
