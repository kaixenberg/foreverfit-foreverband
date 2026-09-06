import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble/ble_service.dart';
import 'screens/scan_connect_screen.dart';
import 'storage/history_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final historyStore = HistoryStore();
  await historyStore.init();

  runApp(HealthCompanionApp(historyStore: historyStore));
}

class HealthCompanionApp extends StatelessWidget {
  const HealthCompanionApp({super.key, required this.historyStore});

  final HistoryStore historyStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HistoryStore>.value(value: historyStore),
        ChangeNotifierProvider(create: (_) => BleService(historyStore)),
      ],
      child: MaterialApp(
        title: 'Health Companion',
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const ScanConnectScreen(),
      ),
    );
  }
}
