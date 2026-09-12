import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/battery_repository.dart';
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
        actions: [
          if (_rack != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Rack',
              onPressed: _showEditRackDialog,
            ),
        ],
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
                        : () => _showAddBatteryDialog(pos['position_id'] as int, posNumber),
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

  Future<void> _showEditRackDialog() async {
    if (_rack == null) return;
    
    final countController = TextEditingController(text: '${_rack!.positionCount}');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Rack'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: countController,
                decoration: const InputDecoration(
                  labelText: 'Number of positions',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    
    if (result == true && mounted) {
      final newCount = int.tryParse(countController.text);
      if (newCount == null || newCount < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid position count')),
        );
        return;
      }
      
      try {
        final repo = context.read<LocationRepository>();
        await repo.updateRackPositionCount(widget.rackId, newCount);
        _loadData(); // reload data
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating rack: $e')),
          );
        }
      }
    }
  }

  Future<void> _showAddBatteryDialog(int positionId, int posNumber) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddBatteryDialog(positionId: positionId, posNumber: posNumber),
    );
    if (result == true) {
      _loadData();
    }
  }
}

class _AddBatteryDialog extends StatefulWidget {
  final int positionId;
  final int posNumber;
  const _AddBatteryDialog({required this.positionId, required this.posNumber});

  @override
  State<_AddBatteryDialog> createState() => _AddBatteryDialogState();
}

class _AddBatteryDialogState extends State<_AddBatteryDialog> {
  final _serialController = TextEditingController();
  bool _isSaving = false;
  String _batteryId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initBatteryId();
  }

  Future<void> _initBatteryId() async {
    final repo = context.read<BatteryRepository>();
    _batteryId = await repo.peekNextBatteryId();
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final repo = context.read<BatteryRepository>();
      final finalBatteryId = await repo.generateNextBatteryId();
      final now = DateTime.now();

      final battery = Battery(
        batteryId: finalBatteryId,
        serialNumber: _serialController.text.isEmpty ? null : _serialController.text.trim(),
        currentPositionId: widget.positionId,
        installationDate: now,
        createdAt: now,
        updatedAt: now,
      );

      final id = await repo.insertBattery(battery);
      await repo.assignToPosition(id, widget.positionId);
      
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
    }
    
    return AlertDialog(
      title: Text('Add Battery to Pos ${widget.posNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Battery ID: $_batteryId', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _serialController,
            decoration: InputDecoration(
              labelText: 'Serial Number',
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () async {
                  final result = await context.pushNamed('scan-battery');
                  if (result != null && result is String) {
                    _serialController.text = result;
                  }
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
