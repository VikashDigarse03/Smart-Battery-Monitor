import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  Future<void> _generateReport(bool isExcel) async {
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
          
      if (mounted) {
        final result = await Share.shareXFiles([XFile(file.path)], text: 'Battery Report');
        if (result.status == ShareResultStatus.success) {
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
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => _generateReport(true),
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Export as Excel (.xlsx)'),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => _generateReport(false),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export as PDF (.pdf)'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
