import 'dart:async';
import 'package:aqs/features/ipc/ipc_loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows actual BOQ progress and failure count', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: IpcLoadingOverlay(
      loading: true, progress: 0.4,
      detail: '4 of 10 BOQs processed · 1 failed',
      child: Text('IPC'),
    ))));
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('4 of 10 BOQs processed · 1 failed'), findsOneWidget);
    expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, 0.4);
  });
  testWidgets('blocks actions until every data source has loaded', (tester) async {
    final first = StreamController<Object?>();
    final second = StreamController<Object?>();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcLoadingScope(
      sources: [first.stream, second.stream],
      child: TextButton(onPressed: () => taps++, child: const Text('Edit')),
    ))));
    expect(find.text('Loading IPC data…'), findsOneWidget);
    await tester.tap(find.text('Edit'), warnIfMissed: false);
    expect(taps, 0);
    first.add(1); await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    second.add(2); await tester.pump();
    expect(find.text('Loading IPC data…'), findsNothing);
    await tester.tap(find.text('Edit')); expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
    first.close(); second.close();
  });

  testWidgets('loading failure shows an error rather than a stuck overlay', (tester) async {
    final source = StreamController<Object?>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcLoadingScope(
      sources: [source.stream], child: const Text('IPC'),
    ))));
    source.addError(StateError('offline')); await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Some IPC data could not load'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); source.close();
  });
}
