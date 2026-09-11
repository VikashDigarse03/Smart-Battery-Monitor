import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Lists all battery rooms with options to add new ones.
class RoomsListView extends StatefulWidget {
  const RoomsListView({super.key});

  @override
  State<RoomsListView> createState() => _RoomsListViewState();
}

class _RoomsListViewState extends State<RoomsListView> {
  List<Room> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    final repo = context.read<LocationRepository>();
    _rooms = await repo.getAllRooms();
    setState(() => _isLoading = false);
  }

  Future<void> _addRoom() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Room Name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
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
      await repo.insertRoom(
        nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
      _loadRooms();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Rooms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Room',
            onPressed: _addRoom,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 64,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No rooms yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _addRoom,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Room'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRooms,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.meeting_room_rounded,
                              color: AppTheme.primary,
                            ),
                          ),
                          title: Text(room.name),
                          subtitle: Text(room.description ?? 'Battery room'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.pushNamed(
                            'room-detail',
                            pathParameters: {'roomId': '${room.id}'},
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
