import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/sensor_reading.dart';
import '../storage/history_store.dart';
import 'protocol.dart';

enum ConnectionStatus { disconnected, scanning, connecting, connected }

/// Owns the BLE connection to the wearable: scanning, connecting,
/// subscribing to the three notify characteristics, parsing packets, and
/// persisting vitals/env history. Exposed to the widget tree via Provider.
class BleService extends ChangeNotifier {
  final HistoryStore _historyStore;

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

  BluetoothAdapterState adapterState = FlutterBluePlus.adapterStateNow;

  BleService(this._historyStore) {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      adapterState = state;
      notifyListeners();
    });
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
        orElse: () => throw Exception('Health Companion service not found'),
      );

      for (final c in service.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid == HealthCompanionProtocol.vitalsCharUuid) {
          await _subscribe(c, _onVitals);
        } else if (uuid == HealthCompanionProtocol.envCharUuid) {
          await _subscribe(c, _onEnv);
        } else if (uuid == HealthCompanionProtocol.motionCharUuid) {
          await _subscribe(c, _onMotion);
        }
      }

      status = ConnectionStatus.connected;
    } catch (e) {
      lastError = 'Connect failed: $e';
      status = ConnectionStatus.disconnected;
    }
    notifyListeners();
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
    // Don't persist a no-finger reading — it's not a real HR/SpO2 sample,
    // and would otherwise sit in history as a 0 that later consumers
    // (the sparkline, BaselineService's rolling stats) would need to know
    // to filter back out.
    if (reading.fingerPresent) _historyStore.addVitals(reading);
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
    _scanSub?.cancel();
    _connSub?.cancel();
    _adapterSub?.cancel();
    for (final s in _valueSubs) {
      s.cancel();
    }
    super.dispose();
  }
}
