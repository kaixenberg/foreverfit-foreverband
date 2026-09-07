import 'package:hive_flutter/hive_flutter.dart';

import '../models/sensor_reading.dart';

/// Local, offline history of vitals/environment readings. Uses Hive so
/// everything stays on-device — no server, no sync, works with no network.
class HistoryStore {
  static const String vitalsBoxName = 'vitals_history';
  static const String envBoxName = 'env_history';

  late Box<Map> _vitalsBox;
  late Box<Map> _envBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _vitalsBox = await Hive.openBox<Map>(vitalsBoxName);
    _envBox = await Hive.openBox<Map>(envBoxName);
  }

  Future<void> addVitals(VitalsReading reading) =>
      _vitalsBox.add(reading.toMap());

  Future<void> addEnv(EnvReading reading) => _envBox.add(reading.toMap());

  List<Map> recentVitals({int limit = 50}) => _recent(_vitalsBox, limit);

  List<Map> recentEnv({int limit = 50}) => _recent(_envBox, limit);

  List<Map> _recent(Box<Map> box, int limit) {
    final values = box.values.toList();
    if (values.length <= limit) return values;
    return values.sublist(values.length - limit);
  }
}
