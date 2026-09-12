import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:provider/provider.dart';
import 'package:wifi_iot/wifi_iot.dart';

import '../../../../data/database/app_database.dart';
import '../../../../data/services/esp32_service.dart';

class Esp32ConnectionDialog extends StatefulWidget {
  final String mode;
  const Esp32ConnectionDialog({super.key, required this.mode});

  static Future<void> show(BuildContext context, {required String mode}) {
    return showDialog(
      context: context,
      builder: (context) => Esp32ConnectionDialog(mode: mode),
    );
  }

  @override
  State<Esp32ConnectionDialog> createState() => _Esp32ConnectionDialogState();
}

class _Esp32ConnectionDialogState extends State<Esp32ConnectionDialog> {
  bool _isConnecting = false;
  List<BluetoothDevice> _devices = [];
  String _wifiStatusText = 'Connecting to ESP32_Battery...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.mode == 'wifi') {
      _connectWifi(); // Automatically attempt connection if opened in wifi mode
    }
  }

  Future<void> _loadSettings() async {
    if (widget.mode == 'bluetooth') {
      try {
        final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
        setState(() => _devices = devices);
      } catch (e) {
        debugPrint('Error getting BT devices: $e');
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    try {
      final btService = context.read<Esp32BluetoothService>();
      final connected = await btService.connect(device.address);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              connected
                  ? 'Connected to ${device.name}'
                  : 'Failed to connect to ${device.name}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _connectWifi() async {
    setState(() {
      _isConnecting = true;
      _wifiStatusText = 'Connecting to ESP32_Battery WiFi...';
    });
    
    try {
      // 1. Attempt to connect to the WiFi AP programmatically
      final isConnectedToWifi = await WiFiForIoTPlugin.connect(
        'ESP32_Battery',
        password: '12345678',
        joinOnce: false,
        security: NetworkSecurity.WPA,
        withInternet: false, // ESP32 AP doesn't have internet
      );
      
      if (!isConnectedToWifi) {
        if (mounted) {
          setState(() {
            _wifiStatusText = 'Failed to auto-connect to ESP32_Battery WiFi.\nPlease connect manually in your phone settings, then click Verify Connection.';
            _isConnecting = false;
          });
        }
        return;
      }
      
      // Force wifi usage if possible (helps on Android 10+)
      await WiFiForIoTPlugin.forceWifiUsage(true);

      if (mounted) {
        setState(() => _wifiStatusText = 'WiFi connected! Pinging device...');
      }

      // Wait a moment for network to stabilize
      await Future.delayed(const Duration(seconds: 3));

      // 2. Ping device via HTTP
      await _verifyWifiConnection();

    } catch (e) {
      if (mounted) {
        setState(() {
          _wifiStatusText = 'Error connecting automatically.\nPlease connect manually to ESP32_Battery in settings, then click Verify Connection.';
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _verifyWifiConnection() async {
    setState(() {
      _isConnecting = true;
      _wifiStatusText = 'Verifying connection to ESP32...';
    });

    try {
      final wifiService = context.read<Esp32WifiService>();
      final db = context.read<AppDatabase>();
      final ip = await db.getSetting('esp32_ip_address') ?? '192.168.4.1';
      wifiService.setIpAddress(ip);
      
      final connected = await wifiService.pingDevice();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              connected ? 'Connected to ESP32 WiFi' : 'Failed to reach ESP32 at $ip',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wifiStatusText = 'Could not reach ESP32. Ensure you are connected to its WiFi.';
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to ESP32'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isConnecting
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_wifiStatusText, textAlign: TextAlign.center),
                ],
              )
            : widget.mode == 'wifi'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _wifiStatusText,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: _verifyWifiConnection,
                            child: const Text('Verify Connection'),
                          ),
                          OutlinedButton(
                            onPressed: _connectWifi,
                            child: const Text('Retry Auto'),
                          ),
                        ],
                      ),
                    ],
                  )
                : _devices.isEmpty 
                  ? const Text('No paired Bluetooth devices found.')
                  : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name ?? 'Unknown Device'),
                        subtitle: Text(device.address),
                        onTap: () => _connect(device),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
