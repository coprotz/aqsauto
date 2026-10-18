import 'dart:async';
import 'package:aqs/core/state/session_data_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('idle disconnect keeps values until account reset and reconnects for freshness', () async {
    final state = SessionDataState(idleDisconnectDelay: const Duration(milliseconds: 5));
    var starts = 0, stops = 0;
    final source = StreamController<int>.broadcast(onListen: () => starts++, onCancel: () => stops++);
    final stream = state.watch('items', () => source.stream);
    final initial = stream.first;
    source.add(10);
    expect(await initial, 10);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stops, 1);
    final values = <int>[];
    final resumed = stream.listen(values.add);
    await Future<void>.delayed(Duration.zero);
    expect(values, [10]);
    expect(starts, 2);
    source.add(20);
    await Future<void>.delayed(Duration.zero);
    expect(values, [10, 20]);
    await resumed.cancel();
    state.clear();
    final fresh = stream.first;
    source.add(30);
    expect(await fresh, 30);
    state.clear();
    await source.close();
  });

  test('default session cache retains more than 64 idle entries', () async {
    final state = SessionDataState();
    var reads = 0;
    final sources = List.generate(70, (_) => StreamController<int>.broadcast());
    for (var i = 0; i < sources.length; i++) {
      final first = state.watch(i, () { reads++; return sources[i].stream; }).first;
      sources[i].add(i);
      expect(await first, i);
    }
    expect(await state.watch(0, () { reads++; return sources[0].stream; }).first, 0);
    expect(reads, 70);
    state.clear();
    for (final source in sources) { await source.close(); }
  });
  test(
    'shares reads, replays state on reopening, and propagates changes',
    () async {
      final state = SessionDataState();
      final source = StreamController<int>.broadcast();
      var reads = 0;
      Stream<int> load() {
        reads++;
        return source.stream;
      }

      final a = <int>[], b = <int>[];
      final first = state.watch('items', load).listen(a.add);
      final second = state.watch('items', load).listen(b.add);
      source.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      expect(a, [1]);
      expect(b, [1]);
      await first.cancel();
      await second.cancel();
      expect(await state.watch('items', load).first, 1);
      source.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(await state.watch('items', load).first, 2);
      expect(reads, 1);
      state.clear();
      await source.close();
    },
  );

  test(
    'account reset discards old data and old streams reload safely',
    () async {
      final state = SessionDataState();
      final source = StreamController<int>.broadcast();
      final stream = state.watch('items', () => source.stream);
      final first = stream.first;
      source.add(1);
      expect(await first, 1);
      state.clear();
      final next = stream.first;
      source.add(2);
      expect(await next, 2);
      state.clear();
      await source.close();
    },
  );

  test(
    'separate projects cannot share values and rollback updates state',
    () async {
      final state = SessionDataState();
      final source = StreamController<int>.broadcast();
      final other = StreamController<int>.broadcast();
      final values = <int>[];
      final sub = state
          .watch('project-a/items', () => source.stream)
          .listen(values.add);
      final second = state.watch('project-b/items', () => other.stream).first;
      source.add(1);
      source.add(2);
      source.add(1);
      other.add(10);
      expect(await second, 10);
      await Future<void>.delayed(Duration.zero);
      expect(values, [1, 2, 1]);
      expect(
        await state.watch('project-a/items', () => source.stream).first,
        1,
      );
      await sub.cancel();
      state.clear();
      await source.close();
      await other.close();
    },
  );

  test('idle expiry releases reads and a held stream can reload', () async {
    final state = SessionDataState(
      idleLifetime: const Duration(milliseconds: 5),
    );
    final source = StreamController<int>.broadcast();
    var reads = 0;
    final stream = state.watch('items', () {
      reads++;
      return source.stream;
    });
    final first = stream.first;
    source.add(1);
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = stream.first;
    source.add(2);
    expect(await second, 2);
    expect(reads, 2);
    state.clear();
    await source.close();
  });

  test('failed reads surface errors and are not cached as success', () async {
    final state = SessionDataState();
    final source = StreamController<int>.broadcast();
    final stream = state.watch('items', () => source.stream);
    final failed = expectLater(stream.first, throwsStateError);
    source.addError(StateError('permission denied'));
    await failed;
    final retry = stream.first;
    source.add(3);
    expect(await retry, 3);
    state.clear();
    await source.close();
  });
}
