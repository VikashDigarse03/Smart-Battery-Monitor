import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import '../../ui/core/constants.dart';

/// Parsed measurement data from ESP32 (both BT JSON and WiFi /data endpoint).
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

  /// Sentinel reading emitted when the connection is lost.
  factory Esp32Reading.disconnected() => const Esp32Reading(
        connected: false,
        voltage: 0,
        current: 0,
        temperature: 0,
        power: 0,
        batteryPercent: 0,
        timeLeft: 0,
        batteryHealth: 0,
        capacity: 0,
        timestamp: 0,
        wifiConnected: false,
      );

  /// Parse from BT JSON (short keys: v, i, t, p, pct, etc.)
  factory Esp32Reading.fromBluetoothJson(Map<String, dynamic> json) {
    final voltage = (json['v'] as num?)?.toDouble() ?? 0.0;
    final temp = (json['t'] as num?)?.toDouble() ?? 0.0;
    return Esp32Reading(
      connected: json['connected'] as bool? ?? false,
      voltage: voltage,
      current: (json['i'] as num?)?.toDouble() ?? 0.0,
      temperature: temp,
      power: (json['p'] as num?)?.toDouble() ?? 0.0,
      batteryPercent: AppConstants.computeSoc(voltage),
      timeLeft: (json['time_left'] as num?)?.toDouble() ?? 0.0,
      batteryHealth: AppConstants.calculateHealth(voltage: voltage, temperature: temp),
      capacity: (json['capacity'] as num?)?.toInt() ?? 100,
      timestamp: (json['ts'] as num?)?.toInt() ?? 0,
      wifiConnected: json['wifi'] as bool? ?? false,
      alert: json['alert'] as String?,
      alertMessage: json['alertMsg'] as String?,
    );
  }

  /// Parse from WiFi /data JSON (full keys).
  factory Esp32Reading.fromWifiJson(Map<String, dynamic> json) {
    final voltage = (json['voltage'] as num?)?.toDouble() ?? 0.0;
    final temp = (json['temperature'] as num?)?.toDouble() ?? 0.0;
    return Esp32Reading(
      connected: json['connected'] as bool? ?? false,
      voltage: voltage,
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      temperature: temp,
      power: (json['power'] as num?)?.toDouble() ?? 0.0,
      batteryPercent: AppConstants.computeSoc(voltage),
      timeLeft: (json['time_left'] as num?)?.toDouble() ?? 0.0,
      batteryHealth: AppConstants.calculateHealth(voltage: voltage, temperature: temp),
      capacity: (json['capacity'] as num?)?.toInt() ?? 100,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      wifiConnected: true,
      alert: json['alert'] as String?,
      alertMessage: json['alertMsg'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// WiFi Service
// ---------------------------------------------------------------------------

/// Polls ESP32 over HTTP. Emits disconnected readings after 3 consecutive
/// failures so the UI can show a "lost connection" state.
class Esp32WifiService {
  String _ipAddress;
  int _port;

  Timer? _pollingTimer;
  final StreamController<Esp32Reading> _readingController =
      StreamController<Esp32Reading>.broadcast();

  Stream<Esp32Reading> get readingStream => _readingController.stream;

  bool _isPolling = false;
  bool get isPolling => _isPolling;

  bool _lastPollSucceeded = false;
  bool get isConnected => _lastPollSucceeded;

  int _consecutiveFails = 0;
  static const int _maxFails = 3;

  Esp32WifiService({
    String ipAddress = '192.168.4.1',
    int port = 80,
  })  : _ipAddress = ipAddress,
        _port = port;

  void setIpAddress(String ip) => _ipAddress = ip;
  void setPort(int port) => _port = port;

  String get baseUrl => 'http://$_ipAddress:$_port';

  /// Fetch one reading. Returns null on failure.
  Future<Esp32Reading?> fetchReading() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/data'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Esp32Reading.fromWifiJson(json);
      }
    } catch (_) {
      // ignore — handled by fail counter below
    }
    return null;
  }

  /// Start polling at [interval]. After [_maxFails] consecutive failures,
  /// a disconnected reading is emitted and the interval slows to 5 s until
  /// the next success.
  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    stopPolling();
    _isPolling = true;
    _consecutiveFails = 0;
    _schedulePoll(interval);
  }

  void _schedulePoll(Duration interval) {
    _pollingTimer = Timer(interval, () async {
      if (!_isPolling) return;

      final reading = await fetchReading();

      if (reading != null) {
        _consecutiveFails = 0;
        _lastPollSucceeded = true;
        _readingController.add(reading);
        _schedulePoll(const Duration(seconds: 2));
      } else {
        _consecutiveFails++;
        _lastPollSucceeded = false;
        if (_consecutiveFails >= _maxFails) {
          // Notify UI that the connection is gone
          _readingController.add(Esp32Reading.disconnected());
        }
        // Back off: slow poll when struggling
        final backoff = _consecutiveFails >= _maxFails
            ? const Duration(seconds: 5)
            : const Duration(seconds: 2);
        _schedulePoll(backoff);
      }
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
    _lastPollSucceeded = false;
    _consecutiveFails = 0;
  }

  void dispose() {
    stopPolling();
    _readingController.close();
  }
}

// ---------------------------------------------------------------------------
// Bluetooth Service
// ---------------------------------------------------------------------------

/// Reads JSON lines from ESP32 over Bluetooth Classic.
/// Emits a disconnected reading when the BT session drops so the UI knows.
class Esp32BluetoothService {
  BluetoothConnection? _connection;
  final StreamController<Esp32Reading> _readingController =
      StreamController<Esp32Reading>.broadcast();

  Stream<Esp32Reading> get readingStream => _readingController.stream;

  bool get isConnected => _connection?.isConnected ?? false;

  String _buffer = '';
  static const int _bufferMaxLen = 2048;

  /// Connect to ESP32 by MAC address.
  Future<bool> connect(String address) async {
    try {
      _connection = await BluetoothConnection.toAddress(address);
      if (_connection!.isConnected) {
        _connection!.input!.listen(
          _onDataReceived,
          onDone: _onDisconnected,
          cancelOnError: true,
        );
        return true;
      }
    } catch (_) {
      // Connection error — caller handles the false return
    }
    return false;
  }

  void _onDataReceived(Uint8List data) {
    _buffer += ascii.decode(data);

    // Guard against unbounded buffer growth from malformed data
    if (_buffer.length > _bufferMaxLen) {
      _buffer = _buffer.substring(_buffer.length - (_bufferMaxLen ~/ 2));
    }

    while (_buffer.contains('\n')) {
      final newlineIndex = _buffer.indexOf('\n');
      final line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);

      if (line.startsWith('{') && line.endsWith('}')) {
        try {
          final jsonMap = jsonDecode(line) as Map<String, dynamic>;
          // Ignore command-response packets
          if (!jsonMap.containsKey('cmd')) {
            _readingController.add(Esp32Reading.fromBluetoothJson(jsonMap));
          }
        } catch (_) {
          // Malformed JSON — skip
        }
      }
    }
  }

  void _onDisconnected() {
    // Notify UI before cleaning up
    if (!_readingController.isClosed) {
      _readingController.add(Esp32Reading.disconnected());
    }
    disconnect();
  }

  /// Send a newline-terminated command to the ESP32.
  Future<void> sendCommand(String command) async {
    if (isConnected && _connection != null) {
      _connection!.output.add(ascii.encode('$command\n'));
      await _connection!.output.allSent;
    }
  }

  /// Trigger zero-current calibration on the ESP32.
  Future<void> calibrateZeroCurrent() async {
    if (isConnected) await sendCommand('CALIBRATE_ZERO');
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
