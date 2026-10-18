import 'dart:async';
import 'package:aqs/features/ipc/ipc_boq_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('timeout offers retry and a new stream can load saved items', (tester) async {
    final streams = <StreamController<String>>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcBoqLoader<String>(
      timeout: const Duration(seconds: 1),
      source: () { final stream = StreamController<String>(); streams.add(stream); return stream.stream; },
      builder: (_, data) => Text(data),
    ))));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Retry loading BOQ'), findsOneWidget);
    await tester.tap(find.text('Retry loading BOQ'));
    await tester.pump();
    expect(streams.length, 2);
    streams.last.add('Saved quantities');
    await tester.pump();
    expect(find.text('Saved quantities'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    for (final stream in streams) { unawaited(stream.close()); }
  });

  testWidgets('Dart timeout errors show a recoverable message', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: IpcBoqLoader<String>(
      source: () => Stream.error(TimeoutException('Reading saved IPC items')),
      builder: (_, data) => Text(data),
    ))));
    await tester.pump();
    expect(find.text('Retry loading BOQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
