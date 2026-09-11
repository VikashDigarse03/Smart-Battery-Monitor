import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Shows a visual grid of rack positions with battery occupancy status.
class RackDetailView extends StatefulWidget {
  final int rackId;

  const RackDetailView({super.key, required this.rackId});

  @override
  State<RackDetailView> createState() => _RackDetailViewState();
}

class _RackDetailViewState extends State<RackDetailView> {
  Rack? _rack;
  List<Map<String, dynamic>> _positions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final repo = context.read<LocationRepository>();
    _rack = await repo.getRackById(widget.rackId);
    _positions = await repo.getPositionsWithBatteries(widget.rackId);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_rack?.name ?? 'Rack'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: _positions.length,
                itemBuilder: (context, index) {
                  final pos = _positions[index];
                  final posNumber = pos['position_number'] as int;
                  final batteryCode = pos['battery_code'] as String?;
                  final batteryDbId = pos['battery_db_id'] as int?;
                  final latestVoltage =
                      (pos['latest_voltage'] as num?)?.toDouble();
                  final hasOccupant = batteryCode != null;

                  Color statusColor;
                  if (!hasOccupant) {
                    statusColor = AppTheme.textMuted;
                  } else if (latestVoltage != null && latestVoltage < 11.5) {
                    statusColor = AppTheme.statusCritical;
                  } else if (latestVoltage != null && latestVoltage < 12.0) {
                    statusColor = AppTheme.statusWarning;
                  } else {
                    statusColor = AppTheme.statusGood;
                  }

                  return GestureDetector(
                    onTap: hasOccupant
                        ? () => context.push('/battery/$batteryDbId')
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: hasOccupant
                            ? statusColor.withValues(alpha: 0.1)
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasOccupant ? statusColor : AppTheme.border,
                          width: hasOccupant ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$posNumber',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (hasOccupant) ...[
                            Icon(
                              Icons.battery_std,
                              size: 20,
                              color: statusColor,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              batteryCode.replaceFirst('BAT-', ''),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (latestVoltage != null)
                              Text(
                                '${latestVoltage.toStringAsFixed(1)}V',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                          ] else ...[
                            Icon(
                              Icons.remove,
                              size: 20,
                              color: AppTheme.textMuted,
                            ),
                            const Text(
                              'Empty',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
