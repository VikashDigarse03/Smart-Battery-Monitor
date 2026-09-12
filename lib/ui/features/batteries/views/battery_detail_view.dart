import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../data/repositories/battery_repository.dart';
import '../../../../data/repositories/measurement_repository.dart';
import '../../../../domain/models/models.dart';
import '../../../core/theme.dart';

/// Shows battery details, current reading, measurement history, and lifecycle events.
class BatteryDetailView extends StatefulWidget {
  final int batteryDbId;

  const BatteryDetailView({super.key, required this.batteryDbId});

  @override
  State<BatteryDetailView> createState() => _BatteryDetailViewState();
}

class _BatteryDetailViewState extends State<BatteryDetailView> {
  Battery? _battery;
  List<Measurement> _measurements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final batteryRepo = context.read<BatteryRepository>();
    final measurementRepo = context.read<MeasurementRepository>();

    _battery = await batteryRepo.findById(widget.batteryDbId);
    if (_battery != null) {
      _measurements = await measurementRepo.getMeasurementsForBattery(
        _battery!.id!,
        limit: 50,
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_battery == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Battery Not Found')),
        body: const Center(child: Text('Battery not found in database.')),
      );
    }

    final battery = _battery!;
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(battery.batteryId),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Info & History'),
              Tab(text: 'Graphs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── TAB 1: Info & History ──
            RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _InfoCard(battery: battery),
                  const SizedBox(height: 16),
                  if (_measurements.isNotEmpty) ...[
                    Text(
                      'Latest Reading',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    _LatestReadingCard(measurement: _measurements.first),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    'Measurement History',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_measurements.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No measurements yet',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('V'), numeric: true),
                            DataColumn(label: Text('A'), numeric: true),
                            DataColumn(label: Text('°C'), numeric: true),
                            DataColumn(label: Text('SOC'), numeric: true),
                            DataColumn(label: Text('SOH'), numeric: true),
                          ],
                          rows: _measurements.map((m) {
                            return DataRow(cells: [
                              DataCell(
                                Text(
                                  dateFormat.format(m.measuredAt),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              DataCell(Text(
                                m.voltage.toStringAsFixed(2),
                                style: TextStyle(
                                  color: AppTheme.getVoltageColor(m.voltage),
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                              DataCell(Text(m.current.toStringAsFixed(2))),
                              DataCell(Text(m.temperature.toStringAsFixed(1))),
                              DataCell(Text('${m.batteryPercent ?? '-'}%')),
                              DataCell(Text('${m.batteryHealth ?? '-'}%')),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── TAB 2: Graphs ──
            _GraphsTab(measurements: _measurements),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/measure/${battery.id}'),
        icon: const Icon(Icons.speed_rounded),
        label: const Text('Measure Battery', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ));
  }
}

class _GraphsTab extends StatefulWidget {
  final List<Measurement> measurements;
  const _GraphsTab({required this.measurements});

  @override
  State<_GraphsTab> createState() => _GraphsTabState();
}

class _GraphsTabState extends State<_GraphsTab> {
  String _viewMode = 'separate'; // 'separate' or 'overlay'

  @override
  Widget build(BuildContext context) {
    if (widget.measurements.isEmpty) {
      return const Center(child: Text('No measurement data to plot.'));
    }

    // Sort chronologically for charts
    final sorted = List<Measurement>.from(widget.measurements)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('View Mode: '),
              DropdownButton<String>(
                value: _viewMode,
                items: const [
                  DropdownMenuItem(value: 'separate', child: Text('Separate Charts')),
                  DropdownMenuItem(value: 'overlay', child: Text('Overlay (Dual Axis)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _viewMode = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _viewMode == 'overlay'
                ? _buildOverlayChart(sorted)
                : _buildSeparateCharts(sorted),
          ),
        ],
      ),
    );
  }

  Widget _buildSeparateCharts(List<Measurement> data) {
    return Column(
      children: [
        Expanded(
          child: _ChartCard(
            title: 'Voltage (V)',
            color: Colors.blue,
            data: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.voltage)).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _ChartCard(
            title: 'Current (A)',
            color: Colors.red,
            data: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.current)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayChart(List<Measurement> data) {
    return _ChartCardOverlay(
      title: 'Voltage & Current Overlay',
      voltageData: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.voltage)).toList(),
      currentData: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.current)).toList(),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<FlSpot> data;

  const _ChartCard({required this.title, required this.color, required this.data});

  @override
  Widget build(BuildContext context) {
    double minX = data.first.x;
    double maxX = data.last.x;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == minX || value == maxX) return const SizedBox.shrink();
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(DateFormat('HH:mm').format(date), style: const TextStyle(fontSize: 10)),
                          );
                        },
                        reservedSize: 24,
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCardOverlay extends StatelessWidget {
  final String title;
  final List<FlSpot> voltageData;
  final List<FlSpot> currentData;

  const _ChartCardOverlay({required this.title, required this.voltageData, required this.currentData});

  @override
  Widget build(BuildContext context) {
    if (voltageData.isEmpty) return const SizedBox.shrink();
    
    double minX = voltageData.first.x;
    double maxX = voltageData.last.x;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Row(
              children: [
                Icon(Icons.circle, color: Colors.blue, size: 12),
                SizedBox(width: 4),
                Text('Voltage (V)'),
                SizedBox(width: 16),
                Icon(Icons.circle, color: Colors.red, size: 12),
                SizedBox(width: 4),
                Text('Current (A)'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  lineBarsData: [
                    LineChartBarData(
                      spots: voltageData,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: currentData,
                      isCurved: true,
                      color: Colors.red,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == minX || value == maxX) return const SizedBox.shrink();
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(DateFormat('HH:mm').format(date), style: const TextStyle(fontSize: 10)),
                          );
                        },
                        reservedSize: 24,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Battery battery;
  const _InfoCard({required this.battery});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    battery.status.displayName,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  battery.batteryId,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.location_on_outlined, 'Location',
                battery.locationString),
            if (battery.serialNumber != null)
              _infoRow(Icons.tag, 'Serial Number', battery.serialNumber!),
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (battery.status) {
      case BatteryStatus.active:
        return AppTheme.statusGood;
      case BatteryStatus.inactive:
        return AppTheme.statusInactive;
      case BatteryStatus.underMaintenance:
        return AppTheme.statusWarning;
      case BatteryStatus.retired:
      case BatteryStatus.removed:
        return AppTheme.statusCritical;
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestReadingCard extends StatelessWidget {
  final Measurement measurement;
  const _LatestReadingCard({required this.measurement});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ReadingChip(
              label: 'Voltage',
              value: '${measurement.voltage.toStringAsFixed(2)} V',
              color: AppTheme.voltageColor,
              icon: Icons.bolt,
            ),
            _ReadingChip(
              label: 'Current',
              value: '${measurement.current.toStringAsFixed(2)} A',
              color: AppTheme.currentColor,
              icon: Icons.electric_bolt,
            ),
            _ReadingChip(
              label: 'Temp',
              value: '${measurement.temperature.toStringAsFixed(1)} °C',
              color: AppTheme.temperatureColor,
              icon: Icons.thermostat,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _ReadingChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
