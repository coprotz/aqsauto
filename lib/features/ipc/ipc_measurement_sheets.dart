import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'ipc_boq_table.dart';

/// This generator reads item-level IPC snapshots. It never spreads a building
/// percentage across BOQ items, nor assumes executed quantities were paid.
class IpcMeasurementSheets {
  static double? value(dynamic v) => double.tryParse('${v ?? ''}'.replaceAll(',', ''));
  static final qtyFormat = NumberFormat('#,##0.###');
  static final amountFormat = NumberFormat('#,##0.00');

  static Future<void> printBuilding({
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> package,
    required Future<List<Map<String, dynamic>>> Function(Map<String, dynamic>) loadEntries,
    String ipcNumber = '',
    bool includeUnmeasured = false,
    Map<String, dynamic> sheetDetails = const {},
  }) async {
    final doc = pw.Document();
    var index = 0;
    for (final original in rows) {
      final kind = '${original['rowType'] ?? 'item'}'.toLowerCase();
      if (kind != 'item') continue;
      final row = ipcDisplayBoq(original, package);
      final execution = ipcItemExecution(row, package);
      // Print only BOQ items with a positive executed quantity in THIS IPC.
      // A previous/cumulative quantity, or existing RFI entries alone, must
      // never make an unexecuted item eligible for the current IPC PDF.
      final thisIpcQty = execution[1];
      if (thisIpcQty == null || thisIpcQty <= 0.000000001) continue;
      final entries = await loadEntries(original);
      final measured = execution[2];
      index++;
      final code = '${row['displayCode'] ?? row['boqCode'] ?? row['code'] ?? ''}';
      final description = '${row['description'] ?? ''}';
      final revised = value(row['revisedQty'] ?? row['revisedQuantity']);
      final contract = value(row['qtyOverride'] ?? row['quantity'] ?? row['qty']);
      final basis = revised ?? contract;
      final percent = basis != null && basis != 0 && measured != null ? measured / basis * 100 : null;
      final refText = entries.map((e) => '${e['rfiNumber'] ?? ''}'.trim()).where((s) => s.isNotEmpty).toSet().join(', ');
      final sheetText = entries.map((e) => '${e['measurementSheetNumber'] ?? ''}'.trim()).where((s) => s.isNotEmpty).toSet().join(', ');
      final unit = '${row['unit'] ?? ''}';
      final heading = '${package['siteName'] ?? ''} - ${package['name'] ?? 'Building'}';
      String detail(String key) => '${sheetDetails[key] ?? ''}'.trim();
      pw.Widget line(String left, String right, {bool shaded = false}) => pw.Container(
        color: shaded ? PdfColors.grey200 : PdfColors.white,
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text(left, style: pw.TextStyle(fontWeight: shaded ? pw.FontWeight.bold : pw.FontWeight.normal))), pw.Expanded(flex: 2, child: pw.Text(right, textAlign: pw.TextAlign.right))]),
      );
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(color: PdfColors.indigo600, padding: const pw.EdgeInsets.all(12), child: pw.Text('${heading.toUpperCase()} MEASUREMENT SHEET', textAlign: pw.TextAlign.center, style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.Table(border: pw.TableBorder.all(), columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(4)}, children: [
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('SHEET NO.')), pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(sheetText.isEmpty ? (detail('sheetPrefix').isEmpty ? 'MS-${index.toString().padLeft(3, '0')}' : '${detail('sheetPrefix')}-${index.toString().padLeft(3, '0')}') : sheetText))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('IPC NO.')), pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(ipcNumber.isEmpty ? 'Not specified' : ipcNumber))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('BOQ ITEM')), pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('$code - $description'))]),
          ]),
          pw.SizedBox(height: 12),
          pw.Table(border: pw.TableBorder.all(), columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2)}, children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.yellow200), children: ['SN', 'MEASUREMENT / QUANTITY ($unit)', 'RFI NO.'].map((t) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList()),
            ...entries.asMap().entries.map((entry) => pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${entry.key + 1}')), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(qtyFormat.format(value(entry.value['quantity']) ?? 0))), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${entry.value['rfiNumber'] ?? ''}'))])),
            if (entries.isEmpty) pw.TableRow(children: [pw.Text('1'), pw.Text(execution[1] == null ? 'Item measurement details unavailable' : qtyFormat.format(execution[1])), pw.Text(refText.isEmpty ? 'Not recorded' : refText)]),
          ]),
          pw.Spacer(),
          pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Column(children: [
            line('Contract/Revised BOQ Qty', basis == null ? 'Not recorded' : '${qtyFormat.format(basis)} $unit'),
            line('Previous Executed Quantity', execution[0] == null ? 'Not available' : '${qtyFormat.format(execution[0])} $unit'),
            line('This IPC Executed Quantity', execution[1] == null ? 'Not available' : '${qtyFormat.format(execution[1])} $unit'),
            line('Actual Measured Cumulative Qty', measured == null ? 'Not available' : '${qtyFormat.format(measured)} $unit', shaded: true),
            line('Cumulative Executed Percentage', percent == null ? 'Not available' : '${percent.toStringAsFixed(2)}%', shaded: true),
          ])),
          pw.SizedBox(height: 20),
          pw.Table(border: pw.TableBorder.all(), children: [pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Prepared by Quantity Surveyor'), pw.SizedBox(height: 12), pw.Text('Name: ${detail('preparedBy').isEmpty ? '_______________________' : detail('preparedBy')}'), pw.SizedBox(height: 55), pw.Text('Signature: __________________________'), pw.SizedBox(height: 12), pw.Text('Date: ${detail('preparedDate').isEmpty ? '_______________________' : detail('preparedDate')}')])),
            pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Reviewed and Verified by Resident Engineer'), pw.SizedBox(height: 12), pw.Text('Name: ${detail('verifiedBy').isEmpty ? '_______________________' : detail('verifiedBy')}'), pw.SizedBox(height: 55), pw.Text('Signature: __________________________'), pw.SizedBox(height: 12), pw.Text('Date: ${detail('verifiedDate').isEmpty ? '_______________________' : detail('verifiedDate')}')])),
          ])]),
        ]),
      ));
    }
    if (index == 0) throw StateError('No BOQ items have a positive This IPC executed quantity for this building.');
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'IPC_${ipcNumber}_Building_Measurement_Sheets.pdf');
  }
}
