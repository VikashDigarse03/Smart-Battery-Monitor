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

  Future<void> _showRenameDialog() async {
    if (_battery == null) return;
    final controller = TextEditingController(text: _battery!.batteryId);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Battery'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Battery Name / ID',
            hintText: 'e.g. BAT-000001 or Main UPS',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty && result.trim() != _battery!.batteryId) {
      final repo = context.read<BatteryRepository>();
      await repo.updateBatteryName(_battery!.id!, result.trim());
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Battery renamed successfully'),
            backgroundColor: AppTheme.statusGood,
          ),
        );
      }
    }
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
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename Battery',
              onPressed: _showRenameDialog,
            ),
          ],
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

// ═══════════════════════════════════════════════════════════════
//  GRAPHS TAB — Enhanced with gradients, tooltips, thresholds
// ═══════════════════════════════════════════════════════════════

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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded, size: 64, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              'No measurement data to plot',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    // Sort chronologically for charts
    final sorted = List<Measurement>.from(widget.measurements)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── View Mode Switcher ──
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _viewMode = 'separate'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _viewMode == 'separate'
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        border: _viewMode == 'separate'
                            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.3))
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.view_agenda_outlined, size: 16,
                              color: _viewMode == 'separate' ? AppTheme.primary : AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text('Separate',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _viewMode == 'separate' ? AppTheme.primary : AppTheme.textMuted,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _viewMode = 'overlay'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _viewMode == 'overlay'
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        border: _viewMode == 'overlay'
                            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.3))
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.layers_outlined, size: 16,
                              color: _viewMode == 'overlay' ? AppTheme.primary : AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text('Overlay',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _viewMode == 'overlay' ? AppTheme.primary : AppTheme.textMuted,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    return ListView(
      children: [
        SizedBox(
          height: 220,
          child: _EnhancedChartCard(
            title: 'Voltage',
            unit: 'V',
            color: AppTheme.voltageColor,
            gradientColors: [AppTheme.voltageColor, AppTheme.voltageColor.withValues(alpha: 0.0)],
            data: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.voltage)).toList(),
            thresholdLines: [
              _ThresholdLine(value: 10.5, color: AppTheme.statusCritical, label: 'Critical'),
              _ThresholdLine(value: 11.5, color: AppTheme.statusWarning, label: 'Warning'),
              _ThresholdLine(value: 12.7, color: AppTheme.statusGood, label: 'Full'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: _EnhancedChartCard(
            title: 'Current',
            unit: 'A',
            color: AppTheme.currentColor,
            gradientColors: [AppTheme.currentColor, AppTheme.currentColor.withValues(alpha: 0.0)],
            data: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.current)).toList(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: _EnhancedChartCard(
            title: 'Temperature',
            unit: '°C',
            color: AppTheme.temperatureColor,
            gradientColors: [AppTheme.temperatureColor, AppTheme.temperatureColor.withValues(alpha: 0.0)],
            data: data.map((m) => FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.temperature)).toList(),
            thresholdLines: [
              _ThresholdLine(value: 45.0, color: AppTheme.statusWarning, label: '45°C'),
              _ThresholdLine(value: 55.0, color: AppTheme.statusCritical, label: '55°C'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: _EnhancedChartCard(
            title: 'State of Charge',
            unit: '%',
            color: AppTheme.socColor,
            gradientColors: [AppTheme.socColor, AppTheme.socColor.withValues(alpha: 0.0)],
            data: data.map((m) => FlSpot(
              m.measuredAt.millisecondsSinceEpoch.toDouble(),
              (m.batteryPercent ?? 0).toDouble(),
            )).toList(),
            minY: 0,
            maxY: 100,
          ),
        ),
        const SizedBox(height: 80), // FAB clearance
      ],
    );
  }

  Widget _buildOverlayChart(List<Measurement> data) {
    return ListView(
      children: [
        SizedBox(
          height: 350,
          child: _EnhancedOverlayChart(data: data),
        ),
        const SizedBox(height: 80), // FAB clearance
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ENHANCED CHART CARD — Gradient fill, tooltips, thresholds
// ═══════════════════════════════════════════════════════════════

class _ThresholdLine {
  final double value;
  final Color color;
  final String label;
  const _ThresholdLine({required this.value, required this.color, required this.label});
}

class _EnhancedChartCard extends StatelessWidget {
  final String title;
  final String unit;
  final Color color;
  final List<Color> gradientColors;
  final List<FlSpot> data;
  final List<_ThresholdLine> thresholdLines;
  final double? minY;
  final double? maxY;

  const _EnhancedChartCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.gradientColors,
    required this.data,
    this.thresholdLines = const [],
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    double chartMinX = data.first.x;
    double chartMaxX = data.last.x;

    // Calculate Y bounds with padding
    double dataMinY = data.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double dataMaxY = data.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    
    // Include threshold lines in Y range
    for (final tl in thresholdLines) {
      if (tl.value < dataMinY) dataMinY = tl.value;
      if (tl.value > dataMaxY) dataMaxY = tl.value;
    }
    
    double yPadding = (dataMaxY - dataMinY) * 0.1;
    if (yPadding == 0) yPadding = 1;
    double chartMinY = minY ?? (dataMinY - yPadding);
    double chartMaxY = maxY ?? (dataMaxY + yPadding);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                )),
                const Spacer(),
                // Current value badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${data.last.y.toStringAsFixed(1)} $unit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: chartMinX,
                  maxX: chartMaxX,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipColor: (_) => AppTheme.cardBgLight,
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                          return LineTooltipItem(
                            '${spot.y.toStringAsFixed(2)} $unit',
                            TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(
                                text: '\n${DateFormat('dd MMM HH:mm').format(date)}',
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.normal,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: thresholdLines.map((tl) {
                      return HorizontalLine(
                        y: tl.value,
                        color: tl.color.withValues(alpha: 0.4),
                        strokeWidth: 1,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          style: TextStyle(
                            fontSize: 9,
                            color: tl.color.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                          labelResolver: (_) => tl.label,
                        ),
                      );
                    }).toList(),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: color,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: data.length <= 15,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: color,
                              strokeWidth: 1.5,
                              strokeColor: AppTheme.cardBg,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.25),
                            color.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          if (value == chartMinX || value == chartMaxX) {
                            return const SizedBox.shrink();
                          }
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('HH:mm').format(date),
                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          if (value == chartMinY || value == chartMaxY) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            value.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: null,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppTheme.border.withValues(alpha: 0.3),
                      strokeWidth: 0.5,
                      dashArray: [4, 4],
                    ),
                  ),
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

// ═══════════════════════════════════════════════════════════════
//  ENHANCED OVERLAY CHART — Dual-axis with proper labeling
// ═══════════════════════════════════════════════════════════════

class _EnhancedOverlayChart extends StatelessWidget {
  final List<Measurement> data;
  const _EnhancedOverlayChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    double minV = data.map((m) => m.voltage).reduce((a, b) => a < b ? a : b);
    double maxV = data.map((m) => m.voltage).reduce((a, b) => a > b ? a : b);
    double minI = data.map((m) => m.current).reduce((a, b) => a < b ? a : b);
    double maxI = data.map((m) => m.current).reduce((a, b) => a > b ? a : b);

    // Add padding to scales and avoid zero-range
    double vRange = maxV - minV;
    if (vRange == 0) { maxV += 1; minV -= 1; vRange = 2; }
    double iRange = maxI - minI;
    if (iRange == 0) { maxI += 1; minI -= 1; iRange = 2; }

    // Pad by 10% on top and bottom
    minV -= vRange * 0.1;
    maxV += vRange * 0.1;
    vRange = maxV - minV;

    minI -= iRange * 0.1;
    maxI += iRange * 0.1;
    iRange = maxI - minI;

    final voltageData = data.map((m) =>
        FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), m.voltage)).toList();
        
    // Map current to voltage scale for overlap
    final currentData = data.map((m) {
      double mappedI = minV + ((m.current - minI) / iRange) * vRange;
      return FlSpot(m.measuredAt.millisecondsSinceEpoch.toDouble(), mappedI);
    }).toList();

    double minX = voltageData.first.x;
    double maxX = voltageData.last.x;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title + Legend
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Voltage & Current', style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                )),
                Wrap(
                  spacing: 12,
                  children: [
                    _LegendChip(color: AppTheme.voltageColor, label: 'Voltage (V)'),
                    _LegendChip(color: AppTheme.currentColor, label: 'Current (A)'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minV,
                  maxY: maxV,
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipColor: (_) => AppTheme.cardBgLight,
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      getTooltipItems: (spots) {
                        return spots.asMap().entries.map((entry) {
                          final spot = entry.value;
                          final isVoltage = entry.key == 0;
                          final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                          final unit = isVoltage ? 'V' : 'A';
                          final clr = isVoltage ? AppTheme.voltageColor : AppTheme.currentColor;
                          
                          double displayValue = spot.y;
                          if (!isVoltage) {
                            // Reverse map back to actual current
                            displayValue = minI + ((spot.y - minV) / vRange) * iRange;
                          }
                          
                          return LineTooltipItem(
                            '${displayValue.toStringAsFixed(2)} $unit',
                            TextStyle(color: clr, fontWeight: FontWeight.bold, fontSize: 13),
                            children: isVoltage
                                ? [
                                    TextSpan(
                                      text: '\n${DateFormat('dd MMM HH:mm').format(date)}',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontWeight: FontWeight.normal,
                                        fontSize: 10,
                                      ),
                                    )
                                  ]
                                : null,
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: voltageData,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: AppTheme.voltageColor,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: data.length <= 15,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: AppTheme.voltageColor,
                              strokeWidth: 1.5,
                              strokeColor: AppTheme.cardBg,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.voltageColor.withValues(alpha: 0.15),
                            AppTheme.voltageColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                    LineChartBarData(
                      spots: currentData,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: AppTheme.currentColor,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: data.length <= 15,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: AppTheme.currentColor,
                              strokeWidth: 1.5,
                              strokeColor: AppTheme.cardBg,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.currentColor.withValues(alpha: 0.15),
                            AppTheme.currentColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          if (value == minX || value == maxX) return const SizedBox.shrink();
                          final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(DateFormat('HH:mm').format(date),
                                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: Text('Voltage (V)',
                          style: TextStyle(fontSize: 10, color: AppTheme.voltageColor.withValues(alpha: 0.7))),
                      axisNameSize: 16,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: TextStyle(fontSize: 10, color: AppTheme.voltageColor.withValues(alpha: 0.6)),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      axisNameWidget: Text('Current (A)',
                          style: TextStyle(fontSize: 10, color: AppTheme.currentColor.withValues(alpha: 0.7))),
                      axisNameSize: 16,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value == minV || value == maxV) return const SizedBox.shrink();
                          // Reverse map to original current value
                          double origI = minI + ((value - minV) / vRange) * iRange;
                          return Text(
                            origI.toStringAsFixed(1),
                            style: TextStyle(fontSize: 10, color: AppTheme.currentColor.withValues(alpha: 0.6)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppTheme.border.withValues(alpha: 0.3),
                      strokeWidth: 0.5,
                      dashArray: [4, 4],
                    ),
                  ),
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

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  EXISTING WIDGETS (Info, Latest Reading, etc.)
// ═══════════════════════════════════════════════════════════════

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
