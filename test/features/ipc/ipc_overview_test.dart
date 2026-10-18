import 'package:aqs/features/ipc/ipc_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Top cards show certified total and latest cumulative work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IpcOverview(
              records: const [
                {
                  'id': '4',
                  'number': 4,
                  'status': 'submitted',
                  'amountCertified': 999,
                  'cumulativeExecutedAmount': 450,
                  'contractValue': 1000,
                },
                {
                  'id': '3',
                  'number': 3,
                  'status': 'certified',
                  'amountCertified': 120,
                },
                {
                  'id': '2',
                  'number': 2,
                  'status': 'sent_to_employer',
                  'amountCertified': 80,
                },
                {
                  'id': '1',
                  'number': 1,
                  'status': 'paid',
                  'amountCertified': 150,
                  'advancePayment': 150,
                  'cumulativeExecutedAmount': 0,
                },
                {
                  'id': 'deleted',
                  'status': 'paid',
                  'amountCertified': 900,
                  'isDeleted': true,
                },
              ],
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Amount certified to date'), findsOneWidget);
    expect(find.text('TZS 350.00'), findsOneWidget);
    expect(find.text('Value of work done to date'), findsOneWidget);
    expect(find.text('TZS 450.00'), findsOneWidget);
    expect(find.text('45.00% of contract sum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1900.0]) {
    testWidgets('Empty IPC dashboard remains visible at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IpcOverview(records: const [], onOpen: (_) {}),
            ),
          ),
        ),
      );
      expect(find.text('Retention Held'), findsOneWidget);
      final cardHeights =
          [
                'Latest IPC',
                'Amount Applied',
                'Amount certified to date',
                'Value of work done to date',
                'Retention Held',
                'Advance payment recovered',
              ]
              .map(
                (label) =>
                    tester
                        .getSize(
                          find
                              .ancestor(
                                of: find.text(label).first,
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .height,
              )
              .toSet();
      expect(
        cardHeights.length,
        1,
        reason: 'All summary cards have equal height',
      );
      expect(find.text('Advance payment recovered'), findsOneWidget);
      expect(find.text('IPC Progress'), findsOneWidget);
      expect(find.text('No IPC submitted before.'), findsOneWidget);
      expect(find.text('TZS 0.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Large IPC values and status action at $width', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: IpcOverview(
                records: const [
                  {
                    'id': 'ipc1',
                    'number': 1,
                    'status': 'submitted',
                    'amountApplied': 2992943399.33,
                  },
                ],
                onOpen: (_) {},
                onStatus: (id) => selected = id,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Outstanding'), findsNothing);
      expect(find.text('TZS 2,992,943,399.33'), findsWidgets);
      final action = find.byTooltip('Change status and action date');
      expect(action, findsOneWidget);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Change status and action date',
        ),
      );
      button.onPressed!();
      expect(selected, 'ipc1');
      expect(tester.takeException(), isNull);
    });
  }
}
