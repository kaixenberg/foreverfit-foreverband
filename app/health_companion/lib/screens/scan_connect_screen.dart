import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';

class ScanConnectScreen extends StatefulWidget {
  const ScanConnectScreen({super.key});

  @override
  State<ScanConnectScreen> createState() => _ScanConnectScreenState();
}

class _ScanConnectScreenState extends State<ScanConnectScreen> {
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndScan();
  }

  Future<void> _requestPermissionsAndScan() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final granted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
    setState(() => _permissionsGranted = granted);

    if (granted && mounted) {
      context.read<BleService>().startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Wearable')),
      body: !_permissionsGranted
          ? _PermissionRequest(onRetry: _requestPermissionsAndScan)
          : _buildBody(ble),
      floatingActionButton: _permissionsGranted
          ? FloatingActionButton.extended(
              onPressed: ble.status == ConnectionStatus.scanning
                  ? null
                  : () => ble.startScan(),
              icon: const Icon(Icons.search),
              label: Text(
                ble.status == ConnectionStatus.scanning
                    ? 'Scanning...'
                    : 'Scan again',
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BleService ble) {
    if (ble.adapterState != BluetoothAdapterState.on) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth_disabled,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              const Text(
                'Bluetooth is off — turn it on to scan for the wearable.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => FlutterBluePlus.turnOn(),
                child: const Text('Turn on Bluetooth'),
              ),
            ],
          ),
        ),
      );
    }

    if (ble.lastError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ble.lastError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (ble.discovered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Looking for your HealthCompanion wearable...\n'
            'Make sure it is powered on and nearby.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: ble.discovered.length,
      itemBuilder: (context, index) {
        final result = ble.discovered[index];
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : result.device.remoteId.str;
        return ListTile(
          leading: const Icon(Icons.watch),
          title: Text(name),
          subtitle: Text(result.device.remoteId.str),
          trailing: ble.status == ConnectionStatus.connecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: () async {
            await ble.connect(result.device);
            // Reached via a button push from the dashboard now, not the
            // app's home route — return to wherever it was opened from.
            if (ble.status == ConnectionStatus.connected && mounted) {
              Navigator.of(context).pop();
            }
          },
        );
      },
    );
  }
}

class _PermissionRequest extends StatelessWidget {
  const _PermissionRequest({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bluetooth and location permissions are required to scan for '
              'the wearable.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: onRetry, child: const Text('Grant permissions')),
          ],
        ),
      ),
    );
  }
}
