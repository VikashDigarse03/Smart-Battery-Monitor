import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../../data/repositories/battery_repository.dart';
import '../../../../data/repositories/measurement_repository.dart';
import '../../../../data/repositories/location_repository.dart';
import '../view_models/dashboard_view_model.dart';
import 'package:go_router/go_router.dart';

/// Main dashboard — overview of the battery monitoring system.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel(
      batteryRepo: context.read<BatteryRepository>(),
      measurementRepo: context.read<MeasurementRepository>(),
      locationRepo: context.read<LocationRepository>(),
    );
    _viewModel.loadDashboardData();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'Reports',
            onPressed: () => context.pushNamed('reports'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _viewModel.loadDashboardData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Summary Cards ──
                _buildSummaryGrid(),
                const SizedBox(height: 20),

                // ── Quick Actions ──
                _buildQuickActions(),
                const SizedBox(height: 20),

                // ── Room Status ──
                _buildSectionHeader('Room Status'),
                const SizedBox(height: 8),
                ..._buildRoomStatusCards(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _SummaryCard(
          title: 'Total Batteries',
          value: '${_viewModel.totalBatteries}',
          icon: Icons.battery_full_rounded,
          color: AppTheme.primary,
        ),
        _SummaryCard(
          title: 'Measured Today',
          value: '${_viewModel.measuredToday}',
          icon: Icons.speed_rounded,
          color: AppTheme.statusInfo,
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Scan Battery',
            color: AppTheme.primary,
            onTap: () => context.pushNamed('scan-battery'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.add_circle_outline,
            label: 'Add Battery',
            color: AppTheme.secondary,
            onTap: () => context.pushNamed('add-battery'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.assessment_outlined,
            label: 'Reports',
            color: AppTheme.statusInfo,
            onTap: () => context.pushNamed('reports'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }

  List<Widget> _buildRoomStatusCards() {
    if (_viewModel.rooms.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 48,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No rooms configured yet',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return _viewModel.rooms.map((room) {
      return Card(
        child: ListTile(
          leading: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppTheme.statusGood,
              shape: BoxShape.circle,
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
    }).toList();
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
