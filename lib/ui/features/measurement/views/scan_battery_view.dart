import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/battery_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Full-screen QR/barcode scanner to identify a battery.
///
/// Scans → extracts Battery ID (e.g., BAT-000123) → looks up in database.
/// If found, navigates to the measurement screen.
/// If not found, offers to add a new battery.
class ScanBatteryView extends StatefulWidget {
  const ScanBatteryView({super.key});

  @override
  State<ScanBatteryView> createState() => _ScanBatteryViewState();
}

class _ScanBatteryViewState extends State<ScanBatteryView> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;
  String? _lastScanned;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final scannedValue = barcode.rawValue!.trim();

    // Prevent duplicate processing
    if (scannedValue == _lastScanned) return;
    _lastScanned = scannedValue;

    setState(() => _isProcessing = true);

    try {
      final batteryRepo = context.read<BatteryRepository>();
      final battery = await batteryRepo.findByBatteryId(scannedValue);

      if (!mounted) return;

      if (battery != null) {
        // Battery found → go to measurement
        _showBatteryFound(battery);
      } else {
        // Battery not found
        _showBatteryNotFound(scannedValue);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showBatteryFound(Battery battery) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              color: AppTheme.statusGood,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Battery Found',
              style: Theme.of(ctx).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              battery.batteryId,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              battery.locationString,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/battery/${battery.id}');
                    },
                    child: const Text('View Details'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/measure/${battery.id}');
                    },
                    icon: const Icon(Icons.speed),
                    label: const Text('Measure'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ).then((_) => _lastScanned = null);
  }

  void _showBatteryNotFound(String scannedValue) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.statusWarning,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Battery Not Found',
              style: Theme.of(ctx).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '"$scannedValue"',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _lastScanned = null;
                    },
                    child: const Text('Scan Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.pushNamed('add-battery');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Battery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ).then((_) => _lastScanned = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Battery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),

          // Overlay with scanning frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Bottom instructions
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point at battery QR code',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),

          // Loading indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
