import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'ipc_summary_model.dart';

/// Uses the app's existing cross-platform Excel support; exports exactly the
/// values shown on the summary page, with formulas for subtotal/net rows.
// IPC Gross Work compatibility: supports per-column percentages and grouped execution columns.
Uint8List ipcSummaryExcel(
  String title,
  Map<String, String> details,
  List<IpcSummaryRow> rows,
  {
    List<String>? headers,
    bool percentLast = false,
    Set<int> percentValueIndexes = const {},
    bool groupedExecuted = false,
  }
) {
  final resolvedHeaders = headers ?? const [
    'Ref',
    'Description',
    'Previous (TZS)',
    'This IPC (TZS)',
    'Cumulative (TZS)',
  ];
  final columnCount = resolvedHeaders.length;
  final book = xl.Excel.createExcel();
  book.rename('Sheet1', 'IPC summary');
  final sheet = book['IPC summary'];
  final navy = xl.ExcelColor.fromHexString('FF173565');
  final pale = xl.ExcelColor.fromHexString('FFEAF3E5');
  final line = xl.Border(
    borderStyle: xl.BorderStyle.Thin,
    borderColorHex: xl.ExcelColor.fromHexString('FFD6DFEA'),
  );
  void put(
    int r,
    int c,
    xl.CellValue value, {
    bool heading = false,
    bool total = false,
    bool numeric = false,
    bool percent = false,
  }) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
    );
    cell.value = value;
    cell.cellStyle = xl.CellStyle(
      fontFamily: 'Calibri',
      fontSize: 11,
      bold: heading || total,
      fontColorHex: heading ? xl.ExcelColor.white : navy,
      backgroundColorHex:
          heading
              ? navy
              : total
              ? pale
              : xl.ExcelColor.white,
      textWrapping: xl.TextWrapping.WrapText,
      verticalAlign: xl.VerticalAlign.Center,
      horizontalAlign:
          numeric ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Left,
      numberFormat: xl.NumFormat.custom(formatCode: percent ? '0.00"%"' : '#,##0.00;(#,##0.00);"-"'),
      bottomBorder: line,
    );
  }

  void merged(int r, String value, {bool heading = false}) {
    for (var c = 0; c < columnCount; c++) {
      put(r, c, xl.TextCellValue(c == 0 ? value : ''), heading: heading);
    }
    sheet.merge(
      xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      xl.CellIndex.indexByColumnRow(columnIndex: columnCount - 1, rowIndex: r),
    );
    sheet.setRowHeight(r, heading ? 36 : 30);
  }

  merged(0, title, heading: true);
  var r = 2;
  for (final entry in details.entries) {
    put(r, 0, xl.TextCellValue(entry.key));
    put(r, 1, xl.TextCellValue(entry.value));
    sheet.merge(
      xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r),
      xl.CellIndex.indexByColumnRow(columnIndex: columnCount - 1, rowIndex: r),
    );
    sheet.setRowHeight(r++, 28);
  }
  r++;
  if (groupedExecuted && columnCount == 9) {
    for (var c = 0; c < columnCount; c++) {
      put(r, c, xl.TextCellValue(c < 3 ? resolvedHeaders[c] : ''), heading: true);
      put(r + 1, c, xl.TextCellValue(''), heading: true);
      put(r + 2, c, xl.TextCellValue(''), heading: true);
    }
    put(r, 3, xl.TextCellValue('EXECUTED'), heading: true);
    sheet.merge(
      xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r),
      xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r),
    );
    for (var c = 0; c < 3; c++) {
      sheet.merge(
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 2),
      );
    }
    const groups = ['Previous IPC', 'This IPC', 'Cumulative'];
    for (var group = 0; group < groups.length; group++) {
      final start = 3 + group * 2;
      put(r + 1, start, xl.TextCellValue(groups[group]), heading: true);
      sheet.merge(
        xl.CellIndex.indexByColumnRow(columnIndex: start, rowIndex: r + 1),
        xl.CellIndex.indexByColumnRow(columnIndex: start + 1, rowIndex: r + 1),
      );
      put(r + 2, start, xl.TextCellValue('Amount (TZS)'), heading: true);
      put(r + 2, start + 1, xl.TextCellValue('%'), heading: true);
    }
    sheet.setRowHeight(r, 28);
    sheet.setRowHeight(r + 1, 26);
    sheet.setRowHeight(r + 2, 26);
    r += 3;
  } else {
    for (var c = 0; c < columnCount; c++) {
      put(r, c, xl.TextCellValue(resolvedHeaders[c]), heading: true);
    }
    sheet.setRowHeight(r++, 32);
  }
  final references = <String, int>{};
  for (final row in rows) {
    if (row.section) {
      merged(r++, row.label, heading: true);
      continue;
    }
    references[row.code] = r + 1;
    put(r, 0, xl.TextCellValue(row.code), total: row.total);
    put(r, 1, xl.TextCellValue(row.label), total: row.total);
    for (var i = 0; i < row.values.length; i++) {
      final column = String.fromCharCode(67 + i);
      final value = row.values[i];
      final formula = row.formula?.replaceAllMapped(
        RegExp(r'\{([^}]+)\}'),
        (m) => '$column${references[m[1]]}',
      );
      put(
        r,
        i + 2,
        value == null
            ? xl.TextCellValue('Not available')
            : formula != null
            ? xl.FormulaCellValue(formula)
            : xl.DoubleCellValue(value),
        numeric: true,
        total: row.total,
        percent:
            percentValueIndexes.contains(i) ||
            (percentLast && i == row.values.length - 1),
      );
    }
    sheet.setRowHeight(r++, 32);
  }
  r++;
  merged(
    r++,
    'VAT and retention releases are not included: these adjustments are not configured in the IPC calculation.',
  );
  merged(
    r++,
    'Previous and cumulative columns show valuations, not confirmation of amounts certified or paid.',
  );
  merged(
    r++,
    'Prepared by: ____________________    Checked by: ____________________',
  );
  merged(r, 'Signature: ____________________    Date: ____________________');
  sheet.setColumnWidth(0, 16);
  sheet.setColumnWidth(1, 54);
  for (var c = 2; c < columnCount; c++) {
    final valueIndex = c - 2;
    final percent =
        percentValueIndexes.contains(valueIndex) ||
        (percentLast && valueIndex == columnCount - 3);
    sheet.setColumnWidth(c, percent ? 13 : 24);
  }
  final bytes = book.encode();
  if (bytes == null) throw StateError('Could not create the Excel summary.');
  return Uint8List.fromList(bytes);
}
