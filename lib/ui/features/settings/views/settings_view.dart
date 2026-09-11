import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/database/app_database.dart';
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

  String _getUnit(String key) {
    if (key.contains('volt') || key.contains('voltage')) return 'V';
    if (key.contains('temp')) return '°C';
    if (key.contains('current')) return 'A';
    if (key.contains('sensitivity')) return 'mV/A';
    if (key.contains('offset')) return 'mV';
    if (key.contains('capacity')) return 'Ah';
    return '';
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
            icon: Icons.wifi,
            title: 'Connection Mode',
            subtitle: _settings['connection_mode'] == 'wifi'
                ? 'WiFi (HTTP)'
                : 'Bluetooth Classic',
            onTap: () async {
              final current = _settings['connection_mode'] ?? 'bluetooth';
              await _updateSetting(
                'connection_mode',
                current == 'wifi' ? 'bluetooth' : 'wifi',
              );
            },
          ),
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

          // ── Push Settings to ESP32 ──
          _SectionHeader(title: 'Device Configuration'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Push the above settings to the connected ESP32 device via Bluetooth.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Settings push will be available after Bluetooth implementation',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Push to ESP32'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Calibrate Zero will send CALIBRATE_ZERO command to ESP32',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.balance),
                      label: const Text('Calibrate Zero Current'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
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
