import '../../domain/models/models.dart';

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

  // ─── SOH Peak-Voltage Table (12V Lead-Acid) ──────────────────
  static const List<(double peakVoltage, int health)> sohPeakVoltageTable = [
    (12.70, 100),
    (12.50,  85),
    (12.30,  70),
    (12.00,  50),
    (11.50,  25),
    (10.50,   0),
  ];

  /// Estimate State of Charge (0–100 %) from the current voltage reading
  /// by linearly interpolating [socVoltageTable].
  static int computeSoc(double voltage) {
    if (voltage <= 0.5) return 0;
    final table = socVoltageTable;
    if (voltage >= table.first.$1) return table.first.$2;
    if (voltage <= table.last.$1) return table.last.$2;
    for (int i = 0; i < table.length - 1; i++) {
      final hi = table[i];
      final lo = table[i + 1];
      if (voltage <= hi.$1 && voltage >= lo.$1) {
        final t = (voltage - lo.$1) / (hi.$1 - lo.$1);
        return (lo.$2 + t * (hi.$2 - lo.$2)).round().clamp(0, 100);
      }
    }
    return 0;
  }

  /// Evaluates Battery State of Health (SOH) (0–100%) based on physical damage
  /// indicators and historical stress without requiring a current sensor.
  ///
  /// Physical damage factors:
  /// 1. Deep discharge (< 10.5V): Causes irreversible plate sulfation and active material loss.
  /// 2. Overcharge (> 14.8V): Causes electrolyte boiling (dry-out) and positive grid corrosion.
  /// 3. Thermal stress (> 45°C / > 55°C): Accelerates chemical breakdown (Arrhenius rule).
  /// 4. Dead / shorted cell: Indicated by persistent low voltage (< 10.8V) across multiple readings.
  /// 5. Inability to reach full charge: Peak recorded voltage consistently lower than 12.5V.
  /// 6. Calendar age: If [installationDate] is known (~8% degradation per year after year 1).
  static int calculateHealth({
    required double voltage,
    required double temperature,
    List<Measurement>? history,
    DateTime? installationDate,
  }) {
    if (voltage <= 0.5) return 0; // Disconnected or 0V
    
    double health = 100.0;

    // --- 1. Immediate Critical Stress Penalties ---
    if (voltage < defaultVoltCriticalLow) {
      // Current reading is in deep discharge territory (severe sulfation active)
      final deficit = defaultVoltCriticalLow - voltage;
      health -= (15.0 + (deficit * 15.0)).clamp(15.0, 45.0);
    } else if (voltage > defaultVoltOvercharge) {
      // Overcharge active (electrolyte gassing and grid corrosion)
      health -= 20.0;
    }

    if (temperature >= defaultTempCritical) {
      health -= 25.0; // Critical heat
    } else if (temperature >= defaultTempWarning) {
      health -= 10.0; // Warning heat
    }

    // --- 2. Historical Damage Analysis (if history is present) ---
    if (history != null && history.isNotEmpty) {
      int deepDischargeCount = 0;
      int overchargeCount = 0;
      int highTempCount = 0;
      double peakVoltage = 0.0;

      for (final m in history) {
        if (m.voltage > peakVoltage) peakVoltage = m.voltage;
        if (m.voltage < defaultVoltCriticalLow) deepDischargeCount++;
        if (m.voltage > defaultVoltOvercharge) overchargeCount++;
        if (m.temperature >= defaultTempWarning) highTempCount++;
      }

      // Past deep discharge damage (permanent sulfation)
      if (deepDischargeCount > 0) {
        health -= (deepDischargeCount * 5.0).clamp(5.0, 30.0);
      }

      // Past overcharge damage (grid corrosion)
      if (overchargeCount > 0) {
        health -= (overchargeCount * 4.0).clamp(4.0, 20.0);
      }

      // Past thermal stress
      if (highTempCount > 2) {
        health -= (highTempCount * 2.0).clamp(4.0, 15.0);
      }

      // Dead / Shorted Cell Detection:
      // If a 12V battery has >= 3 measurements and never exceeded 10.8V,
      // one of the 6 cells is damaged/shorted.
      if (history.length >= 3 && peakVoltage < 10.8 && peakVoltage > 1.0) {
        health -= 50.0; // Major cell failure
      } else if (history.length >= 5 && peakVoltage < 12.30 && peakVoltage > 1.0) {
        // Battery has been cycled but cannot reach full resting voltage (loss of active mass)
        final gap = (12.50 - peakVoltage).clamp(0.0, 1.5);
        health -= (gap * 25.0);
      }
    }

    // --- 3. Calendar Aging (if installationDate provided) ---
    if (installationDate != null) {
      final daysInService = DateTime.now().difference(installationDate).inDays;
      if (daysInService > 365) {
        final yearsPastOne = (daysInService - 365) / 365.25;
        health -= (yearsPastOne * 8.0).clamp(0.0, 40.0);
      }
    }

    return health.round().clamp(5, 100);
  }

  /// Convenience fallback that delegates to [calculateHealth].
  static int computeSoh(double? peakVoltage) {
    if (peakVoltage == null || peakVoltage <= 0) return 100;
    return calculateHealth(voltage: peakVoltage, temperature: 25.0);
  }

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
