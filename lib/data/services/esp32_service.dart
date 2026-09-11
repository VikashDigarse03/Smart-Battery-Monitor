import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

/// Parsed measurement data from ESP32 (both BT JSON and WiFi /data endpoint).
///
/// Matches the JSON format sent by BatteryMonitor.ino's sendBluetoothData()
/// and handleData() functions.
class Esp32Reading {
  final bool connected;
  final double voltage;
  final double current;
  final double temperature;
  final double power;
  final int batteryPercent;
  final double timeLeft;
  final int batteryHealth;
  final int capacity;
  final int timestamp;
  final bool wifiConnected;
  final String? alert;
  final String? alertMessage;

  const Esp32Reading({
    required this.connected,
    required this.voltage,
    required this.current,
    required this.temperature,
    required this.power,
    required this.batteryPercent,
    required this.timeLeft,
    required this.batteryHealth,
    required this.capacity,
    required this.timestamp,
    required this.wifiConnected,
    this.alert,
    this.alertMessage,
  });

  /// Parse from BT JSON (short keys: v, i, t, p, pct, etc.)
  factory Esp32Reading.fromBluetoothJson(Map<String, dynamic> json) {
    return Esp32Reading(
      connected: json['connected'] as bool? ?? false,
      voltage: (json['v'] as num?)?.toDouble() ?? 0.0,
      current: (json['i'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['t'] as num?)?.toDouble() ?? 0.0,
      power: (json['p'] as num?)?.toDouble() ?? 0.0,
      batteryPercent: (json['pct'] as num?)?.toInt() ?? 0,
      timeLeft: (json['time_left'] as num?)?.toDouble() ?? 0.0,
      batteryHealth: (json['health'] as num?)?.toInt() ?? 100,
      capacity: (json['capacity'] as num?)?.toInt() ?? 100,
      timestamp: (json['ts'] as num?)?.toInt() ?? 0,
      wifiConnected: json['wifi'] as bool? ?? false,
      alert: json['alert'] as String?,
      alertMessage: json['alertMsg'] as String?,
    );
  }

  /// Parse from WiFi /data JSON (full keys: voltage, current, temperature, etc.)
  factory Esp32Reading.fromWifiJson(Map<String, dynamic> json) {
    return Esp32Reading(
      connected: json['connected'] as bool? ?? false,
      voltage: (json['voltage'] as num?)?.toDouble() ?? 0.0,
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      power: (json['power'] as num?)?.toDouble() ?? 0.0,
      batteryPercent: (json['battery_pct'] as num?)?.toInt() ?? 0,
      timeLeft: (json['time_left'] as num?)?.toDouble() ?? 0.0,
      batteryHealth: (json['health'] as num?)?.toInt() ?? 100,
      capacity: (json['capacity'] as num?)?.toInt() ?? 100,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      wifiConnected: true,
      alert: json['alert'] as String?,
      alertMessage: json['alertMsg'] as String?,
    );
  }
}

/// Response from ESP32 command.
class Esp32CommandResponse {
  final String command;
  final String? status;
  final Map<String, dynamic> data;

  const Esp32CommandResponse({
    required this.command,
    this.status,
    required this.data,
  });

  factory Esp32CommandResponse.fromJson(Map<String, dynamic> json) {
    return Esp32CommandResponse(
      command: json['cmd'] as String? ?? 'unknown',
      status: json['status'] as String?,
      data: json,
    );
  }
}

/// Service for communicating with ESP32 over WiFi (HTTP).
///
/// The ESP32 runs as a WiFi Access Point. The phone connects to the ESP32's
/// WiFi network, then polls the /data endpoint for readings and sends
/// commands via HTTP.
class Esp32WifiService {
  String _ipAddress;
  int _port;
  Timer? _pollingTimer;
  final StreamController<Esp32Reading> _readingController =
      StreamController<Esp32Reading>.broadcast();

  /// Stream of readings from the ESP32 via WiFi polling.
  Stream<Esp32Reading> get readingStream => _readingController.stream;

  bool _isPolling = false;
  bool get isPolling => _isPolling;

  Esp32WifiService({
    String ipAddress = '192.168.4.1',
    int port = 80,
  })  : _ipAddress = ipAddress,
        _port = port;

  /// Update the ESP32 IP address (from Settings).
  void setIpAddress(String ip) {
    _ipAddress = ip;
  }

  void setPort(int port) {
    _port = port;
  }

  String get baseUrl => 'http://$_ipAddress:$_port';

  /// Fetch a single reading from /data endpoint.
  Future<Esp32Reading?> fetchReading() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/data'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Esp32Reading.fromWifiJson(json);
      }
    } catch (e) {
      // Connection failed — ESP32 not reachable
    }
    return null;
  }

  /// Start polling the ESP32 for readings at regular intervals.
  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    stopPolling();
    _isPolling = true;
    _pollingTimer = Timer.periodic(interval, (_) async {
      final reading = await fetchReading();
      if (reading != null) {
        _readingController.add(reading);
      }
    });
  }

  /// Stop polling.
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
  }

  /// Send a configuration command to ESP32 via the BT serial bridge.
  /// For WiFi, we could add HTTP endpoints, but currently configuration
  /// is done via Bluetooth commands. This method is a placeholder
  /// for future HTTP-based configuration.
  Future<bool> pingDevice() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/data'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    stopPolling();
    _readingController.close();
  }
}

/// Service for communicating with ESP32 over Bluetooth Classic.
class Esp32BluetoothService {
  BluetoothConnection? _connection;
  final StreamController<Esp32Reading> _readingController =
      StreamController<Esp32Reading>.broadcast();

  /// Stream of readings from the ESP32 via Bluetooth.
  Stream<Esp32Reading> get readingStream => _readingController.stream;

  bool get isConnected => _connection?.isConnected ?? false;

  String _buffer = '';

  /// Connect to the ESP32 device using its MAC address.
  Future<bool> connect(String address) async {
    try {
      _connection = await BluetoothConnection.toAddress(address);
      if (_connection != null && _connection!.isConnected) {
        _connection!.input!.listen(_onDataReceived).onDone(() {
          // Handle disconnection internally if needed
          disconnect();
        });
        return true;
      }
    } catch (e) {
      // Connection error
    }
    return false;
  }

  void _onDataReceived(Uint8List data) {
    _buffer += ascii.decode(data);

    // Parse complete lines from the buffer
    while (_buffer.contains('\n')) {
      int newlineIndex = _buffer.indexOf('\n');
      String line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);

      if (line.startsWith('{') && line.endsWith('}')) {
        try {
          final jsonMap = jsonDecode(line) as Map<String, dynamic>;
          // Ignore command responses, we only want readings
          if (!jsonMap.containsKey('cmd')) {
            final reading = Esp32Reading.fromBluetoothJson(jsonMap);
            _readingController.add(reading);
          }
        } catch (e) {
          // Ignore malformed JSON
        }
      }
    }
  }

  /// Send a command to the ESP32 over Bluetooth.
  Future<void> sendCommand(String command) async {
    if (isConnected && _connection != null) {
      _connection!.output.add(ascii.encode('$command\n'));
      await _connection!.output.allSent;
    }
  }

  /// Push configuration settings to the ESP32.
  Future<bool> pushSettings(Map<String, String> settings) async {
    if (!isConnected) return false;

    final Map<String, dynamic> espSettings = {};
    
    void parseAndAdd(String destKey, String srcKey) {
      if (settings.containsKey(srcKey)) {
        final val = double.tryParse(settings[srcKey]!);
        if (val != null) espSettings[destKey] = val;
      }
    }
    
    void parseIntAndAdd(String destKey, String srcKey) {
      if (settings.containsKey(srcKey)) {
        final val = int.tryParse(settings[srcKey]!);
        if (val != null) espSettings[destKey] = val;
      }
    }

    parseAndAdd('v_crit_low', 'volt_critical_low');
    parseAndAdd('v_warn_low', 'volt_warning_low');
    parseAndAdd('v_norm_low', 'volt_normal_low');
    parseAndAdd('v_full', 'volt_full');
    parseAndAdd('v_over', 'volt_overcharge');
    
    parseAndAdd('t_warn', 'temp_warning');
    parseAndAdd('t_crit', 'temp_critical');
    
    parseAndAdd('c_warn', 'current_warning');
    parseAndAdd('c_crit', 'current_critical');
    
    parseAndAdd('v_div', 'voltage_divider_ratio');
    parseAndAdd('v_cal', 'voltage_calibration');
    
    parseAndAdd('i_sens', 'acs712_sensitivity');
    parseAndAdd('i_div', 'current_divider_ratio');
    
    parseIntAndAdd('adc_samp', 'adc_samples');
    parseIntAndAdd('capacity', 'battery_capacity_ah');

    try {
      final jsonStr = jsonEncode(espSettings);
      await sendCommand('CONFIG_SET:$jsonStr');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Trigger zero-current calibration on the ESP32.
  Future<void> calibrateZeroCurrent() async {
    if (isConnected) {
      await sendCommand('CALIBRATE_ZERO');
    }
  }

  /// Disconnect the active Bluetooth session.
  void disconnect() {
    _connection?.close();
    _connection = null;
    _buffer = '';
  }

  void dispose() {
    disconnect();
    _readingController.close();
  }
}

