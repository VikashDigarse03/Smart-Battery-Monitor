import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  Future<void> _pushToEsp32() async {
    final btService = context.read<Esp32BluetoothService>();
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to ESP32 via Bluetooth on the Dashboard first.'),
          backgroundColor: AppTheme.statusWarning,
        ),
      );
      return;
    }

    try {
      // Build config payload
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
            content: Text('Configuration pushed to ESP32 successfully.'),
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
          content: Text('Please connect to ESP32 via Bluetooth first.'),
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
            content: Text('Calibration failed: \$e'),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── ESP32 Connection ──
          _SectionHeader(title: 'ESP32 Connection'),
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
          _SectionHeader(title: 'Voltage Thresholds (12V Lead-Acid)'),
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
          _SectionHeader(title: 'Temperature Thresholds'),
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
          _SectionHeader(title: 'Current Thresholds'),
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
          _SectionHeader(title: 'Voltage Zero Offset'),
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
            color: AppTheme.primary.withOpacity(0.15),
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
          _SectionHeader(title: 'Sensor Calibration'),
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


        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pushToEsp32,
        icon: const Icon(Icons.bluetooth_connected),
        label: const Text('Push to ESP32'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
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
