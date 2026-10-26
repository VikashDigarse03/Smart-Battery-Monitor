import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../data/repositories/measurement_repository.dart';
import '../../../../utils/report_generator.dart';
import '../../../core/theme.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Default to last 10 days
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 10));
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  /// [isExcel] determines file type; [openDirectly] skips the share sheet
  /// and opens the file in the native app instead.
  Future<void> _generateReport(bool isExcel, {bool openDirectly = false}) async {
    setState(() => _isGenerating = true);

    try {
      final repo = context.read<MeasurementRepository>();
      final measurements = await repo.getMeasurementsForReport(
        fromDate: _startDate,
        toDate: _endDate,
      );

      if (measurements.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data exists for the selected date range.')),
          );
        }
        return;
      }

      final file = isExcel
          ? await ReportGenerator.generateExcelReport(measurements, _startDate, _endDate)
          : await ReportGenerator.generatePdfReport(measurements, _startDate, _endDate);

      if (!mounted) return;

      if (openDirectly) {
        // Open in native app (e.g. Excel / PDF viewer)
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: ${result.message}')),
          );
        }
      } else {
        // Share / Export via share sheet
        final result = await Share.shareXFiles([XFile(file.path)], text: 'Battery Report');
        if (result.status == ShareResultStatus.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report generated and shared successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assessment_outlined,
                size: 72,
                color: AppTheme.textMuted,
              ),
              const SizedBox(height: 20),
              Text(
                'Generate Report',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),

              Card(
                child: ListTile(
                  leading: const Icon(Icons.date_range),
                  title: const Text('Date Range'),
                  subtitle: Text('${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}'),
                  trailing: const Icon(Icons.edit),
                  onTap: _isGenerating ? null : _selectDateRange,
                ),
              ),
              const SizedBox(height: 32),

              if (_isGenerating)
                const CircularProgressIndicator()
              else ...[
                // ── Excel split-button ──────────────────────────────────
                _ReportSplitButton(
                  icon: Icons.table_chart,
                  label: 'Excel (.xlsx)',
                  accentColor: Colors.green.shade700,
                  onExport: () => _generateReport(true),
                  onOpen: () => _generateReport(true, openDirectly: true),
                ),
                const SizedBox(height: 16),

                // ── PDF split-button ────────────────────────────────────
                _ReportSplitButton(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF (.pdf)',
                  accentColor: Theme.of(context).colorScheme.primary,
                  onExport: () => _generateReport(false),
                  onOpen: () => _generateReport(false, openDirectly: true),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable split-button widget
// ---------------------------------------------------------------------------

class _ReportSplitButton extends StatelessWidget {
  const _ReportSplitButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onExport,
    required this.onOpen,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onExport;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Row(
        children: [
          // ── Main action: Export & Share ────────────────────────────────
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
                ),
              ),
              onPressed: onExport,
              icon: Icon(icon),
              label: Text('Export as $label'),
            ),
          ),

          // Divider between main button and dropdown
          Container(width: 1, color: Colors.white24),

          // ── Dropdown trigger ───────────────────────────────────────────
          SizedBox(
            width: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
                ),
              ),
              onPressed: () => _showMenu(context),
              child: const Icon(Icons.arrow_drop_down, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        0,
      ),
      items: [
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.share, size: 20, color: accentColor),
              const SizedBox(width: 12),
              const Text('Export & Share'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(icon, size: 20, color: accentColor),
              const SizedBox(width: 12),
              Text('Open in ${label.contains('xlsx') ? 'Excel' : 'PDF viewer'}'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'export') onExport();
      if (value == 'open') onOpen();
    });
  }
}
