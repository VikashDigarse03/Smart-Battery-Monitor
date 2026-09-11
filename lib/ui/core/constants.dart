/// Application-wide constants, thresholds, and default settings.
///
/// Alert thresholds match the ESP32 firmware defaults but are user-configurable
/// via the Settings screen. Changes pushed to ESP32 via Bluetooth/WiFi commands.
class AppConstants {
  AppConstants._();

  // ─── Battery ID format ──────────────────────────────────────
  static const String batteryIdPrefix = 'BAT-';
  static const int batteryIdDigits = 6;

  // ─── Device ID format ───────────────────────────────────────
  static const String deviceIdPrefix = 'ESP32-';

  // ─── ESP32 defaults ─────────────────────────────────────────
  static const String defaultEsp32BtName = 'ESP32_BattMon';
  static const String defaultEsp32WifiSsid = 'ESP32_Battery';
  static const String defaultEsp32WifiPassword = '12345678';
  static const String defaultEsp32IpAddress = '192.168.4.1';
  static const int esp32HttpPort = 80;
  static const String esp32DataEndpoint = '/data';

  // ─── Bluetooth ──────────────────────────────────────────────
  static const int btSendIntervalMs = 2000;

  // ─── 12V Lead-Acid Battery Thresholds (defaults) ────────────
  // These correspond to the ESP32 firmware constants and can be
  // overridden in Settings and pushed to the device.
  static const double defaultVoltCriticalLow = 10.5;
  static const double defaultVoltWarningLow = 11.5;
  static const double defaultVoltNormalLow = 12.0;
  static const double defaultVoltFull = 12.7;
  static const double defaultVoltOvercharge = 14.8;

  static const double defaultTempWarning = 45.0;
  static const double defaultTempCritical = 55.0;

  static const double defaultCurrentWarning = 20.0;
  static const double defaultCurrentCritical = 28.0;

  // ─── ESP32 Sensor Calibration (defaults) ────────────────────
  static const double defaultVoltageDividerRatio = 5.0;
  static const double defaultVoltageCalibration = 1.0;
  static const double defaultAcs712Sensitivity = 66.0; // mV/A
  static const double defaultCurrentDividerRatio = 0.5;
  static const double defaultAcs712ZeroOffset = 1300.0; // mV
  static const int defaultAdcSamples = 64;
  static const double defaultVoltageConnectedThreshold = 1.0;
  static const int defaultBatteryCapacityAh = 100;

  // ─── SOC Voltage Table (12V Lead-Acid, resting) ─────────────
  // Maps resting open-circuit voltage to approximate State of Charge.
  // Source: Standard 12V flooded lead-acid battery tables.
  static const List<(double voltage, int percent)> socVoltageTable = [
    (12.70, 100),
    (12.50, 90),
    (12.42, 80),
    (12.32, 70),
    (12.20, 60),
    (12.06, 50),
    (11.90, 40),
    (11.75, 30),
    (11.58, 20),
    (11.31, 10),
    (10.50, 0),
  ];

  // ─── Battery Health Thresholds ──────────────────────────────
  // SOH (State of Health) based on internal resistance estimation.
  // Healthy 12V 100Ah: IR < 15mΩ, degraded > 30mΩ, failing > 50mΩ.
  static const double healthGoodThreshold = 80.0;
  static const double healthFairThreshold = 50.0;

  // ─── Lead-Acid Battery Performance Indicators ───────────────
  // Used for overtime performance analysis.
  //
  // Key behaviors of lead-acid batteries:
  //
  // 1. VOLTAGE SAG: As a battery ages, its resting voltage after full
  //    charge gradually decreases. A new battery might rest at 12.72V,
  //    while a 3-year-old battery might only reach 12.55V.
  //
  // 2. CAPACITY FADE: The usable capacity (Ah) decreases over time.
  //    Typically loses 1-3% per year under normal conditions.
  //    End of life is usually defined as 80% of rated capacity.
  //
  // 3. INTERNAL RESISTANCE: Rises as the plates sulfate and corrode.
  //    Measured by voltage droop under load:
  //    IR = (V_rest - V_load) / I_load
  //    New battery: 5-15 mΩ, End of life: 30-50+ mΩ
  //
  // 4. SULFATION: If a battery sits partially discharged for extended
  //    periods, lead sulfate crystals harden and become permanent,
  //    reducing capacity. Detected by lower-than-expected voltage
  //    after charging.
  //
  // 5. TEMPERATURE EFFECTS: Every 8°C above 25°C halves the battery
  //    life. High temperature accelerates corrosion and water loss.
  //    Monitoring average temperature over time is critical.
  //
  // 6. FLOAT VOLTAGE: In standby/float applications, a properly
  //    maintained 12V battery should float at 13.5-13.8V.
  //    Deviation indicates charger issues or battery degradation.
  static const double expectedRestingVoltageNew = 12.72;
  static const double endOfLifeCapacityPercent = 80.0;
  static const double idealOperatingTempC = 25.0;
  static const double tempLifeHalvingDegrees = 8.0;
}

/// Alert severity levels matching the ESP32 firmware.
enum AlertLevel {
  none,
  warning,
  critical;

  static AlertLevel fromString(String? value) {
    switch (value) {
      case 'warning':
        return AlertLevel.warning;
      case 'critical':
        return AlertLevel.critical;
      default:
        return AlertLevel.none;
    }
  }
}

/// Connection mode for communicating with ESP32 devices.
enum ConnectionMode {
  bluetooth,
  wifi;

  String get displayName {
    switch (this) {
      case ConnectionMode.bluetooth:
        return 'Bluetooth';
      case ConnectionMode.wifi:
        return 'WiFi';
    }
  }
}
