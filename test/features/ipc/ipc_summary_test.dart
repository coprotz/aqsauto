import 'package:aqs/features/ipc/ipc_summary_model.dart';
import 'package:aqs/features/ipc/ipc_summary_export.dart';
import 'package:aqs/features/ipc/ipc_summary_page.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const certificate = <String, dynamic>{
  'number': 3,
  'ipcType': 'work',
  'grossWorkValue': 1000,
  'previousExecutedAmount': 2000,
  'cumulativeExecutedAmount': 3000,
  'retentionDeduction': 100,
  'retentionHeld': 300,
  'advanceRecovery': 150,
  'advancePaymentRecovered': 450,
};
const history = <Map<String, dynamic>>[
  {
    'number': 1,
    'status': 'submitted',
    'ipcType': 'advance',
    'advanceAmount': 500,
  },
  {
    'number': 4,
    'status': 'submitted',
    'ipcType': 'advance',
    'advanceAmount': 999,
  },
  {'number': 2, 'status': 'draft', 'ipcType': 'advance', 'advanceAmount': 999},
  {
    'number': 2,
    'status': 'submitted',
    'ipcType': 'advance',
    'advanceAmount': 999,
    'isDeleted': true,
  },
];
void main() {
  test('reconciliation preserves original IPC and deducts certified advance once', () {
    final rows = ipcSummaryRows({...certificate, 'rateAdjustmentAmount': 25}, [
      {'number': 1, 'status': 'paid', 'ipcType': 'advance', 'advanceAmount': 500, 'amountCertified': 500},
      {'number': 2, 'status': 'submitted', 'originalIpcValue': 1450, 'amountApplied': 9999},
    ]);
    expect(rows.firstWhere((r) => r.code == 'D').values, [null, 500, null]);
    expect(rows.firstWhere((r) => r.code == 'E').values, [1450, 2250, null]);
    expect(rows.firstWhere((r) => r.code == 'R').values, [null, 25, null]);
  });
  test('missing certified or historical values are not guessed', () {
    final rows = ipcSummaryRows(certificate, [
      {'number': 1, 'status': 'certified', 'ipcType': 'advance', 'advanceAmount': 500},
      {'number': 2, 'status': 'submitted', 'calculatedAmountApplied': 9999},
    ]);
    expect(rows.firstWhere((r) => r.code == 'E').values, [null, null, null]);
    expect(rows.firstWhere((r) => r.code == 'R').values, [null, null, null]);
  });
  test('summary reconciles current card and cumulative less previous', () {
    final rows = ipcSummaryRows(certificate, history);
    final net = rows.firstWhere((r) => r.code == 'C');
    expect(net.values, [2000, 750, 2750]);
    expect(net.values[2]! - net.values[0]!, net.values[1]);
    expect(rows.firstWhere((r) => r.code == '2').values, [500, 0, 500]);
  });
  test('missing cumulative values stay unavailable', () {
    final rows = ipcSummaryRows({
      'number': 2,
      'grossWorkValue': 100,
      'retentionDeduction': 10,
      'advanceRecovery': 15,
    }, []);
    expect(rows.firstWhere((r) => r.code == 'C').values, [null, 75, null]);
  });
  test('advance certificate counts advance once without executed work', () {
    final rows = ipcSummaryRows({
      'number': 1,
      'ipcType': 'advance',
      'grossWorkValue': 0,
      'advanceAmount': 500,
      'retentionDeduction': 0,
      'advanceRecovery': 0,
    }, []);
    expect(rows.firstWhere((r) => r.code == 'C').values, [0, 500, 500]);
  });
  test('Excel export has numeric values and subtotal formulas', () {
    final bytes = ipcSummaryExcel('IPC 3', {
      'Project': 'Test project',
    }, ipcSummaryRows(certificate, history));
    final book = xl.Excel.decodeBytes(bytes);
    expect(book.tables.keys, ['IPC summary']);
    final sheet = book['IPC summary'];
    final detail = sheet.rows.firstWhere(
      (r) =>
          r.length > 1 && r[1]?.value.toString() == 'Value of works executed',
    );
    expect(detail[3]!.value, anyOf(isA<xl.DoubleCellValue>(), isA<xl.IntCellValue>()));
    expect(detail[3]!.value.toString(), '1000');
    final net = sheet.rows.firstWhere(
      (r) =>
          r.length > 1 &&
          r[1]?.value.toString() == 'Net valuation (including advance; before prior certificates)',
    );
    expect(net[3]!.value, isA<xl.FormulaCellValue>());
    expect(
      (net[3]!.value as xl.FormulaCellValue).formula,
      matches(r'^D\d+\+D\d+-D\d+$'),
    );
  });
  testWidgets('summary is legible on desktop and scrolls on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final document = IpcSummaryDocument(
      title: 'INTERIM PAYMENT CERTIFICATE NO. 3',
      details: const {
        'Project': 'Sample project',
        'Contract number': 'Not recorded',
        'Contract sum (TZS)': '19,952,955,995.50',
        'Period': '01 Jan 2025 - 31 Jul 2025',
        'Submission date': '01 Aug 2025',
        'Status': 'submitted',
      },
      rows: ipcSummaryRows(certificate, history),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: document))),
    );
    expect(tester.takeException(), isNull);
      expect(find.text('750.00'), findsNWidgets(2));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
