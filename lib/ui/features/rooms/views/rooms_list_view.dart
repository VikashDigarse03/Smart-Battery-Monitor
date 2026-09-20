import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Lists all battery rooms with options to add, rename, and archive.
class RoomsListView extends StatefulWidget {
  const RoomsListView({super.key});

  @override
  State<RoomsListView> createState() => _RoomsListViewState();
}

class _RoomsListViewState extends State<RoomsListView> {
  List<Room> _rooms = [];
  List<Room> _archivedRooms = [];
  bool _isLoading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    final repo = context.read<LocationRepository>();
    _rooms = await repo.getAllRooms();
    _archivedRooms = await repo.getArchivedRooms();
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

  Future<void> _renameRoom(Room room) async {
    final nameController = TextEditingController(text: room.name);
    final descController = TextEditingController(text: room.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Room'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final repo = context.read<LocationRepository>();
      await repo.updateRoom(
        room.id!,
        nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
      _loadRooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Room renamed successfully'),
            backgroundColor: AppTheme.statusGood,
          ),
        );
      }
    }
  }

  Future<void> _archiveRoom(Room room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Room?'),
        content: Text(
          'Are you sure you want to archive "${room.name}"?\n\n'
          'The room and its racks will be hidden but can be restored later from the archived section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusWarning),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repo = context.read<LocationRepository>();
      await repo.archiveRoom(room.id!);
      _loadRooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${room.name}" archived'),
            backgroundColor: AppTheme.statusInfo,
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () async {
                await repo.unarchiveRoom(room.id!);
                _loadRooms();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _unarchiveRoom(Room room) async {
    final repo = context.read<LocationRepository>();
    await repo.unarchiveRoom(room.id!);
    _loadRooms();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${room.name}" restored'),
          backgroundColor: AppTheme.statusGood,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Rooms'),
        actions: [
          if (_archivedRooms.isNotEmpty)
            IconButton(
              icon: Icon(
                _showArchived ? Icons.visibility_off_outlined : Icons.inventory_2_outlined,
                color: _showArchived ? AppTheme.primary : AppTheme.textMuted,
              ),
              tooltip: _showArchived ? 'Hide Archived' : 'Show Archived (${_archivedRooms.length})',
              onPressed: () => setState(() => _showArchived = !_showArchived),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty && !_showArchived
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
                      Text(
                        'Add a room to get started',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRooms,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Active Rooms ──
                      ..._rooms.map((room) => _buildRoomCard(room, isArchived: false)),

                      // ── Archived Rooms Section ──
                      if (_showArchived && _archivedRooms.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 18, color: AppTheme.textMuted),
                            const SizedBox(width: 8),
                            Text(
                              'Archived Rooms (${_archivedRooms.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._archivedRooms.map((room) => _buildRoomCard(room, isArchived: true)),
                      ],

                      // FAB clearance
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRoom,
        icon: const Icon(Icons.add),
        label: const Text('Add Room'),
      ),
    );
  }

  Widget _buildRoomCard(Room room, {required bool isArchived}) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isArchived
                ? AppTheme.textMuted.withValues(alpha: 0.1)
                : AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isArchived ? Icons.inventory_2_outlined : Icons.meeting_room_rounded,
            color: isArchived ? AppTheme.textMuted : AppTheme.primary,
          ),
        ),
        title: Text(
          room.name,
          style: TextStyle(
            color: isArchived ? AppTheme.textMuted : AppTheme.textPrimary,
            decoration: isArchived ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(room.description ?? 'Battery room'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
          onSelected: (value) {
            switch (value) {
              case 'rename':
                _renameRoom(room);
              case 'archive':
                _archiveRoom(room);
              case 'restore':
                _unarchiveRoom(room);
              case 'open':
                context.pushNamed(
                  'room-detail',
                  pathParameters: {'roomId': '${room.id}'},
                );
            }
          },
          itemBuilder: (ctx) => [
            if (!isArchived) ...[
              const PopupMenuItem(value: 'open', child: _PopupItem(icon: Icons.open_in_new, label: 'Open')),
              const PopupMenuItem(value: 'rename', child: _PopupItem(icon: Icons.edit_outlined, label: 'Rename')),
              const PopupMenuItem(value: 'archive', child: _PopupItem(icon: Icons.inventory_2_outlined, label: 'Archive')),
            ] else ...[
              const PopupMenuItem(value: 'restore', child: _PopupItem(icon: Icons.restore, label: 'Restore')),
            ],
          ],
        ),
        onTap: isArchived
            ? null
            : () => context.pushNamed(
                  'room-detail',
                  pathParameters: {'roomId': '${room.id}'},
                ),
      ),
    );
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PopupItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
