import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sensor_reading.dart';
import '../storage/history_store.dart';
import '../storage/watch_settings_store.dart';
import 'protocol.dart';

enum ConnectionStatus { disconnected, scanning, connecting, connected }

/// Owns the BLE connection to the wearable: scanning, connecting,
/// subscribing to the three notify characteristics, parsing packets, and
/// persisting vitals/env history. Exposed to the widget tree via Provider.
///
/// `with WidgetsBindingObserver` purely for the app-resume auto-connect
/// retry below — a ChangeNotifier can register itself as an observer the
/// same way a State can, it doesn't need to be a widget to do so.
class BleService extends ChangeNotifier with WidgetsBindingObserver {
  final HistoryStore _historyStore;
  final WatchSettingsStore _watchSettingsStore;

  ConnectionStatus status = ConnectionStatus.disconnected;
  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final List<StreamSubscription<List<int>>> _valueSubs = [];
  final List<ScanResult> discovered = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  VitalsReading? latestVitals;
  EnvReading? latestEnv;
  MotionReading? latestMotion;
  String? lastError;

  /// When the wearable last finished connecting — lets consumers (see
  /// dashboard_screen.dart's body-temp equilibrium gate) tell "just
  /// connected" from "connected a while ago." Set on every successful
  /// connect, deliberately never cleared on disconnect (same convention
  /// as latestVitals/latestEnv above — this app shows the last-known
  /// state rather than blanking it out while disconnected).
  DateTime? connectedAt;

  BluetoothCharacteristic? _timeChar;
  Timer? _timeSyncTimer;
  BluetoothCharacteristic? _watchSettingsChar;

  BluetoothAdapterState adapterState = FlutterBluePlus.adapterStateNow;

  BleService(this._historyStore, this._watchSettingsStore) {
    WidgetsBinding.instance.addObserver(this);

    // Auto-connect is driven from here, reactively, rather than a one-shot
    // call from main.dart's first frame — that raced against the adapter
    // state stream's first real event (adapterStateNow reads "unknown"
    // until the native side reports back, an async round-trip that isn't
    // guaranteed to land before the first frame), so it could silently
    // no-op and then never retry. FlutterBluePlus.adapterState replays
    // its current value to every new listener (confirmed by reading the
    // plugin source), so this fires promptly either way — but it only
    // fires again on a genuine *change*, so on its own it wouldn't retry
    // if the very first attempt happened to race a not-yet-granted
    // permission. didChangeAppLifecycleState below is the retry for that.
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      adapterState = state;
      notifyListeners();
      if (state == BluetoothAdapterState.on) autoConnect();
    });
  }

  /// Retries auto-connect every time the app comes to the foreground —
  /// covers reopening the app, and is a safety net if the very first
  /// attempt (from the constructor above) ran before Bluetooth
  /// permissions were actually granted and silently no-opped as a
  /// result. autoConnect() is already guarded to do nothing once
  /// connected, so this is safe to call unconditionally on every resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) autoConnect();
  }

  Future<void> startScan() async {
    discovered.clear();
    status = ConnectionStatus.scanning;
    lastError = null;
    notifyListeners();

    // startScan below already filters by service UUID at the OS level.
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!discovered.any((d) => d.device.remoteId == r.device.remoteId)) {
          discovered.add(r);
        }
      }
      notifyListeners();
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [Guid(HealthCompanionProtocol.serviceUuid)],
      );
      // startScan()'s own await resolves as soon as the scan *starts*,
      // not when it ends — confirmed by reading the plugin source: the
      // `timeout` param only schedules an internal stopScan() call for
      // later, it doesn't make this awaitable. Without this, `status`
      // flips back to "disconnected" within milliseconds of tapping
      // "Scan," even though scanning is genuinely still happening in the
      // background (discovered devices still populate the list below via
      // the notify-driven listener — this was only a `status` bug, not a
      // "scanning doesn't work" bug).
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning.where((s) => s == false).first;
      }
    } catch (e) {
      lastError = 'Scan failed: $e';
    }

    if (status == ConnectionStatus.scanning) {
      status = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
  }

  /// Scans for the wearable and connects to the first one found — used to
  /// auto-connect on app launch instead of requiring a manual "Scan &
  /// Connect" tap every time. A no-op if already connected/connecting/
  /// scanning, or if Bluetooth is off (nothing to scan for in that case);
  /// safe to call on every rebuild the same way BackgroundMonitoringService
  /// .start() is (see main.dart) — guarded internally, not a standing
  /// timer.
  Future<void> autoConnect() async {
    if (status != ConnectionStatus.disconnected) {
      debugPrint('[BLE] autoConnect: skipped, status=$status');
      return;
    }
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('[BLE] autoConnect: skipped, adapterState=$adapterState');
      return;
    }

    // Checked explicitly (rather than just letting startScan() throw and
    // catching it) so a missing permission is visibly distinguishable
    // from "no device found" in the log below — the two used to look
    // identical, both silently doing nothing.
    final scanGranted = await Permission.bluetoothScan.isGranted;
    final connectGranted = await Permission.bluetoothConnect.isGranted;
    if (!scanGranted || !connectGranted) {
      debugPrint('[BLE] autoConnect: skipped, permission not granted '
          '(scan=$scanGranted connect=$connectGranted)');
      return;
    }

    debugPrint('[BLE] autoConnect: scanning...');
    discovered.clear();
    status = ConnectionStatus.scanning;
    lastError = null;
    notifyListeners();

    BluetoothDevice? found;
    final resultsSub = FlutterBluePlus.scanResults.listen((results) {
      // Stops the scan the moment a match shows up, rather than always
      // waiting out the full timeout below — the common case is the
      // wearable already being in range at app launch.
      if (results.isNotEmpty && found == null) {
        found = results.first.device;
        FlutterBluePlus.stopScan();
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withServices: [Guid(HealthCompanionProtocol.serviceUuid)],
      );
      // This is the actual root cause of auto-connect never finding the
      // wearable, confirmed via real device logs (adb logcat): the await
      // above resolves the instant the scan *starts* (tens of ms), not
      // when it ends — the plugin's `timeout` param only schedules an
      // internal stopScan() for later, it doesn't make this awaitable.
      // Without this, `found` was being checked before the wearable had
      // any real chance to be seen, every single time — the logs showed
      // "scanning..." immediately followed by "no matching device found"
      // ~120ms later, nowhere near the real 8s window. Wait for the scan
      // to actually stop (either the listener below calling stopScan()
      // early after a match, or the internal timer) before checking.
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning.where((s) => s == false).first;
      }
    } catch (e) {
      lastError = 'Auto-connect scan failed: $e';
      debugPrint('[BLE] autoConnect: scan threw: $e');
    }
    await resultsSub.cancel();

    if (found != null) {
      debugPrint('[BLE] autoConnect: found ${found!.remoteId}, connecting');
      await connect(found!);
    } else {
      debugPrint('[BLE] autoConnect: no matching device found within timeout');
      status = ConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    await stopScan();
    status = ConnectionStatus.connecting;
    lastError = null;
    notifyListeners();

    try {
      _device = device;
      await device.connect(timeout: const Duration(seconds: 10));

      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          status = ConnectionStatus.disconnected;
          notifyListeners();
        }
      });

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.uuid.toString().toLowerCase() ==
            HealthCompanionProtocol.serviceUuid,
        orElse: () => throw Exception('ForeverBand service not found'),
      );

      _timeChar = null;
      _watchSettingsChar = null;
      for (final c in service.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid == HealthCompanionProtocol.vitalsCharUuid) {
          await _subscribe(c, _onVitals);
        } else if (uuid == HealthCompanionProtocol.envCharUuid) {
          await _subscribe(c, _onEnv);
        } else if (uuid == HealthCompanionProtocol.motionCharUuid) {
          await _subscribe(c, _onMotion);
        } else if (uuid == HealthCompanionProtocol.timeCharUuid) {
          _timeChar = c;
        } else if (uuid == HealthCompanionProtocol.watchSettingsCharUuid) {
          _watchSettingsChar = c;
        }
      }

      status = ConnectionStatus.connected;
      connectedAt = DateTime.now();

      // Lets the OLED show a real clock/date with no RTC or network access
      // of its own — one write now, then a periodic re-sync so a long-
      // running session doesn't drift against millis()-based timekeeping
      // on the firmware side. Best-effort: a write failure here shouldn't
      // fail the whole connection, the watch face just falls back to
      // "--:--" until the next successful sync (see health_companion.ino).
      unawaited(_syncTime());
      _timeSyncTimer?.cancel();
      _timeSyncTimer =
          Timer.periodic(const Duration(minutes: 5), (_) => _syncTime());

      // Applies whatever watch-face preferences were already set (or the
      // defaults) the moment the wearable connects — otherwise it would
      // sit at firmware defaults until the user happened to open the
      // watch settings screen and change something.
      unawaited(syncWatchSettings());
    } catch (e) {
      lastError = 'Connect failed: $e';
      status = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> _syncTime() async {
    final timeChar = _timeChar;
    if (timeChar == null) return;
    try {
      await timeChar.write(
        HealthCompanionProtocol.buildTimeSyncPacket(DateTime.now()),
        withoutResponse: timeChar.properties.writeWithoutResponse,
      );
    } catch (_) {
      // Best-effort — see the comment where this is first called.
    }
  }

  /// Pushes the current WatchSettingsStore state to the wearable. Called
  /// automatically on connect, and again by WatchSettingsScreen whenever
  /// the user changes a preference while already connected — a no-op
  /// (not an error) if not connected, since the store itself is the
  /// source of truth and will just get pushed on the next connect.
  Future<void> syncWatchSettings() async {
    final char = _watchSettingsChar;
    if (char == null) return;
    try {
      await char.write(
        HealthCompanionProtocol.buildWatchSettingsPacket(
            _watchSettingsStore.settings),
        withoutResponse: char.properties.writeWithoutResponse,
      );
    } catch (e) {
      lastError = 'Watch settings sync failed: $e';
      notifyListeners();
    }
  }

  Future<void> _subscribe(
    BluetoothCharacteristic c,
    void Function(List<int>) onData,
  ) async {
    await c.setNotifyValue(true);
    final sub = c.lastValueStream.listen(onData);
    _valueSubs.add(sub);
  }

  void _onVitals(List<int> bytes) {
    final reading = HealthCompanionProtocol.parseVitals(bytes);
    if (reading == null) return;
    latestVitals = reading;
    // Persist whenever there's at least one real reading in the packet —
    // HR/SpO2 (gated on finger contact) or body temp (gated on its own
    // DS18B20 reading, independent of finger contact, see
    // readBodyTempC() in health_companion.ino). A record with one signal
    // zeroed is expected now (e.g. no finger but a valid body temp); the
    // 0/1 history consumers (sparklines, BaselineService) already filter
    // their own metric back out rather than assuming every stored record
    // has every field.
    if (reading.fingerPresent || reading.bodyTempC != 0) {
      _historyStore.addVitals(reading);
    }
    notifyListeners();
  }

  void _onEnv(List<int> bytes) {
    final reading = HealthCompanionProtocol.parseEnv(bytes);
    if (reading == null) return;
    latestEnv = reading;
    _historyStore.addEnv(reading);
    notifyListeners();
  }

  void _onMotion(List<int> bytes) {
    final reading = HealthCompanionProtocol.parseMotion(bytes);
    if (reading == null) return;
    latestMotion = reading;
    // High-rate motion samples are not persisted to history; they exist for
    // live display and future on-device fall-detection windows only (see
    // ARCHITECTURE.md).
    notifyListeners();
  }

  Future<void> disconnect() async {
    _timeSyncTimer?.cancel();
    _timeChar = null;
    _watchSettingsChar = null;
    for (final s in _valueSubs) {
      await s.cancel();
    }
    _valueSubs.clear();
    await _connSub?.cancel();
    await _device?.disconnect();
    status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel();
    _connSub?.cancel();
    _adapterSub?.cancel();
    _timeSyncTimer?.cancel();
    for (final s in _valueSubs) {
      s.cancel();
    }
    super.dispose();
  }
}
