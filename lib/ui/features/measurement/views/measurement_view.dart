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
  bool _isSaving = false;
  bool _connectionLost = false;
  bool _showSoc = true;
  bool _showSoh = true;
  List<Measurement> _batteryHistory = [];
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

    // Load connection mode and metric display settings
    final db = context.read<AppDatabase>();
    final modeString = await db.getSetting('connection_mode');
    _connectionMode = modeString == 'bluetooth' 
        ? ConnectionMode.bluetooth 
        : ConnectionMode.wifi;

    final showSocSetting = await db.getSetting('show_soc');
    final showSohSetting = await db.getSetting('show_soh');
    _showSoc = showSocSetting != 'false';
    _showSoh = showSohSetting != 'false';

    final measurementRepo = context.read<MeasurementRepository>();
    _batteryHistory = await measurementRepo.getMeasurementsForBattery(
      widget.batteryDbId,
      limit: 30,
    );

    if (_connectionMode == ConnectionMode.wifi) {
      _wifiService.startPolling();
      _readingSub = _wifiService.readingStream.listen((reading) {
        setState(() {
          _latestReading = reading;
          _connectionLost = !reading.connected && reading.voltage == 0;
        });
      });
    } else {
      _readingSub = _btService.readingStream.listen((reading) {
        setState(() {
          _latestReading = reading;
          _connectionLost = !reading.connected && reading.voltage == 0;
        });
      });
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveMeasurement() async {
    if (_latestReading == null || _battery == null) return;

    setState(() => _isSaving = true);

    try {
      final measurementRepo = context.read<MeasurementRepository>();
      final now = DateTime.now();

      final soc = _showSoc ? AppConstants.computeSoc(_latestReading!.voltage) : null;
      final soh = _showSoh
          ? AppConstants.calculateHealth(
              voltage: _latestReading!.voltage,
              temperature: _latestReading!.temperature,
              history: _batteryHistory,
              installationDate: _battery?.installationDate,
            )
          : null;

      final measurement = Measurement(
        batteryId: _battery!.id!,
        voltage: _latestReading!.voltage,
        current: _latestReading!.current,
        temperature: _latestReading!.temperature,
        power: _latestReading!.power,
        batteryPercent: soc,
        batteryHealth: soh,
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

        // Pop with `true` so the caller knows to refresh its data
        context.pop(true);
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
            // ── Connection Lost Banner ──
            if (_connectionLost)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.statusWarning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.statusWarning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.signal_wifi_off, color: AppTheme.statusWarning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Connection lost — waiting to reconnect...',
                        style: TextStyle(color: AppTheme.statusWarning, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

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
                  'Waiting for readings...',
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

    final soc = AppConstants.computeSoc(reading.voltage);
    final soh = AppConstants.calculateHealth(
      voltage: reading.voltage,
      temperature: reading.temperature,
      history: _batteryHistory,
      installationDate: _battery?.installationDate,
    );

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
        if (_showSoc || _showSoh) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (_showSoc)
                Expanded(
                  child: _BigReadingCard(
                    label: 'Charge (SOC)',
                    value: '$soc',
                    unit: '%',
                    color: AppTheme.getSocColor(soc),
                    icon: Icons.battery_charging_full,
                  ),
                ),
              if (_showSoc && _showSoh) const SizedBox(width: 12),
              if (_showSoh)
                Expanded(
                  child: _BigReadingCard(
                    label: 'Health (SOH)',
                    value: '$soh',
                    unit: '%',
                    color: AppTheme.getHealthColor(soh),
                    icon: Icons.health_and_safety,
                  ),
                ),
            ],
          ),
        ],

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
