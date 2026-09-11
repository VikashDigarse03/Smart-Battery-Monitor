import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/device_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Lists registered ESP32 devices with option to add new ones.
class DevicesListView extends StatefulWidget {
  const DevicesListView({super.key});

  @override
  State<DevicesListView> createState() => _DevicesListViewState();
}

class _DevicesListViewState extends State<DevicesListView> {
  List<Device> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final repo = context.read<DeviceRepository>();
    _devices = await repo.getAllDevices();
    setState(() => _isLoading = false);
  }

  Future<void> _addDevice() async {
    final nameController = TextEditingController();
    final btAddressController = TextEditingController();
    final ipController = TextEditingController(text: '192.168.4.1');
    final ssidController = TextEditingController(text: 'ESP32_Battery');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register ESP32 Device'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'e.g., Battery Monitor Unit 1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: btAddressController,
                decoration: const InputDecoration(
                  labelText: 'Bluetooth Address (optional)',
                  hintText: 'e.g., AA:BB:CC:DD:EE:FF',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ssidController,
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'WiFi IP Address',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Register'),
          ),
        ],
      ),
    );

    if (result == true) {
      final repo = context.read<DeviceRepository>();
      final deviceId = await repo.generateNextDeviceId();
      final now = DateTime.now();
      await repo.insertDevice(Device(
        deviceId: deviceId,
        name: nameController.text.isEmpty ? null : nameController.text.trim(),
        bluetoothAddress: btAddressController.text.isEmpty
            ? null
            : btAddressController.text.trim(),
        wifiIpAddress:
            ipController.text.isEmpty ? null : ipController.text.trim(),
        wifiSsid:
            ssidController.text.isEmpty ? null : ssidController.text.trim(),
        createdAt: now,
        updatedAt: now,
      ));
      _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register Device',
            onPressed: _addDevice,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.developer_board,
                        size: 64,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No devices registered',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _addDevice,
                        icon: const Icon(Icons.add),
                        label: const Text('Register Device'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.developer_board,
                              color: AppTheme.accent,
                            ),
                          ),
                          title: Text(device.deviceId),
                          subtitle: Text(
                            device.name ??
                                device.wifiIpAddress ??
                                device.bluetoothAddress ??
                                'ESP32 Device',
                          ),
                          trailing: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: device.status == 'active'
                                  ? AppTheme.statusGood
                                  : AppTheme.statusInactive,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
