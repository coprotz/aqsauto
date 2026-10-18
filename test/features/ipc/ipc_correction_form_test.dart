import 'package:aqs/features/ipc/ipc_boq_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final trade in ['Electricity', 'Plumbing']) {
    testWidgets(
      '$trade accepts metres and preserves percentage storage value',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        double? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IpcBoqTable(
                rows: const [
                  {
                    'boqCode': 'A',
                    'description': 'Conduit',
                    'quantity': 100,
                    'rate': 315000,
                    'amount': 31500000,
                    'unit': '%',
                    'sourceBoq': {'quantity': 2100, 'unit': 'm', 'rate': 15000},
                    'previousExecutedQuantity': 10,
                    'cumulativeExecutedQuantity': 20,
                  },
                ],
                package: {'name': trade, 'executionMode': 'percentage'},
                onExecute: (row, rfi, sheet, qty) async {
                  saved = qty;
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Conduit'));
        await tester.pumpAndSettle();
        expect(find.text('210 m'), findsNWidgets(2));
        expect(find.text('420 m'), findsOneWidget);
        await tester.tap(find.text('Add new executed qty'));
        await tester.pumpAndSettle();
        expect(find.text('Executed quantity (m)'), findsOneWidget);
        expect(find.text('Executed percentage (%)'), findsNothing);
        await tester.enterText(find.byType(TextFormField).at(1), '01');
        await tester.enterText(find.byType(TextFormField).at(2), '210');
        await tester.tap(find.text('Save quantity'));
        await tester.pumpAndSettle();
        expect(saved, 10);
        expect(saved! * 315000, 210 * 15000);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('preliminaries retain percentage entry', () {
    final row = {
      'sourceBoq': {'quantity': 2100, 'unit': 'm'},
    };
    final package = {'name': 'Preliminaries', 'executionMode': 'percentage'};
    expect(ipcUsesMeasuredEntry(row, package), isFalse);
    expect(ipcEntryQuantityScale(row, package), 1);
  });
  testWidgets('negative execution requires correction and a reason', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    double? saved;
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IpcBoqTable(
            rows: const [
              {
                'boqCode': 'A',
                'description': 'Concrete',
                'quantity': 100,
                'rate': 20,
                'unit': 'sqm',
                'previousExecutedQuantity': 20,
                'cumulativeExecutedQuantity': 30,
              },
            ],
            package: const {},
            onExecute: (row, rfi, sheet, qty) async {
              saved = qty;
              payload = row;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Concrete'));
    await tester.pumpAndSettle();
    expect(find.text('Total BOQ quantity'), findsOneWidget);
    expect(find.text('100 sqm'), findsOneWidget);
    expect(find.text('20 sqm'), findsOneWidget);
    expect(find.text('10 sqm'), findsOneWidget);
    expect(find.text('30 sqm'), findsOneWidget);
    expect(find.text('70 sqm'), findsOneWidget);
    await tester.tap(find.text('Add new executed qty'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '02');
    await tester.enterText(find.byType(TextFormField).at(2), '-10');
    await tester.tap(find.text('Save quantity'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save quantity'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measurement correction').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save quantity'));
    await tester.pumpAndSettle();
    expect(saved, -10);
    expect(payload?['_correctionReason'], 'Measurement correction');
    expect(tester.takeException(), isNull);
  });
}
