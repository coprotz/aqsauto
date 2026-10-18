import 'package:aqs/features/ipc/ipc_work_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Work IPC requires application amount and all three dates', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => showWorkIpcSetup(context), child: const Text('Prepare'))))));
    await tester.tap(find.text('Prepare'));
    await tester.pumpAndSettle();
    expect(find.text('Period From'), findsOneWidget);
    expect(find.text('Period To'), findsOneWidget);
    expect(find.text('Submission Date'), findsOneWidget);
    expect(find.text('Amount applied (TZS)'), findsOneWidget);
    await tester.tap(find.text('Continue to BOQs'));
    await tester.pumpAndSettle();
    expect(find.text('Select a date'), findsNWidgets(3));
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
