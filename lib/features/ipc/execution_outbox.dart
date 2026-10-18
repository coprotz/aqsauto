import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/state/outbox_storage.dart';

typedef ExecutionCommand = Map<String, dynamic>;

/// Device-saved commands, isolated by user. Never remove a command until the
/// idempotent server transaction confirms it, then persist the acknowledgement.
class ExecutionOutbox extends ChangeNotifier {
  ExecutionOutbox({this.read = readOutbox, this.write = writeOutbox});
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  Future<void> Function(ExecutionCommand)? send;
  String? user;
  List<ExecutionCommand> commands = [];
  String? message;
  bool ready = false, busy = false;
  int failures = 0;
  Timer? retryTimer;
  Future<void> serial = Future.value();

  Future<void> _exclusive(Future<void> Function() action) {
    final next = serial.then((_) => action());
    serial = next.catchError((Object _) {});
    return next;
  }

  Future<void> setUser(String? uid) => _exclusive(() async {
    retryTimer?.cancel();
    user = uid;
    ready = false;
    commands = [];
    message = null;
    notifyListeners();
    if (uid == null) return;
    try {
      final saved = await read(uid);
      commands =
          saved == null
              ? []
              : (jsonDecode(saved) as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
      ready = true;
    } catch (error) {
      message =
          'Local saving is unavailable: $error. Do not clear browser data.';
    }
    notifyListeners();
    if (ready) unawaited(sync());
  });

  Future<void> enqueue(ExecutionCommand command) => _exclusive(() async {
    if (!ready || user == null)
      throw StateError('Local saving is not ready. Please sign in and retry.');
    final next = [
      ...commands,
      {...command, 'user': user},
    ];
    await write(user!, jsonEncode(next));
    commands = next;
    notifyListeners();
    unawaited(sync());
  });

  Future<void> sync() async {
    if (busy || !ready || user == null || send == null || commands.isEmpty)
      return;
    busy = true;
    retryTimer?.cancel();
    final owner = user!;
    Duration delay = const Duration(minutes: 1);
    try {
      while (user == owner && commands.isNotEmpty) {
        final command = Map<String, dynamic>.from(commands.first);
        if (command['blocked'] == true) break;
        await send!(command).timeout(const Duration(seconds: 60));
        await _exclusive(() async {
          if (user != owner) return;
          final remaining =
              commands.where((e) => e['id'] != command['id']).toList();
          await write(owner, jsonEncode(remaining));
          commands = remaining;
          failures = 0;
          message = null;
          notifyListeners();
        });
      }
    } catch (error) {
      if (user == owner) {
        final rejected =
            error is StateError ||
            (error is FirebaseException &&
                [
                  'permission-denied',
                  'invalid-argument',
                  'not-found',
                ].contains(error.code));
        if (rejected) {
          try {
            await _exclusive(() async {
              if (user != owner || commands.isEmpty) return;
              final next =
                  commands.map((e) => Map<String, dynamic>.from(e)).toList();
              next.first['blocked'] = true;
              next.first['error'] = '$error';
              await write(owner, jsonEncode(next));
              commands = next;
            });
          } catch (_) {
            message =
                'Could not update local sync status. Your pending quantities have been kept.';
            return;
          }
          message = 'A saved quantity needs review: $error';
        } else {
          failures++;
          delay = Duration(minutes: (1 << failures.clamp(0, 5)).clamp(1, 30));
          message =
              'Saved on this device. Firebase is unavailable; sync will retry automatically.';
          if (error is FirebaseException &&
              error.code == 'resource-exhausted') {
            delay = const Duration(minutes: 30);
          }
        }
      }
    } finally {
      busy = false;
      notifyListeners();
      if (ready && commands.isNotEmpty && commands.first['blocked'] != true) {
        retryTimer = Timer(delay, () => unawaited(sync()));
      }
    }
  }

  Future<void> retry() async {
    if (busy) return;
    await _exclusive(() async {
      if (!ready || user == null) return;
      final next =
          commands
              .map(
                (e) =>
                    {...e}
                      ..remove('blocked')
                      ..remove('error'),
              )
              .toList();
      await write(user!, jsonEncode(next));
      commands = next;
      message = null;
      notifyListeners();
    });
    await sync();
  }

  List<ExecutionCommand> forPackage(String path) =>
      commands.where((e) => e['package'] == path).toList();

  Stream<List<Map<String, dynamic>>> entries(
    String path,
    String item,
    Stream<List<Map<String, dynamic>>> source,
  ) => Stream.multi((sink) {
    List<Map<String, dynamic>>? saved;
    void emit() {
      final pending = forPackage(path).where((e) => e['item'] == item);
      if (saved == null && pending.isEmpty) return;
      final rows = {
        for (final row in saved ?? <Map<String, dynamic>>[])
          row['_entryId']: row,
      };
      for (final command in pending) {
        final old = rows[command['entry']];
        if ((old?['appliedOperationIds'] as List? ?? []).contains(
          command['id'],
        ))
          continue;
        if (command['delete'] == true) {
          rows.remove(command['entry']);
          continue;
        }
        rows[command['entry']] = {
          '_entryId': command['entry'],
          'quantity': command['quantity'],
          'rawQuantity': command['rawQuantity'],
          'factor': command['factor'],
          'rfiNumber': command['rfi'],
          'measurementSheetNumber': command['sheet'],
          'correctionReason': command['reason'],
          '_pendingSync': true,
        };
      }
      sink.add(rows.values.toList());
    }

    addListener(emit);
    final sub = source.listen((rows) {
      saved = rows;
      emit();
    }, onError: sink.addError);
    emit();
    sink.onCancel = () {
      removeListener(emit);
      return sub.cancel();
    };
  });

  Map<String, dynamic> projectRow(String path, Map<String, dynamic> row) {
    final pending =
        forPackage(path).where((e) => e['item'] == row['_itemId']).toList();
    final acknowledged = pending.indexWhere(
      (e) => e['id'] == row['lastExecutionOperationId'],
    );
    final changes = pending.skip(acknowledged + 1);
    if (changes.isEmpty) return row;
    final delta = changes.fold<double>(
      0,
      (v, e) => v + (e['delta'] as num).toDouble(),
    );
    return {
      ...row,
      'cumulativeExecutedQuantity':
          (row['cumulativeExecutedQuantity'] as num? ??
              pending.first['baseCumulative'] as num? ??
              0) +
          delta,
      '_pendingSync': true,
    };
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    super.dispose();
  }
}

final executionOutbox = ExecutionOutbox();

class ExecutionSyncBanner extends StatelessWidget {
  const ExecutionSyncBanner({super.key, required this.packagePath});
  final String? packagePath;
  @override
  Widget build(BuildContext context) {
    final pending =
        packagePath == null
            ? executionOutbox.commands
            : executionOutbox.forPackage(packagePath!);
    if (pending.isEmpty && executionOutbox.message == null)
      return const SizedBox.shrink();
    return Material(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${pending.length} quantities saved on this device · Pending sync. '
                'IPC summary totals remain server-confirmed until synced.\n'
                '${executionOutbox.message ?? (executionOutbox.busy ? 'Syncing…' : 'Waiting to sync.')}',
              ),
            ),
            TextButton(
              onPressed:
                  () => showDialog<void>(
                    context: Get.key.currentState?.overlay?.context ?? context,
                    builder:
                        (dialogContext) => AlertDialog(
                          title: const Text('Device-saved quantities'),
                          content: SizedBox(
                            width: 500,
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final e in pending)
                                  ListTile(
                                    title: Text('${e['label']}'),
                                    subtitle: Text(
                                      'Quantity: ${e['quantity']} · RFI ${e['rfi']}\n${e['error'] ?? 'Pending sync'}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                  ),
              child: const Text('View pending'),
            ),
            TextButton(
              onPressed:
                  executionOutbox.busy
                      ? null
                      : () async {
                        try {
                          await executionOutbox.retry();
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not update the local queue. Entries have been kept.',
                                ),
                              ),
                            );
                        }
                      },
              child: const Text('Retry sync'),
            ),
          ],
        ),
      ),
    );
  }
}
