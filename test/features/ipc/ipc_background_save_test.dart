import 'dart:async';
import 'package:aqs/features/ipc/ipc_boq_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('form closes before save finishes and retains failed input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completion = Completer<void>();
    double? quantity;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcBoqTable(
      rows: const [{'boqCode': 'A', 'description': 'Concrete', 'quantity': 10, 'rate': 20}],
      package: const {},
      onExecute: (row, rfi, sheet, qty) { quantity = qty; return completion.future; },
    ))));
    await tester.tap(find.text('Concrete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new executed qty'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'RFI-1');
    await tester.enterText(find.byType(TextFormField).at(2), '12');
    await tester.ensureVisible(find.text('Save quantity'));
    await tester.tap(find.text('Save quantity'));
    await tester.pumpAndSettle();
    expect(find.text('Add executed quantity'), findsNothing);
    expect(completion.isCompleted, isFalse);
    expect(quantity, 12);
    completion.completeError(StateError('Quota exceeded'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View entry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Quantity: 12 × 1 = 12.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
