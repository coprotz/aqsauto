import 'package:aqs/features/ipc/ipc_boq_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large BOQs append more items and search spans all rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcBoqTable(rows: List.generate(1000, (i) => {'boqCode': 'Code$i', 'description': 'Item $i', 'quantity': 1, 'rate': 1}), package: const {'executedAmount': 0, 'previousExecutedAmount': 0}))));
    expect(find.text('Rows 1–25 of 1000'), findsOneWidget);
    expect(find.text('Code25'), findsNothing);
    expect(find.byTooltip('Next page'), findsNothing);
    await tester.scrollUntilVisible(find.text('View more items'), 500, scrollable: find.byType(Scrollable).first);
    final more = tester.widget<OutlinedButton>(find.ancestor(of: find.text('View more items'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)).first);
    more.onPressed!();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(find.text('Rows 1–50 of 1000'), findsOneWidget);
    expect(find.text('Code0'), findsOneWidget);
    expect(find.text('Code25'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Code999');
    await tester.pumpAndSettle();
    expect(find.text('Rows 1–1 of 1'), findsOneWidget);
    expect(find.text('View more items'), findsNothing);
    expect(find.text('Code999', findRichText: false).evaluate().where((e) => e.widget is Text).length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('BOQ code stays at left edge after horizontal scrolling', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: IpcBoqTable(rows: [{'boqCode': 'A1', 'description': 'Wrapped description', 'quantity': 1, 'rate': 20}], package: {}))));
    final before = tester.getTopLeft(find.text('A1'));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    final frozenCode = find.descendant(of: find.byKey(const ValueKey('fixed-boq-code')), matching: find.text('A1'));
    expect(tester.getTopLeft(frozenCode), before);
    expect(tester.takeException(), isNull);
  });
  test('totals sum item amounts, excluding headings and handling percent basis', () {
    expect(ipcBoqExecutionTotals([
      {'rate': 500000, 'previousExecutedQuantity': 10, 'cumulativeExecutedQuantity': 50},
      {'rate': 100000, 'previousExecutedQuantity': 0, 'cumulativeExecutedQuantity': 30},
      {'rowType': 'heading', 'rate': 999},
    ], {}), [5000000, 23000000, 28000000]);
    expect(ipcBoqExecutionTotals([{'rate': 1}], {}), [null, null, null]);
  });
  test('percentage BOQ displays original quantity and full rate', () {
    final row = ipcDisplayBoq({'quantity': 100, 'rate': 500000, 'amount': 50000000, 'sourceBoq': {'quantity': 1, 'unit': 'Item'}}, {'executionMode': 'percentage'});
    expect(row['quantity'], 1);
    expect(row['rate'], 50000000);
    expect(row['unit'], 'Item');
  });
  testWidgets('click item row opens site header and sheet-first form', (tester) async {
    double? savedQty;
    Map<String, dynamic>? savedRow;
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcBoqTable(
      rows: const [{'boqCode': 'A', 'description': 'Concrete', 'quantity': 10, 'rate': 20}],
      package: const {'siteName': 'Inala', 'name': 'Guard house'},
      onExecute: (row, rfi, sheet, qty) async { savedQty = qty; savedRow = row; },
    ))));
    await tester.tap(find.text('Concrete'));
    await tester.pumpAndSettle();
    expect(find.text('Executed quantities'), findsOneWidget);
    expect(find.text('No executed quantities added yet.'), findsOneWidget);
    await tester.tap(find.text('Add new executed qty'));
    await tester.pumpAndSettle();
    expect(find.text('Executed quantities'), findsNothing);
    expect(find.text('Add executed quantity'), findsOneWidget);
    expect(find.text('Inala · Guard house'), findsWidgets);
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields.length, 4);
    expect(fields.last.controller!.text, '1');
    expect(tester.getTopLeft(find.text('Measurement sheet number')).dy, lessThan(tester.getTopLeft(find.text('RFI number')).dy));
    expect(find.text('Executed qty'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(1), 'RFI-1');
    await tester.enterText(find.byType(TextFormField).at(2), '12');
    await tester.enterText(find.byType(TextFormField).at(3), '1.5');
    await tester.pumpAndSettle();
    expect(find.text('Final quantity: 12 × 1.5 = 18'), findsOneWidget);
    await tester.ensureVisible(find.text('Save quantity'));
    await tester.tap(find.text('Save quantity'));
    await tester.pumpAndSettle();
    expect(savedQty, 18);
    expect(savedRow?['_rawQuantity'], 12);
    expect(savedRow?['_factor'], 1.5);
    expect(tester.takeException(), isNull);
  });
  test('execution is separate from BOQ quantity', () {
    expect(
      ipcItemExecution(
        {'quantity': 100},
        {'previousExecutedAmount': 0, 'executedAmount': 0},
      ),
      [0, 0, 0],
    );
    expect(
      ipcItemExecution(
        {'quantity': 100},
        {'previousExecutedAmount': 20, 'executedAmount': 80},
      ),
      [null, null, null],
    );
    expect(
      ipcItemExecution({
        'previousExecutedQuantity': 12,
        'cumulativeExecutedQuantity': 30,
      }, {}),
      [12, 18, 30],
    );
  });
  testWidgets(
    'grouped BOQ table renders without overflow and supports search',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IpcBoqTable(
              rows: [
                {
                  'boqCode': '1',
                  'description': 'Concrete',
                  'quantity': 100,
                  'rate': 200,
                  'previousExecutedQuantity': 10,
                  'cumulativeExecutedQuantity': 30,
                },
              ],
              package: {},
            ),
          ),
        ),
      );
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('This IPC'), findsOneWidget);
      expect(find.text('Cumulative'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.text('No matching BOQ items.'), findsOneWidget);
    },
  );
}
