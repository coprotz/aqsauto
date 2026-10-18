import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'ipc_boq_table.dart';

/// Full IPC BOQ snapshot: includes measured, non-measured and heading rows.
/// A null item-level execution is explicitly shown as unavailable, not zero.
class IpcBoqDetailsPdf {
  static double? _num(dynamic value) =>
      double.tryParse('${value ?? ''}'.replaceAll(',', ''));
  static final _amount = NumberFormat('#,##0.00');
  static final _qty = NumberFormat('#,##0.###');
  static String _text(dynamic value) => '${value ?? ''}'.trim();
  static String _format(double? value, {bool money = false}) =>
      value == null ? '—' : (money ? _amount : _qty).format(value);

  static Future<void> printBuilding({
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> package,
    required String ipcNumber,
    Map<String, dynamic> signatories = const {},
  }) async {
    if (rows.isEmpty) throw StateError('No BOQ rows are available.');
    final doc = pw.Document();
    final navy = PdfColor.fromHex('#183767');
    final paleBlue = PdfColor.fromHex('#DCE9FA');
    final paleYellow = PdfColor.fromHex('#FFF3C8');
    final border = PdfColor.fromHex('#8796A9');
    final site = _text(package['siteName']);
    final building = _text(package['name']).isEmpty ? 'BOQ' : _text(package['name']);
    final project = _text(package['projectName']).isEmpty ? site : _text(package['projectName']);
    const widths = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(6), 1: pw.FlexColumnWidth(34),
      2: pw.FlexColumnWidth(6), 3: pw.FlexColumnWidth(7),
      4: pw.FlexColumnWidth(10), 5: pw.FlexColumnWidth(12),
      6: pw.FlexColumnWidth(7), 7: pw.FlexColumnWidth(6), 8: pw.FlexColumnWidth(12),
      9: pw.FlexColumnWidth(7), 10: pw.FlexColumnWidth(6), 11: pw.FlexColumnWidth(12),
      12: pw.FlexColumnWidth(7), 13: pw.FlexColumnWidth(6), 14: pw.FlexColumnWidth(12),
    };
    pw.Widget cell(String text, {bool bold = false, bool right = false, double size = 7}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
          child: pw.Text(text, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );
    pw.TableRow titleRow(List<String> values, {PdfColor? color, bool bold = false}) =>
      pw.TableRow(decoration: pw.BoxDecoration(color: color), children: [
        for (var i = 0; i < values.length; i++) cell(values[i], bold: bold, right: i >= 3),
      ]);
    // Same persisted building/IPC fields used by the Measurement Sheets PDF.
    final prepared = _text(signatories['preparedBy']);
    final checked = _text(signatories['verifiedBy']);
    final preparedDate = _text(signatories['preparedDate']);
    final checkedDate = _text(signatories['verifiedDate']);

    // Keep the heading and column labels repeated on EVERY printed page.
    pw.Widget pageHeader() => pw.Column(children: [
      pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: border)),
        child: pw.Column(children: [
          pw.Text(project.isEmpty ? building.toUpperCase() : project.toUpperCase(),
            textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('SITE: ${site.isEmpty ? 'Not recorded' : site}', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('IPC NO.: ${ipcNumber.isEmpty ? 'Not recorded' : ipcNumber}', style: const pw.TextStyle(fontSize: 8)),
          ]),
          pw.SizedBox(height: 3),
          pw.Text('BUILDING / WORK SECTION: $building', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ])),
      pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(6), color: paleBlue,
        child: pw.Text('BILL OF QUANTITIES — CONTRACT / REVISED AND EXECUTED WORKS',
          textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.Table(border: pw.TableBorder.all(color: border, width: 0.5), columnWidths: const {
        0: pw.FlexColumnWidth(75), 1: pw.FlexColumnWidth(25),
        2: pw.FlexColumnWidth(25), 3: pw.FlexColumnWidth(25),
      }, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: paleBlue), children: [
          cell('CONTRACT / REVISED', bold: true),
          cell('PREVIOUS IPC', bold: true),
          cell('CUMULATIVE IPC', bold: true),
          cell('THIS IPC', bold: true),
        ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: border, width: 0.5), columnWidths: widths, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: paleBlue), children: [
          cell('ITEM', bold: true), cell('DESCRIPTION', bold: true), cell('UNIT', bold: true),
          cell('QTY', bold: true), cell('RATE', bold: true), cell('AMOUNT', bold: true),
          cell('QTY', bold: true), cell('%', bold: true), cell('AMOUNT', bold: true),
          cell('QTY', bold: true), cell('%', bold: true), cell('AMOUNT', bold: true),
          cell('QTY', bold: true), cell('%', bold: true), cell('AMOUNT', bold: true),
        ]),
      ]),
      pw.SizedBox(height: 3),
    ]);

    final printableRows = <List<String>>[];
    final headingFlags = <bool>[];
    final amounts = <double>[0, 0, 0, 0];
    var known = <bool>[true, true, true];
    for (final original in rows) {
      final type = _text(original['rowType']).toLowerCase();
      final heading = type.isNotEmpty && type != 'item';
      final row = ipcDisplayBoq(original, package);
      if (heading) {
        printableRows.add([_text(original['displayCode'] ?? original['boqCode']),
          _text(original['description'] ?? original['billLabel']), ...List.filled(13, '')]);
        headingFlags.add(true);
        continue;
      }
      final qty = _num(row['revisedQty'] ?? row['revisedQuantity']) ??
          _num(row['qtyOverride'] ?? row['quantity'] ?? row['qty']) ?? 0;
      final rate = _num(row['rate']) ?? 0;
      final rawExecution = ipcItemExecution(original, package);
      final execution = rawExecution.map((v) => v == null ? null :
          package['executionMode'] == 'percentage' ? v * qty / 100 : v).toList();
      final cumulative = execution[2];
      final previous = execution[0];
      final current = execution[1];
      double? percent(double? v) => v == null || qty == 0 ? null : v / qty * 100;
      String p(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)}%';
      printableRows.add([
        _text(original['displayCode'] ?? original['boqCode']),
        _text(original['description'] ?? original['billLabel']),
        _text(row['unit']), _format(qty), _format(rate, money: true), _format(qty * rate, money: true),
        _format(previous), p(percent(previous)), _format(previous == null ? null : previous * rate, money: true),
        _format(cumulative), p(percent(cumulative)), _format(cumulative == null ? null : cumulative * rate, money: true),
        _format(current), p(percent(current)), _format(current == null ? null : current * rate, money: true),
      ]);
      headingFlags.add(false);
      amounts[0] += qty * rate;
      for (var i = 0; i < 3; i++) {
        if (execution[i] == null) known[i] = false;
        else amounts[i + 1] += execution[i]! * rate;
      }
    }
    if (printableRows.isEmpty) throw StateError('No BOQ rows to print.');

    // A3 landscape has substantially more usable height than the old 450pt
    // pagination limit. Allocate the page according to its actual dimensions,
    // accounting for repeated headers, page footer and the final sign-off area.
    // Keep each BOQ item on one page and reserve room for totals/signatures.
    const normalPageBudget = 615.0;
    const finalPageBudget = 420.0;
    final rowHeights = <double>[];
    for (var i = 0; i < printableRows.length; i++) {
      final descLen = printableRows[i][1].length;
      // DESCRIPTION occupies roughly 34/150 of the table width; fonts are 7pt.
      final estimatedLines = (descLen / 57).ceil().clamp(1, 12);
      rowHeights.add(headingFlags[i] ? 21.0 : 14.0 + estimatedLines * 9.0);
    }
    final pages = <List<int>>[];
    var currentPage = <int>[];
    var used = 0.0;
    for (var i = 0; i < printableRows.length; i++) {
      final height = rowHeights[i];
      if (currentPage.isNotEmpty && used + height > normalPageBudget) {
        pages.add(currentPage);
        currentPage = <int>[];
        used = 0;
      }
      currentPage.add(i);
      used += height;
    }
    if (currentPage.isNotEmpty) pages.add(currentPage);

    // The final page contains the BOQ total and two signature boxes. If the
    // final body is too tall, move its trailing rows to one additional page;
    // never cut the total/signature section or leave a mostly blank page due
    // to an arbitrary maximum row count.
    if (pages.isNotEmpty) {
      final lastRows = pages.last;
      var lastHeight = lastRows.fold<double>(0, (sum, i) => sum + rowHeights[i]);
      if (lastHeight > finalPageBudget) {
        final moved = <int>[];
        while (lastRows.isNotEmpty &&
            (lastHeight > finalPageBudget || moved.isEmpty)) {
          final index = lastRows.removeLast();
          moved.insert(0, index);
          lastHeight -= rowHeights[index];
        }
        if (lastRows.isEmpty) pages.removeLast();
        pages.add(moved);
      }
    }
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final last = pageIndex == pages.length - 1;
      final body = <pw.Widget>[
        pw.Table(columnWidths: widths, border: pw.TableBorder.all(color: border, width: 0.45), children: [
          for (final rowIndex in pages[pageIndex])
            titleRow(printableRows[rowIndex], color: headingFlags[rowIndex] ? paleYellow : null, bold: headingFlags[rowIndex]),
        ]),
      ];
      if (last) {
        body.add(pw.Table(columnWidths: widths, border: pw.TableBorder.all(color: border, width: 0.6), children: [
          titleRow(['', 'TOTAL CARRIED TO SUMMARY', '', '', '', _format(amounts[0], money: true),
            '', '', known[0] ? _format(amounts[1], money: true) : '—',
            '', '', known[2] ? _format(amounts[3], money: true) : '—',
            '', '', known[1] ? _format(amounts[2], money: true) : '—'], color: paleBlue, bold: true),
        ]));
        body.add(pw.SizedBox(height: 12));
        body.add(pw.Table(border: pw.TableBorder.all(color: border), children: [pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('PREPARED BY: QUANTITY SURVEYOR', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8), pw.Text('Name: ${prepared.isEmpty ? '______________________' : prepared}', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 38), pw.Text('Signature: ______________________', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 8), pw.Text('Date: ${preparedDate.isEmpty ? '________________' : preparedDate}', style: const pw.TextStyle(fontSize: 8)),
          ])),
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('REVIEWED AND VERIFIED BY: RESIDENT ENGINEER', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8), pw.Text('Name: ${checked.isEmpty ? '______________________' : checked}', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 38), pw.Text('Signature: ______________________', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 8), pw.Text('Date: ${checkedDate.isEmpty ? '________________' : checkedDate}', style: const pw.TextStyle(fontSize: 8)),
          ])),
        ])]));
      }
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(26),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pageHeader(), ...body,
          pw.Spacer(), pw.Text('IPC $ipcNumber  |  $building  |  Page ${pageIndex + 1} of ${pages.length}',
            textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
        ]),
      ));
    }
    await Printing.layoutPdf(onLayout: (_) async => doc.save(),
      name: 'IPC_${ipcNumber}_${building.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_BOQ_Details.pdf');
  }
}
