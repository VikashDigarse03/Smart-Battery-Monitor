# Smart Battery Monitor 🔋

A Flutter application designed to monitor battery health, voltage, current, and temperature in real-time by interfacing with an ESP32 microcontroller. 

## Features ✨

- **Real-time Monitoring:** View battery voltage, current (via ACS712 sensor), and temperature.
- **Dual Connectivity:** Connect seamlessly to your ESP32 device via Bluetooth or WiFi.
- **Advanced Sensor Calibration:**
  - **Auto-Calibrate:** Zero out idle ADC noise via Bluetooth when no battery is connected.
  - **Manual Offsets:** Fine-tune voltage, current, and temperature offsets to ensure precise readings.
- **Battery Capacity Tracking:** Monitor Amp-hours (Ah) and state of charge.
- **Customizable Thresholds:** Set warning and critical thresholds for voltage, current, and temperature.
- **Dashboard & Reports:** An intuitive dashboard for quick actions and a reports screen for data analysis.

## Getting Started 🚀

### Prerequisites
- Flutter SDK (latest version recommended)
- An ESP32 microcontroller set up with the corresponding battery monitoring firmware.
- Bluetooth or WiFi enabled on your mobile device.

### Installation

1. Clone the repository:
   ```bash
   git clone <your-repo-url>
   ```
2. Navigate to the project directory:
   ```bash
   cd flutter_application_1
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Hardware Configuration ⚙️

The app expects to communicate with an ESP32. Ensure your ESP32 is configured to send telemetry data (Voltage, Current, Temperature). 
You can adjust the hardware-specific settings directly within the app's **Settings** page:
- Voltage divider ratios
- ACS712 sensitivity
- Zero offsets for all sensors

## License
This project is open-source and available under the MIT License.
