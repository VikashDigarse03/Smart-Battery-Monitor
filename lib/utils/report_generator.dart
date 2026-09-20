import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/models.dart';

class ReportGenerator {
  static Future<File> generateExcelReport(List<Measurement> measurements, DateTime startDate, DateTime endDate) async {
    final excel = Excel.createExcel();
    final sheet = excel['Measurements'];
    excel.setDefaultSheet('Measurements');

    // Headers
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Battery ID'),
      TextCellValue('Voltage (V)'),
      TextCellValue('Current (A)'),
      TextCellValue('Temp (°C)'),
      TextCellValue('SOC (%)'),
      TextCellValue('SOH (%)'),
    ]);

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    for (final m in measurements) {
      sheet.appendRow([
        TextCellValue(dateFormat.format(m.measuredAt)),
        TextCellValue(m.batteryCode ?? 'Unknown'),
        DoubleCellValue(m.voltage),
        DoubleCellValue(m.current),
        DoubleCellValue(m.temperature),
        TextCellValue(m.batteryPercent?.toString() ?? '-'),
        TextCellValue(m.batteryHealth?.toString() ?? '-'),
      ]);
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/battery_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
    
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }

  static Future<File> generatePdfReport(List<Measurement> measurements, DateTime startDate, DateTime endDate) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Battery Measurement Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Paragraph(text: 'Period: ${dateFormat.format(startDate)} to ${dateFormat.format(endDate)}'),
          pw.Paragraph(text: 'Total Records: ${measurements.length}'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            context: context,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerHeight: 25,
            cellHeight: 20,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['Date', 'Battery', 'Voltage', 'Current', 'Temp', 'SOC'],
            data: measurements.map((m) => [
              dateFormat.format(m.measuredAt),
              m.batteryCode ?? 'Unknown',
              '${m.voltage.toStringAsFixed(2)} V',
              '${m.current.toStringAsFixed(2)} A',
              '${m.temperature.toStringAsFixed(1)} C',
              '${m.batteryPercent ?? '-'}%',
            ]).toList(),
          ),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/battery_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
