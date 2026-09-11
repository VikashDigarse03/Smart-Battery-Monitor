import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'data/database/app_database.dart';
import 'data/repositories/battery_repository.dart';
import 'data/repositories/device_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/measurement_repository.dart';
import 'data/services/esp32_service.dart';
import 'ui/core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database
  final appDatabase = AppDatabase();
  await appDatabase.database; // Trigger creation

  // Load ESP32 IP from settings
  final esp32Ip = await appDatabase.getSetting('esp32_ip_address') ?? '192.168.4.1';

  runApp(
    MultiProvider(
      providers: [
        // Database
        Provider<AppDatabase>.value(value: appDatabase),

        // Repositories
        Provider<BatteryRepository>(
          create: (_) => BatteryRepository(appDatabase),
        ),
        Provider<MeasurementRepository>(
          create: (_) => MeasurementRepository(appDatabase),
        ),
        Provider<LocationRepository>(
          create: (_) => LocationRepository(appDatabase),
        ),
        Provider<DeviceRepository>(
          create: (_) => DeviceRepository(appDatabase),
        ),

        // Services
        Provider<Esp32WifiService>(
          create: (_) => Esp32WifiService(ipAddress: esp32Ip),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<Esp32BluetoothService>(
          create: (_) => Esp32BluetoothService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: const BatteryMonitorApp(),
    ),
  );
}

class BatteryMonitorApp extends StatelessWidget {
  const BatteryMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Battery Monitor',
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
