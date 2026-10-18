import 'dart:io';
import 'package:aqs/features/ipc/ipc_certificate_document.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  final data = <String, dynamic>{'number': 3, 'grossWorkValue': 1000,
    'previousExecutedAmount': 2000, 'cumulativeExecutedAmount': 3000,
    'retentionDeduction': 100, 'retentionHeld': 300,
    'advanceRecovery': 150, 'advancePaymentRecovered': 450};
  final history = <Map<String, dynamic>>[
    {'number': 1, 'status': 'paid', 'ipcType': 'advance', 'advanceAmount': 500, 'amountCertified': 500},
  ];
  final fields = <String, String>{'heading': "THE UNITED REPUBLIC OF TANZANIA\nPRESIDENT'S OFFICE\nREGIONAL ADMINISTRATION AND LOCAL GOVERNMENT",
    'projectTitle': 'SAMPLE PROJECT - CONSTRUCTION OF REGIONAL BUS TERMINAL AND MARKET',
    'contractNumber': 'SAMPLE/2026/01', 'contractSum': '19,952,955,995.50',
    'financier': 'Sample financier', 'employer': 'Sample employer',
    'contractorName': 'Sample contractor', 'projectManager': 'Sample project manager'};
  test('certificate uses cumulative values and deducts certified amounts once', () {
    final lines = certificateLines(data, history);
    expect(lines.last.amount, 2250);
    expect(lines.firstWhere((l) => l.ref == '7').amount, 500);
    expect(lines.firstWhere((l) => l.ref == '6').label, contains('not configured'));
  });
  test('Excel contains numeric values and valid total formulas', () {
    final lines = certificateLines(data, history);
    final book = xl.Excel.decodeBytes(certificateExcel('3', fields, lines));
    final rows = book['IPC certificate'].rows;
    expect(rows[5][2]!.value, isA<xl.DoubleCellValue>());
    final total = rows.firstWhere((r) => r.first?.value.toString() == 'E');
    expect((total[2]!.value as xl.FormulaCellValue).formula, matches(r'^C\d+-C\d+$'));
    expect(rows.expand((r) => r).any((c) => c?.value.toString().contains('null') == true), isFalse);
  });
  test('PDF preserves headings, metadata and amount due', () async {
    final bytes = await certificatePdf('3', fields, certificateLines(data, history));
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    expect(text, contains('SAMPLE/2026/01'));
    expect(text, contains('2,250.00'));
    expect(text, contains('Signature:'));
    expect(document.pages.count, lessThanOrEqualTo(2));
    document.dispose();
    if (Platform.environment['IPC_CERTIFICATE_PREVIEW'] == '1') {
      await File('/private/tmp/ipc-certificate-preview.pdf').writeAsBytes(bytes);
    }
  });
}
