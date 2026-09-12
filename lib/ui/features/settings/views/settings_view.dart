import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import '../../../../data/database/app_database.dart';
import '../../../../data/services/esp32_service.dart';
import '../../../core/theme.dart';

/// Settings screen for configuring thresholds, ESP32 calibration, and connection.
///
/// All values stored in app_settings table and can be pushed to ESP32
/// via Bluetooth commands.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Map<String, String> _settings = {};
  bool _isLoading = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = context.read<AppDatabase>();
    _settings = await db.getAllSettings();
    setState(() => _isLoading = false);
  }

  Future<void> _updateSetting(String key, String value) async {
    final db = context.read<AppDatabase>();
    await db.setSetting(key, value);
    _settings[key] = value;
    setState(() {});
  }

  Future<void> _showEditDialog(
    String title,
    String key, {
    TextInputType keyboardType = TextInputType.number,
  }) async {
    final controller = TextEditingController(text: _settings[key] ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: 'Enter value',
            suffixText: _getUnit(key),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _updateSetting(key, result);
    }
  }

  // ─── Bluetooth Connection Management ──────────────────────

  Future<void> _showBluetoothDevicePicker() async {
    final btService = context.read<Esp32BluetoothService>();

    if (btService.isConnected) {
      // Already connected — ask to disconnect
      final disconnect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth Connected'),
          content: const Text('You are connected to ESP32.\nDo you want to disconnect?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusCritical),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (disconnect == true) {
        btService.disconnect();
        setState(() {});
      }
      return;
    }

    // Show device picker
    setState(() => _isConnecting = true);
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return;

      setState(() => _isConnecting = false);

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No paired Bluetooth devices found. Pair your ESP32 in system Bluetooth settings first.'),
            backgroundColor: AppTheme.statusWarning,
          ),
        );
        return;
      }

      final selected = await showDialog<BluetoothDevice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select ESP32 Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth, color: AppTheme.primary),
                  title: Text(device.name ?? 'Unknown'),
                  subtitle: Text(device.address),
                  onTap: () => Navigator.pop(ctx, device),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        setState(() => _isConnecting = true);
        final success = await btService.connect(selected.address);
        if (mounted) {
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success
                  ? 'Connected to ${selected.name ?? selected.address}'
                  : 'Failed to connect to ${selected.name ?? selected.address}'),
              backgroundColor: success ? AppTheme.statusGood : AppTheme.statusCritical,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bluetooth error: $e'),
            backgroundColor: AppTheme.statusCritical,
          ),
        );
      }
    }
  }

  // ─── Send Partial Config Sections ──────────────────────────

  Future<void> _sendSectionToEsp32(String sectionName, Map<String, dynamic> payload) async {
    final btService = context.read<Esp32BluetoothService>();
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected to ESP32. Tap the Bluetooth icon in the app bar to connect.'),
          backgroundColor: AppTheme.statusWarning,
        ),
      );
      return;
    }

    try {
      payload['cmd'] = 'config';
      final jsonStr = jsonEncode(payload);
      await btService.sendCommand(jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$sectionName sent to ESP32 ✓'),
            backgroundColor: AppTheme.statusGood,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send $sectionName: $e'),
            backgroundColor: AppTheme.statusCritical,
          ),
        );
      }
    }
  }

  void _sendEsp32Connection() {
    _sendSectionToEsp32('WiFi Config', {
      'ssid': _settings['esp32_wifi_ssid'] ?? '',
      'pass': _settings['esp32_wifi_password'] ?? '',
    });
  }

  void _sendVoltageThresholds() {
    _sendSectionToEsp32('Voltage Thresholds', {
      'v_crit_L': double.tryParse(_settings['volt_critical_low'] ?? '10.5') ?? 10.5,
      'v_warn_L': double.tryParse(_settings['volt_warning_low'] ?? '11.5') ?? 11.5,
      'v_norm_L': double.tryParse(_settings['volt_normal_low'] ?? '12.0') ?? 12.0,
      'v_full': double.tryParse(_settings['volt_full'] ?? '12.7') ?? 12.7,
      'v_over': double.tryParse(_settings['volt_overcharge'] ?? '14.8') ?? 14.8,
    });
  }

  void _sendTemperatureThresholds() {
    _sendSectionToEsp32('Temperature Thresholds', {
      't_zero': double.tryParse(_settings['temp_zero_offset'] ?? '0.0') ?? 0.0,
      't_warn': double.tryParse(_settings['temp_warning'] ?? '45.0') ?? 45.0,
      't_crit': double.tryParse(_settings['temp_critical'] ?? '55.0') ?? 55.0,
    });
  }

  void _sendCurrentThresholds() {
    _sendSectionToEsp32('Current Thresholds', {
      'i_warn': double.tryParse(_settings['current_warning'] ?? '20.0') ?? 20.0,
      'i_crit': double.tryParse(_settings['current_critical'] ?? '28.0') ?? 28.0,
    });
  }

  void _sendVoltageZeroOffset() {
    _sendSectionToEsp32('Voltage Zero Offset', {
      'v_zero': double.tryParse(_settings['voltage_zero_offset'] ?? '0.0') ?? 0.0,
      'v_conn': double.tryParse(_settings['voltage_conn_threshold'] ?? '0.15') ?? 0.15,
    });
  }

  void _sendSensorCalibration() {
    _sendSectionToEsp32('Sensor Calibration', {
      'v_div': double.tryParse(_settings['voltage_divider_ratio'] ?? '5.0') ?? 5.0,
      'v_cal': double.tryParse(_settings['voltage_calibration'] ?? '1.0') ?? 1.0,
      'i_div': double.tryParse(_settings['current_divider_ratio'] ?? '0.5') ?? 0.5,
      'i_sens': double.tryParse(_settings['acs712_sensitivity'] ?? '66.0') ?? 66.0,
      'i_zero': double.tryParse(_settings['acs712_zero_offset'] ?? '1300.0') ?? 1300.0,
      'adc_samp': int.tryParse(_settings['adc_samples'] ?? '64') ?? 64,
      'cap': int.tryParse(_settings['battery_capacity_ah'] ?? '100') ?? 100,
    });
  }

  // ─── Send All ──────────────────────────────────────────────

  Future<void> _pushAllToEsp32() async {
    final btService = context.read<Esp32BluetoothService>();
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected to ESP32. Tap the Bluetooth icon in the app bar to connect.'),
          backgroundColor: AppTheme.statusWarning,
        ),
      );
      return;
    }

    try {
      // Build full config payload
      final payload = {
        "cmd": "config",
        "ssid": _settings['esp32_wifi_ssid'] ?? "",
        "pass": _settings['esp32_wifi_password'] ?? "",
        "v_div": double.tryParse(_settings['voltage_divider_ratio'] ?? '5.0') ?? 5.0,
        "v_cal": double.tryParse(_settings['voltage_calibration'] ?? '1.0') ?? 1.0,
        "v_zero": double.tryParse(_settings['voltage_zero_offset'] ?? '0.0') ?? 0.0,
        "v_conn": double.tryParse(_settings['voltage_conn_threshold'] ?? '0.15') ?? 0.15,
        "i_div": double.tryParse(_settings['current_divider_ratio'] ?? '0.5') ?? 0.5,
        "i_sens": double.tryParse(_settings['acs712_sensitivity'] ?? '66.0') ?? 66.0,
        "i_zero": double.tryParse(_settings['acs712_zero_offset'] ?? '1300.0') ?? 1300.0,
        "adc_samp": int.tryParse(_settings['adc_samples'] ?? '64') ?? 64,
        "cap": int.tryParse(_settings['battery_capacity_ah'] ?? '100') ?? 100,
        "v_crit_L": double.tryParse(_settings['volt_critical_low'] ?? '10.5') ?? 10.5,
        "v_warn_L": double.tryParse(_settings['volt_warning_low'] ?? '11.5') ?? 11.5,
        "v_norm_L": double.tryParse(_settings['volt_normal_low'] ?? '12.0') ?? 12.0,
        "v_full": double.tryParse(_settings['volt_full'] ?? '12.7') ?? 12.7,
        "v_over": double.tryParse(_settings['volt_overcharge'] ?? '14.8') ?? 14.8,
        "t_zero": double.tryParse(_settings['temp_zero_offset'] ?? '0.0') ?? 0.0,
        "t_warn": double.tryParse(_settings['temp_warning'] ?? '45.0') ?? 45.0,
        "t_crit": double.tryParse(_settings['temp_critical'] ?? '55.0') ?? 55.0,
        "i_warn": double.tryParse(_settings['current_warning'] ?? '20.0') ?? 20.0,
        "i_crit": double.tryParse(_settings['current_critical'] ?? '28.0') ?? 28.0,
      };

      final jsonStr = jsonEncode(payload);
      await btService.sendCommand(jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All settings pushed to ESP32 ✓'),
            backgroundColor: AppTheme.statusGood,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to push config: $e'),
            backgroundColor: AppTheme.statusCritical,
          ),
        );
      }
    }
  }

  String _getUnit(String key) {
    if (key.contains('volt') || key.contains('voltage')) return 'V';
    if (key.contains('threshold')) return 'V';
    if (key.contains('temp')) return '°C';
    if (key.contains('current')) return 'A';
    if (key.contains('sensitivity')) return 'mV/A';
    if (key.contains('offset') && key.contains('acs')) return 'mV';
    if (key.contains('offset')) return 'V';
    if (key.contains('capacity')) return 'Ah';
    return '';
  }

  Future<void> _autoCalibVoltageZero() async {
    final btService = context.read<Esp32BluetoothService>();
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected to ESP32. Tap the Bluetooth icon in the app bar to connect.'),
          backgroundColor: AppTheme.statusWarning,
        ),
      );
      return;
    }

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-Calibrate Voltage Zero'),
        content: const Text(
          'Make sure NO BATTERY is connected to the sensor.\n\n'
          'The ESP32 will sample the idle voltage and set it as the zero offset '
          'so that the reading shows 0V when nothing is connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Calibrate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await btService.sendCommand('CALIBRATE_VOLTAGE_ZERO');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voltage zero calibration sent! Check ESP32 response.'),
            backgroundColor: AppTheme.statusGood,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calibration failed: $e'),
            backgroundColor: AppTheme.statusCritical,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final btService = context.read<Esp32BluetoothService>();
    final isConnected = btService.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // ── BT Connection Button ──
          _isConnecting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? AppTheme.statusGood : AppTheme.textMuted,
                  ),
                  tooltip: isConnected ? 'Connected — Tap to manage' : 'Connect to ESP32',
                  onPressed: _showBluetoothDevicePicker,
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connection Status Banner ──
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.statusWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.statusWarning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_disabled, color: AppTheme.statusWarning, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Not connected to ESP32. Tap the Bluetooth icon above to connect.',
                      style: TextStyle(fontSize: 13, color: AppTheme.statusWarning),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.statusGood.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.statusGood.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_connected, color: AppTheme.statusGood, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Connected to ESP32 via Bluetooth',
                      style: TextStyle(fontSize: 13, color: AppTheme.statusGood),
                    ),
                  ),
                ],
              ),
            ),

          // ── ESP32 Connection ──
          _SectionHeader(title: 'ESP32 WiFi Config', onSend: _sendEsp32Connection, isConnected: isConnected),
          _SettingsTile(
            icon: Icons.language,
            title: 'ESP32 IP Address',
            subtitle: _settings['esp32_ip_address'] ?? '192.168.4.1',
            onTap: () => _showEditDialog(
              'ESP32 IP Address',
              'esp32_ip_address',
              keyboardType: TextInputType.url,
            ),
          ),
          _SettingsTile(
            icon: Icons.wifi_tethering,
            title: 'ESP32 WiFi SSID',
            subtitle: _settings['esp32_wifi_ssid'] ?? 'ESP32_Battery',
            onTap: () => _showEditDialog(
              'ESP32 WiFi SSID',
              'esp32_wifi_ssid',
              keyboardType: TextInputType.text,
            ),
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'ESP32 WiFi Password',
            subtitle: '••••••••',
            onTap: () => _showEditDialog(
              'ESP32 WiFi Password',
              'esp32_wifi_password',
              keyboardType: TextInputType.text,
            ),
          ),
          const Divider(height: 32),

          // ── Voltage Thresholds ──
          _SectionHeader(title: 'Voltage Thresholds (12V Lead-Acid)', onSend: _sendVoltageThresholds, isConnected: isConnected),
          _SettingsTile(
            icon: Icons.warning,
            title: 'Critical Low',
            subtitle: '${_settings['volt_critical_low'] ?? '10.5'} V',
            onTap: () =>
                _showEditDialog('Critical Low Voltage', 'volt_critical_low'),
          ),
          _SettingsTile(
            icon: Icons.warning_amber,
            title: 'Warning Low',
            subtitle: '${_settings['volt_warning_low'] ?? '11.5'} V',
            onTap: () =>
                _showEditDialog('Warning Low Voltage', 'volt_warning_low'),
          ),
          _SettingsTile(
            icon: Icons.check_circle_outline,
            title: 'Normal Low',
            subtitle: '${_settings['volt_normal_low'] ?? '12.0'} V',
            onTap: () =>
                _showEditDialog('Normal Low Voltage', 'volt_normal_low'),
          ),
          _SettingsTile(
            icon: Icons.battery_full,
            title: 'Fully Charged',
            subtitle: '${_settings['volt_full'] ?? '12.7'} V',
            onTap: () => _showEditDialog('Fully Charged Voltage', 'volt_full'),
          ),
          _SettingsTile(
            icon: Icons.flash_on,
            title: 'Overcharge',
            subtitle: '${_settings['volt_overcharge'] ?? '14.8'} V',
            onTap: () =>
                _showEditDialog('Overcharge Voltage', 'volt_overcharge'),
          ),
          const Divider(height: 32),

          // ── Temperature Thresholds ──
          _SectionHeader(title: 'Temperature Thresholds', onSend: _sendTemperatureThresholds, isConnected: isConnected),
          _SettingsTile(
            icon: Icons.thermostat_auto,
            title: 'Temperature Offset',
            subtitle: '${_settings['temp_zero_offset'] ?? '0.0'} °C',
            onTap: () => _showEditDialog(
              'Temperature Offset (°C to subtract)',
              'temp_zero_offset',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'If sensor reads 3°C higher than actual, set offset to 3.0',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          _SettingsTile(
            icon: Icons.thermostat,
            title: 'Warning',
            subtitle: '${_settings['temp_warning'] ?? '45.0'} °C',
            onTap: () =>
                _showEditDialog('Temperature Warning', 'temp_warning'),
          ),
          _SettingsTile(
            icon: Icons.local_fire_department,
            title: 'Critical',
            subtitle: '${_settings['temp_critical'] ?? '55.0'} °C',
            onTap: () =>
                _showEditDialog('Temperature Critical', 'temp_critical'),
          ),
          const Divider(height: 32),

          // ── Current Thresholds ──
          _SectionHeader(title: 'Current Thresholds', onSend: _sendCurrentThresholds, isConnected: isConnected),
          _SettingsTile(
            icon: Icons.electric_bolt,
            title: 'Warning',
            subtitle: '${_settings['current_warning'] ?? '20.0'} A',
            onTap: () =>
                _showEditDialog('Current Warning', 'current_warning'),
          ),
          _SettingsTile(
            icon: Icons.flash_on,
            title: 'Critical',
            subtitle: '${_settings['current_critical'] ?? '28.0'} A',
            onTap: () =>
                _showEditDialog('Current Critical', 'current_critical'),
          ),
          const Divider(height: 32),

          // ── Voltage Zero Offset / Calibration ──
          _SectionHeader(title: 'Voltage Zero Offset', onSend: _sendVoltageZeroOffset, isConnected: isConnected),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Subtract idle ADC noise so voltage reads 0V when no battery is connected. '
              'Current offset: ${_settings['voltage_zero_offset'] ?? '0.0'} V',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ),
          _SettingsTile(
            icon: Icons.straighten,
            title: 'Voltage Zero Offset',
            subtitle: '${_settings['voltage_zero_offset'] ?? '0.0'} V',
            onTap: () => _showEditDialog(
              'Voltage Zero Offset (V)',
              'voltage_zero_offset',
            ),
          ),
          _SettingsTile(
            icon: Icons.filter_center_focus,
            title: 'Connection Threshold',
            subtitle: '${_settings['voltage_conn_threshold'] ?? '0.15'} V',
            onTap: () => _showEditDialog(
              'Min Voltage to Detect Battery (V)',
              'voltage_conn_threshold',
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            color: AppTheme.primary.withValues(alpha: 0.15),
            child: ListTile(
              leading: const Icon(Icons.auto_fix_high, color: AppTheme.primary, size: 20),
              title: const Text(
                'Auto-Calibrate Voltage Zero',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Disconnect battery first, then tap to zero out idle noise',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.play_arrow, color: AppTheme.primary),
              onTap: _autoCalibVoltageZero,
            ),
          ),
          const Divider(height: 32),

          // ── Sensor Calibration ──
          _SectionHeader(title: 'Sensor Calibration', onSend: _sendSensorCalibration, isConnected: isConnected),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Voltage Divider Ratio',
            subtitle: _settings['voltage_divider_ratio'] ?? '5.0',
            onTap: () => _showEditDialog(
              'Voltage Divider Ratio',
              'voltage_divider_ratio',
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Voltage Calibration Factor',
            subtitle: _settings['voltage_calibration'] ?? '1.0',
            onTap: () => _showEditDialog(
              'Voltage Calibration Factor',
              'voltage_calibration',
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'ACS712 Sensitivity',
            subtitle: '${_settings['acs712_sensitivity'] ?? '66.0'} mV/A',
            onTap: () => _showEditDialog(
              'ACS712 Sensitivity',
              'acs712_sensitivity',
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Current Divider Ratio',
            subtitle: _settings['current_divider_ratio'] ?? '0.5',
            onTap: () => _showEditDialog(
              'Current Divider Ratio',
              'current_divider_ratio',
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'ACS712 Zero Offset',
            subtitle: '${_settings['acs712_zero_offset'] ?? '1300.0'} mV',
            onTap: () => _showEditDialog(
              'ACS712 Zero Offset',
              'acs712_zero_offset',
            ),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'ADC Samples',
            subtitle: _settings['adc_samples'] ?? '64',
            onTap: () =>
                _showEditDialog('ADC Samples', 'adc_samples'),
          ),
          _SettingsTile(
            icon: Icons.tune,
            title: 'Battery Capacity',
            subtitle: '${_settings['battery_capacity_ah'] ?? '100'} Ah',
            onTap: () => _showEditDialog(
              'Battery Capacity',
              'battery_capacity_ah',
            ),
          ),
          const Divider(height: 32),

          // Extra bottom padding for FAB
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pushAllToEsp32,
        icon: const Icon(Icons.send_rounded),
        label: const Text('Send All to ESP32'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSend;
  final bool isConnected;

  const _SectionHeader({
    required this.title,
    this.onSend,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          if (onSend != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onSend,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? AppTheme.primary.withValues(alpha: 0.12)
                        : AppTheme.textMuted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isConnected
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : AppTheme.textMuted.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.send_rounded,
                        size: 14,
                        color: isConnected ? AppTheme.primary : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Send',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isConnected ? AppTheme.primary : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
