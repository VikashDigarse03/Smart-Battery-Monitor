import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/battery_repository.dart';
import '../../../../data/repositories/measurement_repository.dart';
import '../../../../data/database/app_database.dart';
import '../../../../data/services/esp32_service.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';
import '../../../core/constants.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

/// Live measurement screen — connects to ESP32 and displays real-time readings.
///
/// Supports both Bluetooth Classic and WiFi (HTTP polling) connections.
/// The user can switch modes in Settings.
class MeasurementView extends StatefulWidget {
  final int batteryDbId;

  const MeasurementView({super.key, required this.batteryDbId});

  @override
  State<MeasurementView> createState() => _MeasurementViewState();
}

class _MeasurementViewState extends State<MeasurementView> {
  Battery? _battery;
  Esp32Reading? _latestReading;
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isSaving = false;
  String _connectionStatus = 'Disconnected';
  ConnectionMode _connectionMode = ConnectionMode.wifi;

  late Esp32WifiService _wifiService;
  late Esp32BluetoothService _btService;
  StreamSubscription<Esp32Reading>? _readingSub;

  @override
  void initState() {
    super.initState();
    _wifiService = context.read<Esp32WifiService>();
    _btService = context.read<Esp32BluetoothService>();
    _initialize();
  }

  Future<void> _initialize() async {
    final batteryRepo = context.read<BatteryRepository>();
    _battery = await batteryRepo.findById(widget.batteryDbId);

    // Load connection mode from settings
    final db = context.read<AppDatabase>();
    final modeString = await db.getSetting('connection_mode');
    _connectionMode = modeString == 'bluetooth' 
        ? ConnectionMode.bluetooth 
        : ConnectionMode.wifi;

    setState(() => _isLoading = false);
  }

  Future<void> _connectDevice() async {
    setState(() => _connectionStatus = 'Connecting...');

    if (_connectionMode == ConnectionMode.wifi) {
      // WiFi mode — poll ESP32 HTTP endpoint
      final reachable = await _wifiService.pingDevice();
      if (reachable) {
        _wifiService.startPolling();
        _readingSub = _wifiService.readingStream.listen((reading) {
          setState(() {
            _latestReading = reading;
            _isConnected = true;
            _connectionStatus = 'Connected (WiFi)';
          });
        });
        setState(() {
          _isConnected = true;
          _connectionStatus = 'Connected (WiFi)';
        });
      } else {
        setState(() {
          _connectionStatus = 'ESP32 not reachable';
          _isConnected = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot reach ESP32. Make sure you are connected to the ESP32 WiFi network.',
              ),
            ),
          );
        }
      }
    } else {
      // Bluetooth mode
      final device = await _selectBluetoothDevice();
      if (device == null) {
        setState(() {
          _connectionStatus = 'Disconnected';
          _isConnected = false;
        });
        return;
      }
      
      setState(() => _connectionStatus = 'Connecting to ${device.name ?? device.address}...');
      
      final connected = await _btService.connect(device.address);
      if (connected) {
        _readingSub = _btService.readingStream.listen((reading) {
          setState(() {
            _latestReading = reading;
            _isConnected = true;
            _connectionStatus = 'Connected (Bluetooth)';
          });
        });
        setState(() {
          _isConnected = true;
          _connectionStatus = 'Connected (Bluetooth)';
        });
      } else {
        setState(() {
          _connectionStatus = 'Bluetooth connection failed';
          _isConnected = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to the Bluetooth device.'),
            ),
          );
        }
      }
    }
  }

  Future<BluetoothDevice?> _selectBluetoothDevice() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return null;
      
      return showDialog<BluetoothDevice>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Select ESP32 Device'),
            content: SizedBox(
              width: double.maxFinite,
              child: devices.isEmpty 
                  ? const Text('No paired devices found. Please pair your ESP32 in Android Settings first.')
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    title: Text(device.name ?? 'Unknown device'),
                    subtitle: Text(device.address),
                    onTap: () => Navigator.pop(context, device),
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
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting Bluetooth devices: $e')),
        );
      }
      return null;
    }
  }

  void _disconnectDevice() {
    if (_connectionMode == ConnectionMode.wifi) {
      _wifiService.stopPolling();
    } else {
      _btService.disconnect();
    }
    _readingSub?.cancel();
    setState(() {
      _isConnected = false;
      _connectionStatus = 'Disconnected';
    });
  }

  Future<void> _saveMeasurement() async {
    if (_latestReading == null || _battery == null) return;

    setState(() => _isSaving = true);

    try {
      final measurementRepo = context.read<MeasurementRepository>();
      final now = DateTime.now();

      final measurement = Measurement(
        batteryId: _battery!.id!,
        voltage: _latestReading!.voltage,
        current: _latestReading!.current,
        temperature: _latestReading!.temperature,
        power: _latestReading!.power,
        batteryPercent: _latestReading!.batteryPercent,
        batteryHealth: _latestReading!.batteryHealth,
        timeLeft: _latestReading!.timeLeft,
        measuredAt: now,
        createdAt: now,
      );

      await measurementRepo.saveMeasurement(measurement);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Measurement saved successfully'),
            backgroundColor: AppTheme.statusGood,
          ),
        );

        // Navigate to battery detail to see the saved measurement
        context.go('/battery/${_battery!.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    if (_connectionMode == ConnectionMode.wifi) {
      _wifiService.stopPolling();
    } else {
      _btService.disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_battery?.batteryId ?? 'Measurement'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Battery Info ──
          if (_battery != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.battery_std, color: AppTheme.primary),
                title: Text(_battery!.batteryId),
                subtitle: Text(_battery!.locationString),
              ),
            ),
          const SizedBox(height: 12),

          // ── Connection Control ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected
                            ? Icons.wifi
                            : Icons.wifi_off,
                        color: _isConnected
                            ? AppTheme.statusGood
                            : AppTheme.statusCritical,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _connectionStatus,
                          style: TextStyle(
                            color: _isConnected
                                ? AppTheme.statusGood
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_isConnected)
                        ElevatedButton(
                          onPressed: _connectDevice,
                          child: const Text('Connect'),
                        )
                      else
                        OutlinedButton(
                          onPressed: _disconnectDevice,
                          child: const Text('Disconnect'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Live Readings ──
          _buildReadingDisplay(),

          const SizedBox(height: 24),

          // ── Save Button ──
          if (_latestReading != null && _latestReading!.connected)
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveMeasurement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.statusGood,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Save Measurement'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReadingDisplay() {
    final reading = _latestReading;

    if (reading == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.speed, size: 64, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Connect to ESP32 to see live readings',
                  style: TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!reading.connected) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                const Icon(
                  Icons.battery_unknown,
                  size: 48,
                  color: AppTheme.statusWarning,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Battery Connected to Device',
                  style: TextStyle(
                    color: AppTheme.statusWarning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect a battery to the ESP32 sensor',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Big reading cards
        Row(
          children: [
            Expanded(
              child: _BigReadingCard(
                label: 'Voltage',
                value: reading.voltage.toStringAsFixed(2),
                unit: 'V',
                color: AppTheme.getVoltageColor(reading.voltage),
                icon: Icons.bolt,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigReadingCard(
                label: 'Current',
                value: reading.current.toStringAsFixed(2),
                unit: 'A',
                color: AppTheme.currentColor,
                icon: Icons.electric_bolt,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _BigReadingCard(
                label: 'Temperature',
                value: reading.temperature.toStringAsFixed(1),
                unit: '°C',
                color: AppTheme.getTemperatureColor(reading.temperature),
                icon: Icons.thermostat,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigReadingCard(
                label: 'Power',
                value: reading.power.toStringAsFixed(1),
                unit: 'W',
                color: AppTheme.powerColor,
                icon: Icons.power,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _BigReadingCard(
                label: 'Charge',
                value: '${reading.batteryPercent}',
                unit: '%',
                color: AppTheme.getSocColor(reading.batteryPercent),
                icon: Icons.battery_charging_full,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigReadingCard(
                label: 'Health',
                value: '${reading.batteryHealth}',
                unit: '%',
                color: AppTheme.getHealthColor(reading.batteryHealth),
                icon: Icons.health_and_safety,
              ),
            ),
          ],
        ),

        // Alert banner
        if (reading.alert != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: reading.alert == 'critical'
                  ? AppTheme.statusCritical.withValues(alpha: 0.15)
                  : AppTheme.statusWarning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: reading.alert == 'critical'
                    ? AppTheme.statusCritical
                    : AppTheme.statusWarning,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: reading.alert == 'critical'
                      ? AppTheme.statusCritical
                      : AppTheme.statusWarning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reading.alertMessage ?? 'Alert',
                    style: TextStyle(
                      color: reading.alert == 'critical'
                          ? AppTheme.statusCritical
                          : AppTheme.statusWarning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BigReadingCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  const _BigReadingCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
