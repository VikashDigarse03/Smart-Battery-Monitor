import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Shows racks within a room with option to add new racks.
class RoomDetailView extends StatefulWidget {
  final int roomId;

  const RoomDetailView({super.key, required this.roomId});

  @override
  State<RoomDetailView> createState() => _RoomDetailViewState();
}

class _RoomDetailViewState extends State<RoomDetailView> {
  Room? _room;
  List<Rack> _racks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final repo = context.read<LocationRepository>();
    _room = await repo.getRoomById(widget.roomId);
    _racks = await repo.getRacksForRoom(widget.roomId);
    setState(() => _isLoading = false);
  }

  Future<void> _addRack() async {
    final nameController = TextEditingController();
    final posCountController = TextEditingController(text: '20');
    final batteryTypeController = TextEditingController(text: 'Lead Acid');
    final voltageController = TextEditingController(text: '12.0');
    final capacityController = TextEditingController(text: '100.0');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Rack'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Rack Name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: posCountController,
                decoration:
                    const InputDecoration(labelText: 'Number of Positions (Slots)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: batteryTypeController,
                decoration: const InputDecoration(labelText: 'Battery Type'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: voltageController,
                decoration: const InputDecoration(labelText: 'Nominal Voltage (V)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capacityController,
                decoration: const InputDecoration(labelText: 'Capacity (Ah)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final repo = context.read<LocationRepository>();
      await repo.insertRack(
        widget.roomId,
        nameController.text.trim(),
        positionCount: int.tryParse(posCountController.text) ?? 20,
        batteryType: batteryTypeController.text.trim(),
        nominalVoltage: double.tryParse(voltageController.text) ?? 12.0,
        capacityAh: double.tryParse(capacityController.text) ?? 100.0,
      );
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_room?.name ?? 'Room'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Rack',
            onPressed: _addRack,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _racks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.view_column_outlined,
                        size: 64,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No racks in this room',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _addRack,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Rack'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _racks.length,
                    itemBuilder: (context, index) {
                      final rack = _racks[index];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.view_column_rounded,
                              color: AppTheme.secondary,
                            ),
                          ),
                          title: Text(rack.name),
                          subtitle:
                              Text('${rack.positionCount} positions'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.pushNamed(
                            'rack-detail',
                            pathParameters: {
                              'roomId': '${widget.roomId}',
                              'rackId': '${rack.id}',
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
