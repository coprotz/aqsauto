import 'dart:async';
import 'dart:convert';
import 'package:aqs/features/ipc/execution_outbox.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> command(String id) => {
  'id': id,
  'package': 'p',
  'item': 'i',
  'entry': id,
  'delta': 5.0,
  'quantity': 5.0,
  'baseCumulative': 10.0,
};

void main() {
  late Map<String, String> disk;
  late ExecutionOutbox queue;
  setUp(() async {
    disk = {};
    queue = ExecutionOutbox(
      read: (u) async => disk[u],
      write: (u, v) async {
        disk[u] = v;
      },
    );
    await queue.setUser('alice');
  });
  tearDown(() => queue.dispose());

  test(
    'durable save precedes publication and survives restart/sign-out',
    () async {
      await queue.enqueue(command('one'));
      expect((jsonDecode(disk['alice']!) as List).single['id'], 'one');
      await queue.setUser(null);
      expect(queue.commands, isEmpty);
      await queue.setUser('bob');
      expect(queue.commands, isEmpty);
      await queue.setUser('alice');
      expect(queue.commands.single['id'], 'one');
      final restored = ExecutionOutbox(
        read: (u) async => disk[u],
        write: (u, v) async {
          disk[u] = v;
        },
      );
      await restored.setUser('alice');
      expect(restored.commands.single['id'], 'one');
      restored.dispose();
    },
  );

  test('quota rejection retains command and retry uses the same ID', () async {
    await queue.enqueue(command('one'));
    final sent = <String>[];
    queue.send = (c) async {
      sent.add(c['id'] as String);
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'resource-exhausted',
      );
    };
    await queue.sync();
    expect(queue.commands.length, 1);
    expect(queue.retryTimer!.isActive, isTrue);
    queue.send = (c) async {
      sent.add(c['id'] as String);
    };
    await queue.retry();
    expect(sent, ['one', 'one']);
    expect(queue.commands, isEmpty);
    expect(jsonDecode(disk['alice']!), isEmpty);
  });

  test('failed device write never reports a saved quantity', () async {
    final broken = ExecutionOutbox(
      read: (_) async => null,
      write: (_, __) async => throw Exception('device full'),
    );
    await broken.setUser('alice');
    await expectLater(broken.enqueue(command('one')), throwsException);
    expect(broken.commands, isEmpty);
    broken.dispose();
  });

  test('locked IPC rejection is retained for review', () async {
    await queue.enqueue(command('one'));
    queue.send = (_) async => throw StateError('IPC is certified');
    await queue.sync();
    expect(queue.commands.single['blocked'], isTrue);
    expect(queue.retryTimer?.isActive ?? false, isFalse);
    await queue.setUser(null);
    queue.send = null;
    await queue.setUser('alice');
    expect(queue.commands.single['error'], contains('certified'));
  });

  test(
    'optimistic quantities do not apply again to acknowledged row',
    () async {
      await queue.enqueue(command('one'));
      final row = <String, dynamic>{
        '_itemId': 'i',
        'cumulativeExecutedQuantity': 10.0,
      };
      expect(queue.projectRow('p', row)['cumulativeExecutedQuantity'], 15);
      expect(
        queue.projectRow('p', {
          ...row,
          'cumulativeExecutedQuantity': 15.0,
          'lastExecutionOperationId': 'one',
        })['cumulativeExecutedQuantity'],
        15,
      );
    },
  );

  test(
    'changing account while sending never removes the other user queue',
    () async {
      await queue.enqueue(command('alice-entry'));
      final sent = Completer<void>();
      queue.send = (_) => sent.future;
      final sending = queue.sync();
      await queue.setUser('bob');
      await queue.enqueue(command('bob-entry'));
      sent.complete();
      await sending;
      expect(queue.commands.single['id'], 'bob-entry');
      expect((jsonDecode(disk['alice']!) as List).single['id'], 'alice-entry');
    },
  );
}
