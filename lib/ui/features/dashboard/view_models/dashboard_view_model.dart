import 'package:flutter/material.dart';

import '../../../../data/repositories/battery_repository.dart';
import '../../../../data/repositories/measurement_repository.dart';
import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';

/// ViewModel for the Dashboard screen.
class DashboardViewModel extends ChangeNotifier {
  final BatteryRepository batteryRepo;
  final MeasurementRepository measurementRepo;
  final LocationRepository locationRepo;

  DashboardViewModel({
    required this.batteryRepo,
    required this.measurementRepo,
    required this.locationRepo,
  });

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  int _totalBatteries = 0;
  int get totalBatteries => _totalBatteries;

  int _activeBatteries = 0;
  int get activeBatteries => _activeBatteries;

  int _retiredBatteries = 0;
  int get retiredBatteries => _retiredBatteries;

  int _measuredToday = 0;
  int get measuredToday => _measuredToday;

  List<Room> _rooms = [];
  List<Room> get rooms => _rooms;

  Future<void> loadDashboardData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load battery counts
      final counts = await batteryRepo.getBatteryCounts();
      _totalBatteries = counts['total'] ?? 0;
      _activeBatteries = counts['active'] ?? 0;
      _retiredBatteries = counts['retired'] ?? 0;

      // Load today's measurement count
      _measuredToday = await measurementRepo.getMeasurementsCountToday();

      // Load rooms
      _rooms = await locationRepo.getAllRooms();
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
