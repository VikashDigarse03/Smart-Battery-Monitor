/*
 * =============================================================
 *  ESP32 Battery Monitor Firmware
 * =============================================================
 *  Board: DOIT ESP32 DevKit V1
 *
 *  Hardware:
 *    - Voltage Sensor Module (25V)    → GPIO 34
 *    - ACS712 30A Current Sensor      → GPIO 35 (via voltage divider)
 *    - DS18B20 Temperature Sensor     → GPIO 15 (4.7kΩ pull-up)
 *    - ST7789 2.4" TFT Display (SPI) → CS=5, DC=2, RST=4, MOSI=23, SCLK=18
 *    - Buzzer                         → GPIO 27
 *    - LED                            → GPIO 26
 *
 *  Communication:
 *    - Bluetooth Classic: streams JSON every 2s, accepts commands
 *    - WiFi HTTP Server: serves JSON at /data endpoint
 *    - WiFi credentials configurable via Bluetooth commands
 *
 *  Libraries Required (install via Arduino Library Manager):
 *    - OneWire
 *    - DallasTemperature
 *    - ArduinoJson
 *    - Adafruit GFX Library
 *    - Adafruit ST7735 and ST7789 Library
 *
 *  Built-in (no install needed):
 *    - BluetoothSerial, WiFi, WebServer, Preferences, SPI
 * =============================================================
 */

#include "BluetoothSerial.h"
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <ArduinoJson.h>
#include <DallasTemperature.h>
#include <OneWire.h>
#include <Preferences.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>

// ─── Pin Definitions ─────────────────────────────────────────
// Sensors
#define VOLTAGE_PIN 34 // Voltage sensor analog input
#define CURRENT_PIN 35 // ACS712 analog input (through voltage divider)
#define TEMP_PIN 15    // DS18B20 data pin

// TFT Display (ST7789, SPI)
#define TFT_CS 5
#define TFT_RST 4
#define TFT_DC 2
#define TFT_MOSI 23
#define TFT_SCLK 18

// Buzzer & LED
#define BUZZER_PIN 27
#define LED_PIN 26

// Screen dimensions (landscape)
#define SCREEN_W 320
#define SCREEN_H 240

// ─── Sensor Calibration Constants ────────────────────────────
// Voltage sensor: 25V module with 5:1 divider ratio
// Adjust VOLTAGE_CALIBRATION after comparing with a multimeter
float VOLTAGE_DIVIDER_RATIO = 5.0;
float VOLTAGE_CALIBRATION = 1.0; // Fine-tune multiplier

// ACS712 30A: sensitivity = 66 mV/A
// With external voltage divider (2× 100kΩ) scaling 5V → 2.5V
// Divider ratio = 100k / (100k + 100k) = 0.5
// Effective sensitivity at ESP32 pin = 66 * 0.5 = 33 mV/A
float ACS712_SENSITIVITY = 66.0;   // mV/A (sensor spec)
float CURRENT_DIVIDER_RATIO = 0.5; // R2/(R1+R2) for 2× 100kΩ divider
float ACS712_ZERO_OFFSET = 1300.0; // mV at 0A after divider (measured idle)
// NOTE: Auto-calibrated on startup and saved to flash.
//       Use CALIBRATE_ZERO BT command to re-calibrate with no load connected.

// ─── Sampling ────────────────────────────────────────────────
int ADC_SAMPLES = 64; // Number of samples to average

// ─── Connection Detection ────────────────────────────────────
// If measured voltage is below this, no battery is connected.
// ADC noise / residual voltage with nothing connected is typically < 1V.
float VOLTAGE_CONNECTED_THRESHOLD = 1.0; // Volts

// ─── Alert Thresholds (12V Lead-Acid) ────────────────────────
float VOLT_CRITICAL_LOW = 10.5; // Deeply discharged / damaged
float VOLT_WARNING_LOW = 11.5;  // Low battery
float VOLT_NORMAL_LOW = 12.0;   // Acceptable minimum
float VOLT_FULL = 12.7;         // Fully charged (resting)
float VOLT_OVERCHARGE = 14.8;   // Overcharging

float TEMP_WARNING = 45.0;  // °C — getting hot
float TEMP_CRITICAL = 55.0; // °C — dangerous

float CURRENT_WARNING = 20.0;  // A — high draw
float CURRENT_CRITICAL = 28.0; // A — near sensor limit

// ─── Alert States ────────────────────────────────────────────
enum AlertLevel { ALERT_NONE, ALERT_WARNING, ALERT_CRITICAL };

// ─── Custom Colors (RGB565) ──────────────────────────────────
#define COLOR_BG 0x0000     // Black
#define COLOR_HEADER 0x001F // Blue
#define COLOR_WHITE 0xFFFF
#define COLOR_YELLOW 0xFFE0
#define COLOR_CYAN 0x07FF
#define COLOR_GREEN 0x07E0
#define COLOR_RED 0xF800
#define COLOR_ORANGE 0xFD20
#define COLOR_DARK_GRAY 0x2104
#define COLOR_LIGHT_GRAY 0x8410

// ─── Objects ─────────────────────────────────────────────────
BluetoothSerial SerialBT;
WebServer server(80);
Preferences prefs;
OneWire oneWire(TEMP_PIN);
DallasTemperature tempSensor(&oneWire);
Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_RST);

// ─── State ───────────────────────────────────────────────────
String wifiSSID = "";
String wifiPassword = "";
bool wifiConnected = false;

// Timing
unsigned long lastBTSend = 0;
unsigned long lastDisplayUpdate = 0;
unsigned long lastAlertCheck = 0;
unsigned long lastBuzzerToggle = 0;
unsigned long lastLedToggle = 0;

const unsigned long BT_SEND_INTERVAL = 2000; // Send every 2 seconds
const unsigned long DISPLAY_UPDATE_INTERVAL = 1000;
const unsigned long ALERT_CHECK_INTERVAL = 500;

// Current sensor readings (updated continuously)
float currentVoltage = 0.0;
float currentCurrent = 0.0;
float currentTemperature = 0.0;
float currentPower = 0.0;
int batteryPercent = 0;
int batteryCapacity = 100; // Ah
float timeLeft = 0.0;    // Hours (positive = charging, negative = discharging)
int batteryHealth = 100; // % SOH
bool batteryConnected = false; // True when a battery is actually detected

// Internal variables for Health estimation
float restingVoltage = 12.7;

// Previous display values (for partial refresh — avoid flicker)
float prevVoltage = -1;
float prevCurrent = -1;
float prevTemperature = -1;
float prevPower = -1;
float prevTimeLeft = -1;
int prevHealth = -1;
int prevPercent = -1;
AlertLevel prevAlert = ALERT_NONE;
bool prevConnected =
    true; // Start different from batteryConnected to force initial draw

// Alert state
AlertLevel currentAlert = ALERT_NONE;
String alertMessage = "";
bool buzzerOn = false;
bool ledOn = false;

// ─── Utility (forward declarations) ─────────────────────────
float round2(float val);
float round1(float val);
int voltageToPercent(float voltage);
uint16_t getVoltageColor(float voltage);
void drawStaticLayout();
void updateDisplay();
void updateAlerts();
void handleBuzzerLed();
void processBluetoothCommand(String cmd);
void sendBluetoothData();
void connectWiFi();
void readSensors();
void handleBluetooth();

// ─────────────────────────────────────────────────────────────
//  SETUP
// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("\n========================================");
  Serial.println("  ESP32 Battery Monitor — Starting...");
  Serial.println("========================================");

  // ── GPIO Setup ──
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(LED_PIN, LOW);

  // Initialize ADC
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db); // Full 0–3.3V range

  // Initialize DS18B20
  tempSensor.begin();
  Serial.printf("  DS18B20 sensors found: %d\n", tempSensor.getDeviceCount());

  // ── TFT Display ──
  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.init(240, 320);
  tft.setRotation(3); // Landscape (flipped)
  tft.fillScreen(COLOR_BG);
  drawStaticLayout();
  Serial.println("  TFT Display initialized (ST7789 320x240 landscape)");

  // Initialize Bluetooth
  SerialBT.begin("ESP32_BattMon");
  Serial.println("  Bluetooth started: ESP32_BattMon");

  // Load saved WiFi credentials (used for the ESP32's own network)
  prefs.begin("wifi", true); // read-only
  wifiSSID = prefs.getString("ssid", "ESP32_Battery");
  wifiPassword = prefs.getString("pass", "12345678");
  prefs.end();

  // Load custom config
  prefs.begin("batt", true);
  batteryCapacity = prefs.getInt("capacity", 100);
  VOLTAGE_DIVIDER_RATIO = prefs.getFloat("v_div", 5.0);
  VOLTAGE_CALIBRATION = prefs.getFloat("v_cal", 1.0);
  ACS712_SENSITIVITY = prefs.getFloat("i_sens", 66.0);
  CURRENT_DIVIDER_RATIO = prefs.getFloat("i_div", 0.5);
  ADC_SAMPLES = prefs.getInt("adc_samp", 64);
  VOLT_CRITICAL_LOW = prefs.getFloat("v_crit_L", 10.5);
  VOLT_WARNING_LOW = prefs.getFloat("v_warn_L", 11.5);
  VOLT_NORMAL_LOW = prefs.getFloat("v_norm_L", 12.0);
  VOLT_FULL = prefs.getFloat("v_full", 12.7);
  VOLT_OVERCHARGE = prefs.getFloat("v_over", 14.8);
  TEMP_WARNING = prefs.getFloat("t_warn", 45.0);
  TEMP_CRITICAL = prefs.getFloat("t_crit", 55.0);
  CURRENT_WARNING = prefs.getFloat("i_warn", 20.0);
  CURRENT_CRITICAL = prefs.getFloat("i_crit", 28.0);
  prefs.end();

  // ── Current sensor zero-offset calibration ──
  // Auto-calibrate every boot by sampling the current pin.
  // Assumes no load is flowing through ACS712 at power-on.
  Serial.println("  Auto-calibrating current sensor...");
  long calSum = 0;
  for (int i = 0; i < 200; i++) {
    calSum += analogReadMilliVolts(CURRENT_PIN);
    delay(5);
  }
  ACS712_ZERO_OFFSET = calSum / 200.0;
  Serial.printf("  ACS712 zero offset: %.1f mV\n", ACS712_ZERO_OFFSET);

  // Start the WiFi Access Point
  connectWiFi();

  // Setup HTTP endpoints (active even if not connected yet)
  server.on("/", handleRoot);
  server.on("/data", handleData);
  server.onNotFound(handleNotFound);
  server.begin();

  // ── Startup beep ──
  digitalWrite(BUZZER_PIN, HIGH);
  delay(100);
  digitalWrite(BUZZER_PIN, LOW);

  Serial.println("========================================");
  Serial.println("  System Ready!");
  Serial.println("========================================\n");
}

// ─────────────────────────────────────────────────────────────
//  MAIN LOOP
// ─────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  // 1. Read sensors
  readSensors();

  // 2. Handle Bluetooth commands & send data
  handleBluetooth();

  // 3. Handle WiFi HTTP requests
  if (wifiConnected) {
    server.handleClient();
  }

  // 4. Update display (every 1 second)
  if (now - lastDisplayUpdate >= DISPLAY_UPDATE_INTERVAL) {
    lastDisplayUpdate = now;
    updateDisplay();
  }

  // 5. Check alerts (every 500ms)
  if (now - lastAlertCheck >= ALERT_CHECK_INTERVAL) {
    lastAlertCheck = now;
    updateAlerts();
  }

  // 6. Handle buzzer & LED patterns
  handleBuzzerLed();

  delay(50); // Small delay to prevent watchdog issues
}

// ─────────────────────────────────────────────────────────────
//  SENSOR READING
// ─────────────────────────────────────────────────────────────
void readSensors() {
  // --- Voltage ---
  long voltageSum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    voltageSum += analogReadMilliVolts(VOLTAGE_PIN);
    delayMicroseconds(100);
  }
  float voltageMv = voltageSum / (float)ADC_SAMPLES;
  float rawVoltage =
      (voltageMv / 1000.0) * VOLTAGE_DIVIDER_RATIO * VOLTAGE_CALIBRATION;

  // DEBUG: Print raw ADC values every 2 seconds
  static unsigned long lastDebug = 0;
  if (millis() - lastDebug >= 2000) {
    lastDebug = millis();
    Serial.printf(
        "[DEBUG] Voltage pin raw: %.1f mV → %.2f V | Current pin raw: %ld mV\n",
        voltageMv, rawVoltage, analogReadMilliVolts(CURRENT_PIN));
  }

  // --- Connection Detection ---
  // If measured voltage is below the threshold, no battery is connected.
  // This prevents ADC noise/residual voltage from producing fake readings.
  if (rawVoltage < VOLTAGE_CONNECTED_THRESHOLD) {
    batteryConnected = false;
    currentVoltage = 0.0;
    currentCurrent = 0.0;
    currentPower = 0.0;
    batteryPercent = 0;
    timeLeft = 0.0;
    // Don't reset health — preserve last known value
    return; // Skip all further sensor processing
  }

  batteryConnected = true;
  currentVoltage = rawVoltage;

  // --- Current ---
  long currentSum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    currentSum += analogReadMilliVolts(CURRENT_PIN);
    delayMicroseconds(100);
  }
  float currentMv = currentSum / (float)ADC_SAMPLES;
  // Current = (measuredMv - zeroOffset) / effectiveSensitivity
  float effectiveSensitivity = ACS712_SENSITIVITY * CURRENT_DIVIDER_RATIO;
  currentCurrent = (currentMv - ACS712_ZERO_OFFSET) / effectiveSensitivity;
  // Clamp small noise around zero
  if (abs(currentCurrent) < 0.05)
    currentCurrent = 0.0;

  // --- Temperature ---
  tempSensor.requestTemperatures();
  float tempC = tempSensor.getTempCByIndex(0);
  if (tempC != DEVICE_DISCONNECTED_C) {
    currentTemperature = tempC;
  }
  // If disconnected, keep last known value

  // --- Derived values ---
  currentPower = currentVoltage * abs(currentCurrent);
  batteryPercent = voltageToPercent(currentVoltage);

  // --- Time Left Calculation ---
  if (currentCurrent > 0.5) {
    // Charging
    timeLeft =
        (batteryCapacity * ((100.0 - batteryPercent) / 100.0)) / currentCurrent;
  } else if (currentCurrent < -0.5) {
    // Discharging
    timeLeft =
        -(batteryCapacity * (batteryPercent / 100.0)) / abs(currentCurrent);
  } else {
    timeLeft = 0.0; // Idle
  }

  // --- Health Estimation (Simple Voltage Droop) ---
  if (abs(currentCurrent) < 0.5) {
    // Slowly update resting voltage when idle
    restingVoltage = (restingVoltage * 0.99) + (currentVoltage * 0.01);
  }
  if (currentCurrent < -5.0) {
    // Calculate internal resistance (Ohms)
    float ir = (restingVoltage - currentVoltage) / abs(currentCurrent);
    // Typical healthy 12V 100Ah battery IR is < 15mOhm (0.015 Ohms)
    // Map IR from 0.010 (100% health) to 0.050 (0% health)
    int estHealth = map(ir * 1000, 10, 50, 100, 0);
    estHealth = constrain(estHealth, 1, 100);
    // Slow moving average for health
    batteryHealth = (batteryHealth * 0.99) + (estHealth * 0.01);
  }
}

// =============================================================
//  BATTERY PERCENTAGE (12V Lead-Acid Lookup)
// =============================================================
int voltageToPercent(float voltage) {
  if (voltage >= 12.70)
    return 100;
  if (voltage >= 12.40)
    return map(voltage * 100, 1240, 1270, 75, 100);
  if (voltage >= 12.20)
    return map(voltage * 100, 1220, 1240, 50, 75);
  if (voltage >= 12.00)
    return map(voltage * 100, 1200, 1220, 25, 50);
  if (voltage >= 11.80)
    return map(voltage * 100, 1180, 1200, 0, 25);
  return 0;
}

// =============================================================
//  TFT DISPLAY
// =============================================================
void drawStaticLayout() {
  // ── Header bar ──
  tft.fillRect(0, 0, SCREEN_W, 35, COLOR_HEADER);
  tft.setTextColor(COLOR_WHITE);
  tft.setTextSize(2);
  tft.setCursor(60, 10);
  tft.print("BATTERY MONITOR");

  // ── Row labels ──
  tft.setTextColor(COLOR_WHITE);
  tft.setTextSize(2);

  tft.setCursor(10, 45);
  tft.print("Voltage");

  tft.setCursor(10, 70);
  tft.print("Current");

  tft.setCursor(10, 95);
  tft.print("Power");

  tft.setCursor(10, 120);
  tft.print("Temp");

  tft.setCursor(10, 145);
  tft.print("Time Lft");

  tft.setCursor(10, 170);
  tft.print("Health");

  tft.setCursor(10, 200);
  tft.print("Battery");

  // ── Battery bar outline ──
  tft.drawRect(120, 195, 120, 25, COLOR_WHITE);

  // ── Separator lines ──
  tft.drawFastHLine(10, 65, 300, COLOR_DARK_GRAY);
  tft.drawFastHLine(10, 90, 300, COLOR_DARK_GRAY);
  tft.drawFastHLine(10, 115, 300, COLOR_DARK_GRAY);
  tft.drawFastHLine(10, 140, 300, COLOR_DARK_GRAY);
  tft.drawFastHLine(10, 165, 300, COLOR_DARK_GRAY);
  tft.drawFastHLine(10, 190, 300, COLOR_DARK_GRAY);
}

void updateDisplay() {
  // ── Handle disconnected state ──
  if (!batteryConnected) {
    if (prevConnected != false) {
      // State just changed to disconnected — clear value area and show message
      prevConnected = false;

      // Clear all value fields
      tft.fillRect(150, 43, 170, 20, COLOR_BG); // Voltage
      tft.fillRect(150, 68, 170, 20, COLOR_BG); // Current
      tft.fillRect(150, 93, 170, 20, COLOR_BG); // Power
      // Temperature stays (it still reads)
      tft.fillRect(150, 143, 170, 20, COLOR_BG); // Time Left
      tft.fillRect(150, 168, 170, 20, COLOR_BG); // Health
      tft.fillRect(122, 197, 116, 21, COLOR_BG); // Bar
      tft.fillRect(245, 195, 75, 25, COLOR_BG);  // Percent

      // Show dashes / "--" for each disconnected field
      tft.setTextSize(2);

      tft.setTextColor(COLOR_LIGHT_GRAY);
      tft.setCursor(150, 45);
      tft.print("-- V");
      tft.setCursor(150, 70);
      tft.print("-- A");
      tft.setCursor(150, 95);
      tft.print("-- W");
      tft.setCursor(150, 145);
      tft.print("--");
      tft.setCursor(150, 170);
      tft.print("-- %");
      tft.setCursor(250, 200);
      tft.print("--%");

      // Show "NOT CONNECTED" banner
      tft.fillRect(0, 225, SCREEN_W, 15, COLOR_RED);
      tft.setTextColor(COLOR_WHITE);
      tft.setTextSize(1);
      tft.setCursor(70, 228);
      tft.print("BATTERY NOT CONNECTED");

      // Reset prev values so they refresh when reconnected
      prevVoltage = -1;
      prevCurrent = -1;
      prevPower = -1;
      prevTimeLeft = -1;
      prevHealth = -1;
      prevPercent = -1;
      prevAlert = ALERT_NONE;
    }

    // Still update temperature even when disconnected
    float t = round1(currentTemperature);
    if (t != prevTemperature) {
      tft.fillRect(150, 118, 170, 20, COLOR_BG);
      uint16_t tempColor = COLOR_GREEN;
      if (t >= TEMP_CRITICAL)
        tempColor = COLOR_RED;
      else if (t >= TEMP_WARNING)
        tempColor = COLOR_ORANGE;
      tft.setTextColor(tempColor);
      tft.setTextSize(2);
      tft.setCursor(150, 120);
      tft.print(t, 1);
      tft.print(" C");
      prevTemperature = t;
    }
    return;
  }

  // ── Battery is connected — normal display ──
  if (prevConnected != true) {
    // Just reconnected — clear the "NOT CONNECTED" banner
    prevConnected = true;
    tft.fillRect(0, 225, SCREEN_W, 15, COLOR_BG);
  }

  float v = round2(currentVoltage);
  float i = round2(currentCurrent);
  float t = round1(currentTemperature);
  float p = round2(currentPower);
  float l = round2(timeLeft);
  int h = batteryHealth;
  int pct = batteryPercent;

  // ── Voltage ──
  if (v != prevVoltage) {
    tft.fillRect(150, 43, 170, 20, COLOR_BG);
    tft.setTextColor(getVoltageColor(v));
    tft.setTextSize(2);
    tft.setCursor(150, 45);
    tft.print(v, 2);
    tft.print(" V");
    prevVoltage = v;
  }

  // ── Current ──
  if (i != prevCurrent) {
    tft.fillRect(150, 68, 170, 20, COLOR_BG);
    tft.setTextColor(COLOR_CYAN);
    tft.setTextSize(2);
    tft.setCursor(150, 70);
    tft.print(i, 2);
    tft.print(" A");
    prevCurrent = i;
  }

  // ── Power ──
  if (p != prevPower) {
    tft.fillRect(150, 93, 170, 20, COLOR_BG);
    tft.setTextColor(COLOR_GREEN);
    tft.setTextSize(2);
    tft.setCursor(150, 95);
    tft.print(p, 1);
    tft.print(" W");
    prevPower = p;
  }

  // ── Temperature ──
  if (t != prevTemperature) {
    tft.fillRect(150, 118, 170, 20, COLOR_BG);
    uint16_t tempColor = COLOR_GREEN;
    if (t >= TEMP_CRITICAL)
      tempColor = COLOR_RED;
    else if (t >= TEMP_WARNING)
      tempColor = COLOR_ORANGE;
    tft.setTextColor(tempColor);
    tft.setTextSize(2);
    tft.setCursor(150, 120);
    tft.print(t, 1);
    tft.print(" C");
    prevTemperature = t;
  }

  // ── Time Left ──
  if (l != prevTimeLeft) {
    tft.fillRect(150, 143, 170, 20, COLOR_BG);
    tft.setTextColor(COLOR_WHITE);
    tft.setTextSize(2);
    tft.setCursor(150, 145);
    if (l == 0) {
      tft.print("Idle");
    } else {
      tft.print(abs(l), 1);
      tft.print(" h");
    }
    prevTimeLeft = l;
  }

  // ── Health ──
  if (h != prevHealth) {
    tft.fillRect(150, 168, 170, 20, COLOR_BG);
    uint16_t hColor = COLOR_GREEN;
    if (h < 50)
      hColor = COLOR_RED;
    else if (h < 80)
      hColor = COLOR_ORANGE;
    tft.setTextColor(hColor);
    tft.setTextSize(2);
    tft.setCursor(150, 170);
    tft.print(h);
    tft.print(" %");
    prevHealth = h;
  }

  // ── Battery percentage bar ──
  if (pct != prevPercent) {
    tft.fillRect(122, 197, 116, 21, COLOR_BG);
    int barWidth = (pct * 116) / 100;
    if (barWidth > 0) {
      uint16_t barColor = COLOR_GREEN;
      if (pct <= 10)
        barColor = COLOR_RED;
      else if (pct <= 25)
        barColor = COLOR_ORANGE;
      else if (pct <= 50)
        barColor = COLOR_YELLOW;
      tft.fillRect(122, 197, barWidth, 21, barColor);
    }
    tft.fillRect(245, 195, 75, 25, COLOR_BG);
    tft.setTextColor(COLOR_WHITE);
    tft.setTextSize(2);
    tft.setCursor(250, 200);
    tft.print(pct);
    tft.print("%");
    prevPercent = pct;
  }

  // ── Alert banner ──
  if (currentAlert != prevAlert) {
    tft.fillRect(0, 225, SCREEN_W, 15, COLOR_BG);
    if (currentAlert == ALERT_CRITICAL) {
      tft.fillRect(0, 225, SCREEN_W, 15, COLOR_RED);
      tft.setTextColor(COLOR_WHITE);
      tft.setTextSize(1);
      tft.setCursor(5, 228);
      tft.print("!! ");
      tft.print(alertMessage);
    } else if (currentAlert == ALERT_WARNING) {
      tft.fillRect(0, 225, SCREEN_W, 15, COLOR_ORANGE);
      tft.setTextColor(COLOR_BG);
      tft.setTextSize(1);
      tft.setCursor(5, 228);
      tft.print("! ");
      tft.print(alertMessage);
    }
    prevAlert = currentAlert;
  }
}

uint16_t getVoltageColor(float voltage) {
  if (voltage >= 12.6)
    return COLOR_GREEN;
  if (voltage >= VOLT_NORMAL_LOW)
    return COLOR_YELLOW;
  if (voltage >= VOLT_WARNING_LOW)
    return COLOR_ORANGE;
  return COLOR_RED;
}

// =============================================================
//  ALERTS — Buzzer & LED
// =============================================================
void updateAlerts() {
  // Don't trigger battery alerts when nothing is connected
  if (!batteryConnected) {
    currentAlert = ALERT_NONE;
    alertMessage = "";
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(LED_PIN, LOW);
    return;
  }

  AlertLevel level = ALERT_NONE;
  String msg = "";

  if (currentVoltage > 0.5 && currentVoltage < VOLT_CRITICAL_LOW) {
    level = ALERT_CRITICAL;
    msg = "BATTERY DAMAGED - Voltage critically low!";
  } else if (currentVoltage > 0.5 && currentVoltage < VOLT_WARNING_LOW) {
    if (level < ALERT_WARNING) {
      level = ALERT_WARNING;
      msg = "Low battery voltage";
    }
  } else if (currentVoltage > VOLT_OVERCHARGE) {
    level = ALERT_CRITICAL;
    msg = "OVERCHARGE - Voltage too high!";
  }

  if (currentTemperature > TEMP_CRITICAL) {
    level = ALERT_CRITICAL;
    msg = "OVERHEAT - Temperature critical!";
  } else if (currentTemperature > TEMP_WARNING) {
    if (level < ALERT_WARNING) {
      level = ALERT_WARNING;
      msg = "High temperature warning";
    }
  }

  if (abs(currentCurrent) > CURRENT_CRITICAL) {
    level = ALERT_CRITICAL;
    msg = "OVERCURRENT - Current too high!";
  } else if (abs(currentCurrent) > CURRENT_WARNING) {
    if (level < ALERT_WARNING) {
      level = ALERT_WARNING;
      msg = "High current draw";
    }
  }

  currentAlert = level;
  alertMessage = msg;

  if (level == ALERT_NONE) {
    digitalWrite(BUZZER_PIN, LOW);
    digitalWrite(LED_PIN, LOW);
    buzzerOn = false;
    ledOn = false;
  }
}

void handleBuzzerLed() {
  unsigned long now = millis();

  if (currentAlert == ALERT_CRITICAL) {
    if (now - lastBuzzerToggle >= 200) {
      lastBuzzerToggle = now;
      buzzerOn = !buzzerOn;
      digitalWrite(BUZZER_PIN, buzzerOn ? HIGH : LOW);
    }
    if (now - lastLedToggle >= 150) {
      lastLedToggle = now;
      ledOn = !ledOn;
      digitalWrite(LED_PIN, ledOn ? HIGH : LOW);
    }
  } else if (currentAlert == ALERT_WARNING) {
    unsigned long buzzerCycle = now % 3000;
    if (buzzerCycle < 100) {
      digitalWrite(BUZZER_PIN, HIGH);
    } else {
      digitalWrite(BUZZER_PIN, LOW);
    }
    if (now - lastLedToggle >= 500) {
      lastLedToggle = now;
      ledOn = !ledOn;
      digitalWrite(LED_PIN, ledOn ? HIGH : LOW);
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  BLUETOOTH HANDLING
// ─────────────────────────────────────────────────────────────
void handleBluetooth() {
  // Check for incoming commands
  if (SerialBT.available()) {
    String cmd = SerialBT.readStringUntil('\n');
    cmd.trim();
    processBluetoothCommand(cmd);
  }

  // Send data periodically
  unsigned long now = millis();
  if (now - lastBTSend >= BT_SEND_INTERVAL) {
    lastBTSend = now;
    sendBluetoothData();
  }
}

void processBluetoothCommand(String cmd) {
  Serial.printf("BT CMD: %s\n", cmd.c_str());

  // ── WIFI_SET:<SSID>:<PASSWORD> ──
  if (cmd.startsWith("WIFI_SET:")) {
    String params = cmd.substring(9); // After "WIFI_SET:"
    int sepIdx = params.indexOf(':');
    if (sepIdx > 0) {
      wifiSSID = params.substring(0, sepIdx);
      wifiPassword = params.substring(sepIdx + 1);

      // Save to non-volatile storage
      prefs.begin("wifi", false);
      prefs.putString("ssid", wifiSSID);
      prefs.putString("pass", wifiPassword);
      prefs.end();

      SerialBT.println(
          "{\"cmd\":\"WIFI_SET\",\"status\":\"saved\",\"ssid\":\"" + wifiSSID +
          "\"}");
      Serial.printf("WiFi credentials saved: SSID=%s\n", wifiSSID.c_str());

      // Try connecting
      connectWiFi();
    } else {
      SerialBT.println("{\"cmd\":\"WIFI_SET\",\"status\":\"error\",\"msg\":"
                       "\"Format: WIFI_SET:SSID:PASSWORD\"}");
    }
  }
  // ── WIFI_STATUS ──
  else if (cmd == "WIFI_STATUS") {
    StaticJsonDocument<256> doc;
    doc["cmd"] = "WIFI_STATUS";
    doc["connected"] = wifiConnected;
    doc["ssid"] = wifiSSID;
    if (wifiConnected) {
      doc["ip"] = WiFi.localIP().toString();
    }
    String response;
    serializeJson(doc, response);
    SerialBT.println(response);
  }
  // ── WIFI_CLEAR ──
  else if (cmd == "WIFI_CLEAR") {
    prefs.begin("wifi", false);
    prefs.clear();
    prefs.end();
    wifiSSID = "";
    wifiPassword = "";
    WiFi.disconnect();
    wifiConnected = false;
    SerialBT.println("{\"cmd\":\"WIFI_CLEAR\",\"status\":\"cleared\"}");
    Serial.println("WiFi credentials cleared.");
  }
  // ── READ (request single reading now) ──
  else if (cmd == "READ") {
    sendBluetoothData();
  }
  // ── PING ──
  else if (cmd == "PING") {
    SerialBT.println("{\"cmd\":\"PONG\"}");
  }
  // ── CALIBRATE_ZERO ──
  // Use with NO LOAD connected to set the ACS712 zero-current offset
  else if (cmd == "CALIBRATE_ZERO") {
    long sum = 0;
    for (int i = 0; i < 200; i++) {
      sum += analogReadMilliVolts(CURRENT_PIN);
      delay(5);
    }
    ACS712_ZERO_OFFSET = sum / 200.0;
    // Save to flash so it persists across reboots
    prefs.begin("batt", false);
    prefs.putFloat("zeroOff", ACS712_ZERO_OFFSET);
    prefs.end();
    SerialBT.println("{\"cmd\":\"CALIBRATE_ZERO\",\"offset_mv\":" +
                     String(ACS712_ZERO_OFFSET, 1) + "}");
    Serial.printf("ACS712 zero offset calibrated & saved: %.1f mV\n",
                  ACS712_ZERO_OFFSET);
  }
  // ── CAPACITY_SET ──
  else if (cmd.startsWith("CAPACITY_SET:")) {
    int newCap = cmd.substring(13).toInt();
    if (newCap > 0) {
      batteryCapacity = newCap;
      prefs.begin("batt", false);
      prefs.putInt("capacity", batteryCapacity);
      prefs.end();
      SerialBT.println(
          "{\"cmd\":\"CAPACITY_SET\",\"status\":\"saved\",\"capacity\":" +
          String(batteryCapacity) + "}");
      Serial.printf("Capacity saved: %d Ah\n", batteryCapacity);
    }
  }
  // ── JSON CONFIG ──
  else if (cmd.startsWith("{")) {
    StaticJsonDocument<512> doc;
    DeserializationError error = deserializeJson(doc, cmd);
    if (!error && doc["cmd"] == "config") {
      // WiFi
      if (doc.containsKey("ssid")) wifiSSID = doc["ssid"].as<String>();
      if (doc.containsKey("pass")) wifiPassword = doc["pass"].as<String>();

      prefs.begin("wifi", false);
      prefs.putString("ssid", wifiSSID);
      prefs.putString("pass", wifiPassword);
      prefs.end();

      // Battery & Sensor config
      prefs.begin("batt", false);
      if (doc.containsKey("v_div")) { VOLTAGE_DIVIDER_RATIO = doc["v_div"]; prefs.putFloat("v_div", VOLTAGE_DIVIDER_RATIO); }
      if (doc.containsKey("v_cal")) { VOLTAGE_CALIBRATION = doc["v_cal"]; prefs.putFloat("v_cal", VOLTAGE_CALIBRATION); }
      if (doc.containsKey("i_sens")) { ACS712_SENSITIVITY = doc["i_sens"]; prefs.putFloat("i_sens", ACS712_SENSITIVITY); }
      if (doc.containsKey("i_div")) { CURRENT_DIVIDER_RATIO = doc["i_div"]; prefs.putFloat("i_div", CURRENT_DIVIDER_RATIO); }
      if (doc.containsKey("adc_samp")) { ADC_SAMPLES = doc["adc_samp"]; prefs.putInt("adc_samp", ADC_SAMPLES); }
      if (doc.containsKey("cap")) { batteryCapacity = doc["cap"]; prefs.putInt("capacity", batteryCapacity); }

      if (doc.containsKey("v_crit_L")) { VOLT_CRITICAL_LOW = doc["v_crit_L"]; prefs.putFloat("v_crit_L", VOLT_CRITICAL_LOW); }
      if (doc.containsKey("v_warn_L")) { VOLT_WARNING_LOW = doc["v_warn_L"]; prefs.putFloat("v_warn_L", VOLT_WARNING_LOW); }
      if (doc.containsKey("v_norm_L")) { VOLT_NORMAL_LOW = doc["v_norm_L"]; prefs.putFloat("v_norm_L", VOLT_NORMAL_LOW); }
      if (doc.containsKey("v_full")) { VOLT_FULL = doc["v_full"]; prefs.putFloat("v_full", VOLT_FULL); }
      if (doc.containsKey("v_over")) { VOLT_OVERCHARGE = doc["v_over"]; prefs.putFloat("v_over", VOLT_OVERCHARGE); }

      if (doc.containsKey("t_warn")) { TEMP_WARNING = doc["t_warn"]; prefs.putFloat("t_warn", TEMP_WARNING); }
      if (doc.containsKey("t_crit")) { TEMP_CRITICAL = doc["t_crit"]; prefs.putFloat("t_crit", TEMP_CRITICAL); }

      if (doc.containsKey("i_warn")) { CURRENT_WARNING = doc["i_warn"]; prefs.putFloat("i_warn", CURRENT_WARNING); }
      if (doc.containsKey("i_crit")) { CURRENT_CRITICAL = doc["i_crit"]; prefs.putFloat("i_crit", CURRENT_CRITICAL); }
      prefs.end();

      SerialBT.println("{\"cmd\":\"config\",\"status\":\"saved\"}");
      Serial.println("JSON config saved! Restarting ESP32...");
      delay(500);
      ESP.restart();
    }
  }
  // ── Unknown command ──
  else {
    SerialBT.println("{\"cmd\":\"UNKNOWN\",\"msg\":\"Commands: WIFI_SET, "
                     "WIFI_STATUS, WIFI_CLEAR, READ, PING, CALIBRATE_ZERO or JSON config\"}");
  }
}

void sendBluetoothData() {
  if (!SerialBT.hasClient())
    return;

  StaticJsonDocument<384> doc;
  doc["connected"] = batteryConnected;
  doc["v"] = round2(currentVoltage);
  doc["i"] = round2(currentCurrent);
  doc["t"] = round1(currentTemperature);
  doc["p"] = round2(currentPower);
  doc["pct"] = batteryPercent;
  doc["time_left"] = round2(timeLeft);
  doc["health"] = batteryHealth;
  doc["capacity"] = batteryCapacity;
  doc["ts"] = millis();
  doc["wifi"] = wifiConnected;

  if (currentAlert != ALERT_NONE) {
    doc["alert"] = (currentAlert == ALERT_CRITICAL) ? "critical" : "warning";
    doc["alertMsg"] = alertMessage;
  }

  String json;
  serializeJson(doc, json);
  SerialBT.println(json);
}

// ─────────────────────────────────────────────────────────────
//  WIFI (Access Point Mode)
// ─────────────────────────────────────────────────────────────
void connectWiFi() {
  Serial.printf("WiFi AP: Starting network '%s'...\n", wifiSSID.c_str());

  // Set ESP32 as a WiFi Access Point (broadcasts its own network)
  WiFi.mode(WIFI_AP);
  WiFi.softAP(wifiSSID.c_str(), wifiPassword.c_str());

  wifiConnected = true;                   // AP is always active once started
  String ip = WiFi.softAPIP().toString(); // Default is usually 192.168.4.1

  Serial.printf("WiFi AP: Started successfully!\n");
  Serial.printf("         SSID: %s\n", wifiSSID.c_str());
  Serial.printf("         PASS: %s\n", wifiPassword.c_str());
  Serial.printf("         IP:   %s\n", ip.c_str());

  SerialBT.println("{\"cmd\":\"WIFI_CONNECTED\",\"ip\":\"" + ip + "\"}");
}

// ─── HTTP Handlers ───────────────────────────────────────────
void handleRoot() {
  String html =
      "<!DOCTYPE html><html><head><title>ESP32 Battery Monitor</title>";
  html +=
      "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:sans-serif;padding:20px;background:#1a1a2e;"
          "color:#eee;}";
  html += ".card{background:#16213e;padding:20px;border-radius:12px;margin:"
          "10px 0;}";
  html += ".val{font-size:2em;color:#00d4ff;font-weight:bold;}";
  html += ".v{color:#00ff00;}.i{color:#00d4ff;}.t{color:#ff6b6b;}.p{color:#"
          "ffd700;}";
  html +=
      ".bar{background:#333;border-radius:8px;height:30px;margin-top:10px;}";
  html += ".fill{background:linear-gradient(90deg,#ff0000,#ffa500,#00ff00);"
          "height:100%;border-radius:8px;}";
  html += "</style></head><body>";
  html += "<h1>&#9889; ESP32 Battery Monitor</h1>";
  html += "<div class='card'><h3>Voltage</h3><p class='val v'>" +
          String(currentVoltage, 2) + " V</p></div>";
  html += "<div class='card'><h3>Current</h3><p class='val i'>" +
          String(currentCurrent, 2) + " A</p></div>";
  html += "<div class='card'><h3>Power</h3><p class='val p'>" +
          String(currentPower, 2) + " W</p></div>";
  html += "<div class='card'><h3>Temperature</h3><p class='val t'>" +
          String(currentTemperature, 1) + " &deg;C</p></div>";
  html += "<div class='card'><h3>Battery: " + String(batteryPercent) + "%</h3>";
  html += "<div class='bar'><div class='fill' style='width:" +
          String(batteryPercent) + "%'></div></div></div>";
  if (currentAlert != ALERT_NONE) {
    html += "<div class='card' style='background:" +
            String(currentAlert == ALERT_CRITICAL ? "#8b0000" : "#8b4500") +
            "'>";
    html += "<h3>&#9888; " + alertMessage + "</h3></div>";
  }
  html += "<p style='color:#888;margin-top:20px;'>API endpoint: <a "
          "href='/data' style='color:#00d4ff;'>/data</a></p>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

void handleData() {
  StaticJsonDocument<512> doc;
  doc["connected"] = batteryConnected;
  doc["voltage"] = round2(currentVoltage);
  doc["current"] = round2(currentCurrent);
  doc["power"] = round2(currentPower);
  doc["temperature"] = round1(currentTemperature);
  doc["battery_pct"] = batteryPercent;
  doc["time_left"] = round2(timeLeft);
  doc["health"] = batteryHealth;
  doc["capacity"] = batteryCapacity;
  doc["timestamp"] = millis();
  doc["uptime_sec"] = millis() / 1000;

  if (currentAlert != ALERT_NONE) {
    doc["alert"] = (currentAlert == ALERT_CRITICAL) ? "critical" : "warning";
    doc["alertMsg"] = alertMessage;
  }

  String json;
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void handleNotFound() {
  server.send(404, "text/plain",
              "Not Found. Use /data for JSON or / for status page.");
}

// ─── Utility ─────────────────────────────────────────────────
float round2(float val) { return (int)(val * 100 + 0.5) / 100.0; }

float round1(float val) { return (int)(val * 10 + 0.5) / 10.0; }
