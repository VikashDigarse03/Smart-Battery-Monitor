import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/battery_repository.dart';
import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Form to add a new battery with auto-generated ID and location assignment.
class AddBatteryView extends StatefulWidget {
  const AddBatteryView({super.key});

  @override
  State<AddBatteryView> createState() => _AddBatteryViewState();
}

class _AddBatteryViewState extends State<AddBatteryView> {
  final _formKey = GlobalKey<FormState>();
  String _batteryId = '';
  final _manufacturerController = TextEditingController();
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _capacityController = TextEditingController(text: '100');

  List<Room> _rooms = [];
  List<Rack> _racks = [];
  List<RackPosition> _positions = [];

  Room? _selectedRoom;
  Rack? _selectedRack;
  RackPosition? _selectedPosition;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final batteryRepo = context.read<BatteryRepository>();
    final locationRepo = context.read<LocationRepository>();

    _batteryId = await batteryRepo.generateNextBatteryId();
    _rooms = await locationRepo.getAllRooms();

    setState(() => _isLoading = false);
  }

  Future<void> _onRoomChanged(Room? room) async {
    setState(() {
      _selectedRoom = room;
      _selectedRack = null;
      _selectedPosition = null;
      _racks = [];
      _positions = [];
    });

    if (room != null) {
      final repo = context.read<LocationRepository>();
      _racks = await repo.getRacksForRoom(room.id!);
      setState(() {});
    }
  }

  Future<void> _onRackChanged(Rack? rack) async {
    setState(() {
      _selectedRack = rack;
      _selectedPosition = null;
      _positions = [];
    });

    if (rack != null) {
      final repo = context.read<LocationRepository>();
      _positions = await repo.getPositionsForRack(rack.id!);
      setState(() {});
    }
  }

  Future<void> _saveBattery() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final batteryRepo = context.read<BatteryRepository>();
      final now = DateTime.now();

      final battery = Battery(
        batteryId: _batteryId,
        manufacturer: _manufacturerController.text.isEmpty
            ? null
            : _manufacturerController.text.trim(),
        model: _modelController.text.isEmpty
            ? null
            : _modelController.text.trim(),
        serialNumber: _serialController.text.isEmpty
            ? null
            : _serialController.text.trim(),
        capacityAh: double.tryParse(_capacityController.text),
        currentPositionId: _selectedPosition?.id,
        installationDate: now,
        createdAt: now,
        updatedAt: now,
      );

      final id = await batteryRepo.insertBattery(battery);

      // Create assignment if position selected
      if (_selectedPosition != null) {
        await batteryRepo.assignToPosition(id, _selectedPosition!.id!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Battery $_batteryId added successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _manufacturerController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Battery')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Battery ID (auto-generated, read-only)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Battery ID',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          _batteryId,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Optional fields
            TextFormField(
              controller: _manufacturerController,
              decoration: const InputDecoration(labelText: 'Manufacturer'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialController,
              decoration: const InputDecoration(labelText: 'Serial Number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityController,
              decoration:
                  const InputDecoration(labelText: 'Capacity (Ah)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            // Location assignment
            Text(
              'Location Assignment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<Room>(
              initialValue: _selectedRoom,
              decoration: const InputDecoration(labelText: 'Room'),
              items: _rooms
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: _onRoomChanged,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<Rack>(
              initialValue: _selectedRack,
              decoration: const InputDecoration(labelText: 'Rack'),
              items: _racks
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: _onRackChanged,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<RackPosition>(
              initialValue: _selectedPosition,
              decoration: const InputDecoration(labelText: 'Position'),
              items: _positions
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text('Position ${p.positionNumber}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedPosition = v),
            ),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveBattery,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Battery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
