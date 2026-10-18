import 'package:aqs/core/state/firestore_state.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ipc_boq_valuation.dart';
import 'ipc_deductions.dart';
import 'ipc_loading_overlay.dart';

double _number(dynamic value) => double.tryParse('$value'.replaceAll(',', '')) ?? 0;

Map<String, dynamic> ipcTakeoffPatch(Map<String, dynamic> source, double quantity) => {
  if (source.containsKey('description')) 'description': source['description'] ?? '',
  'unit': source['unit'] ?? '', 'quantity': quantity, 'qtyOverride': quantity,
  'rate': _number(source['rate']), 'amount': quantity * _number(source['rate']),
};

/// Links descriptions, units, quantities and rates. Execution quantities stay owned by IPC.
/// Every write rechecks eligible status transactionally.
bool ipcCanSyncTakeoff(Map<String, dynamic>? certificate) =>
    certificate != null && certificate['isDeleted'] != true &&
    ['draft', 'submitted'].contains(certificate['status']);

class IpcDraftLink extends StatefulWidget {
  const IpcDraftLink({super.key, required this.certificate, required this.child, this.initialSources = const []});
  final List<Stream<Object?>> initialSources;
  final DocumentReference<Map<String, dynamic>> certificate;
  final Widget child;
  @override
  State<IpcDraftLink> createState() => _IpcDraftLinkState();
}

class _IpcDraftLinkState extends State<IpcDraftLink> {
  final subscriptions = <StreamSubscription>[];
  final sources = <String, List<StreamSubscription>>{};
  final boqNames = <String, String>{};
  final prefetchedPackages = <String>{};
  String currentBoq = '';
  bool draft = false, running = false, dirty = false;
  int completedBoqs = 0, totalBoqs = 0, failedBoqs = 0;
  String syncStep = 'Preparing BOQs';
  bool slowSync = false;
  Timer? slowTimer;
  final initialReady = <int>{};
  bool initialSettled = false;
  bool certificateKnown = false;
  Timer? initialTimeout;
  bool get initialLoading => initialReady.length < widget.initialSources.length;

  Future<T> readStep<T>(String label, Future<T> operation) {
    if (mounted) setState(() => syncStep = label);
    return operation.timeout(const Duration(seconds: 30), onTimeout: () {
      throw TimeoutException('$label took too long. Check your connection and retry.');
    });
  }

  /// Read each collection from the shared session, without opening another
  /// first-event listener when the data is already in memory. For collections
  /// that have not loaded, wait for the shared stream with a bounded timeout.
  Future<QuerySnapshot<Map<String, dynamic>>> readItems(
    String label,
    Query<Map<String, dynamic>> query,
  ) async {
    final cached = query.stateSnapshot;
    bool usable(QuerySnapshot<Map<String, dynamic>> snapshot) =>
        snapshot.docs.isNotEmpty || !snapshot.metadata.isFromCache;
    if (cached != null && usable(cached)) return cached;
    // An empty offline query may mean it has never been downloaded, not that
    // the collection is empty. Do not use it to recalculate saved totals.
    return readStep(label, query.stateSnapshots().firstWhere(usable));
  }

  void writeStep(String label) {
    if (mounted) setState(() => syncStep = label);
  }
  String? error;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.initialSources.length; i++) {
      final index = i;
      subscriptions.add(widget.initialSources[i].listen((_) {
        if (!mounted || initialReady.contains(index)) return;
        setState(() => initialReady.add(index));
        if (!initialLoading) {
          if (certificateKnown && !draft) setState(() => initialSettled = true);
          schedule();
        }
      }, onError: (Object e) {
        if (!mounted) return;
        setState(() { initialReady.add(index); initialSettled = true; });
        failed(e);
      }));
    }
    initialTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && initialLoading) setState(() {
        initialSettled = true;
        error = 'Initial IPC data did not finish loading. Reopen the page to retry.';
      });
    });
    subscriptions.add(widget.certificate.stateSnapshots().listen((s) {
      final wasDraft = draft;
      certificateKnown = true;
      draft = ipcCanSyncTakeoff(s.data());
      if (!draft && !initialLoading && mounted) setState(() => initialSettled = true);
      if (draft && !wasDraft) schedule();
    }, onError: failed));
    subscriptions.add(widget.certificate.collection('boqs').stateSnapshots().listen((s) {
      for (final p in s.docs) {
        boqNames[p.id] = '${p.data()['buildingName'] ?? p.data()['name'] ?? 'BOQ'}';
        if (sources.containsKey(p.id)) continue;
        final building = widget.certificate.parent.parent!.collection('buildings').doc(p.id);
        sources[p.id] = [for (final collection in ['boq', 'boqItems', 'measurements'])
          building.collection(collection).stateSnapshots().listen((_) => schedule(), onError: failed)];
      }
    }, onError: failed));
    // Warm every package independently of valuation sync. A slow first BOQ
    // must not prevent later BOQs (or submitted/certified IPCs) being cached.
    for (final collection in ['boqs', 'externalBoqs']) {
      subscriptions.add(widget.certificate.collection(collection).stateSnapshots().listen((snapshot) {
        for (final package in snapshot.docs) {
          if (!prefetchedPackages.add(package.reference.path)) continue;
          subscriptions.add(package.reference.collection('items').stateSnapshots().listen((_) {}, onError: failed));
          subscriptions.add(package.reference.collection('measurementSheetSettings').doc('details').stateSnapshots().listen((_) {}, onError: failed));
        }
      }, onError: failed));
    }
  }

  void failed(Object e) {
    final reason = e is FirebaseException ? '${e.code}: ${e.message ?? 'Request failed'}' : '$e';
    if (mounted) setState(() => error = 'BOQ sync failed: $reason');
  }

  void schedule() {
    if (!draft || !mounted || initialLoading) return;
    dirty = true;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), sync);
  }

  Future<void> sync() async {
    if (running || !draft || !mounted) return;
    debounce?.cancel();
    setState(() {
      running = true;
      completedBoqs = 0;
      failedBoqs = 0;
      totalBoqs = sources.length;
      slowSync = false;
    });
    slowTimer?.cancel();
    slowTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && running) setState(() => slowSync = true);
    });
    final failures = <String>[];
    try {
      do {
        dirty = false;
        final ids = sources.keys.toList();
        if (mounted) setState(() {
          completedBoqs = 0;
          failedBoqs = 0;
          totalBoqs = ids.length;
        });
        for (final id in ids) {
          if (!draft || !mounted) break;
          setState(() => currentBoq = boqNames[id] ?? 'BOQ');
          try {
          final building = widget.certificate.parent.parent!.collection('buildings').doc(id);
          var source = await readItems('Reading source BOQ', building.collection('boq'));
          if (source.docs.isEmpty) source = await readItems('Reading source BOQ items', building.collection('boqItems'));
          final rows = {for (final d in source.docs) d.id: d.data()};
          final qty = ipcBoqQuantities(rows, (await readItems('Reading measurements', building.collection('measurements'))).docs.map((d) => d.data()).toList());
          final package = widget.certificate.collection('boqs').doc(id);
          final items = (await readItems('Reading saved IPC items from state', package.collection('items'))).docs;
          final updatedRows = {for (final item in items) item.id: item.data()};
          final changed = items.where((item) {
            final src = rows[item.id];
            final q = qty[item.id];
            if (src == null || q == null) return false;
            return ipcTakeoffPatch(src, q).entries.any((e) => item.data()[e.key] != e.value);
          }).toList();
          // Keep transactions small: only changed rows need fresh reads.
          for (var offset = 0; offset < changed.length; offset += 20) {
            writeStep('Saving changed items ${offset + 1}–${(offset + 20).clamp(0, changed.length)} of ${changed.length}');
            final applied = await widget.certificate.firestore.runTransaction<Map<String, Map<String, dynamic>>?>((tx) async {
              final cert = (await tx.get(widget.certificate)).data();
              if (!ipcCanSyncTakeoff(cert)) return null;
              final pack = (await tx.get(package)).data();
              if (pack == null) return null;
              final appliedRows = <String, Map<String, dynamic>>{};
              final fresh = <DocumentSnapshot<Map<String, dynamic>>>[];
              for (final item in changed.skip(offset).take(20)) {
                fresh.add(await tx.get(item.reference));
              }
              double cumulativeDelta = 0, previousDelta = 0;
              for (final item in fresh) {
                final src = rows[item.id];
                final old = item.data();
                if (src == null || old == null || qty[item.id] == null) continue;
                final q = qty[item.id]!;
                final patch = ipcTakeoffPatch(src, q);
                if (patch.entries.every((e) => old[e.key] == e.value)) continue;
                final rateChange = _number(src['rate']) - _number(old['rate']);
                cumulativeDelta += _number(old['cumulativeExecutedQuantity']) * rateChange;
                previousDelta += _number(old['previousExecutedQuantity']) * rateChange;
                tx.update(item.reference, patch);
                appliedRows[item.id] = {...old, ...patch};
              }
              if (cumulativeDelta != 0 || previousDelta != 0) {
                tx.update(package, {
                  'executedAmount': _number(pack['executedAmount']) + cumulativeDelta,
                  'previousExecutedAmount': _number(pack['previousExecutedAmount']) + previousDelta,
                });
                final excluded = List<String>.from(cert!['excluded'] ?? []);
                if (!excluded.contains('building:$id')) {
                  final gross = _number(cert['grossWorkValue']) + cumulativeDelta - previousDelta;
                  final terms = Map<String, dynamic>.from(cert['terms'] ?? {});
                  final deductions = terms.isEmpty ? <String, double>{} : calculateIpcDeductions(
                    gross: gross, contract: _number(terms['contractPrice']),
                    advancePercent: _number(terms['advancePercent']), recoveryPercent: _number(terms['recoveryPercent']),
                    retentionPercent: _number(terms['retentionPercent']), retentionLimitPercent: _number(terms['retentionLimitPercent']),
                    recovered: _number(cert['advancePaymentRecovered']) - _number(cert['advanceRecovery']),
                    retained: _number(cert['retentionHeld']) - _number(cert['retentionDeduction']),
                    advance: cert['ipcType'] == 'advance',
                  );
                  tx.update(widget.certificate, {
                    'grossWorkValue': gross, ...deductions,
                    'cumulativeExecutedAmount': _number(cert['cumulativeExecutedAmount']) + cumulativeDelta,
                    'previousExecutedAmount': _number(cert['previousExecutedAmount']) + previousDelta,
                    'calculatedAmountApplied': deductions['amountApplied'] ?? gross,
                    'amountApplied': cert['enteredAmountApplied'] ?? deductions['amountApplied'] ?? gross,
                  });
                }
              }
              return appliedRows;
            });
            if (applied == null) break;
            updatedRows.addAll(applied);
          }
          final total = updatedRows.values.fold<double>(0, (sum, r) {
            final type = '${r['rowType'] ?? ''}';
            if (type.isNotEmpty && type != 'item') return sum;
            return sum + (double.tryParse('${r['qtyOverride'] ?? r['quantity']}') ?? 0) * (double.tryParse('${r['rate']}') ?? 0);
          });
          writeStep('Updating BOQ totals');
          await widget.certificate.firestore.runTransaction((tx) async {
            final cert = (await tx.get(widget.certificate)).data();
            final pack = (await tx.get(package)).data();
            if (!ipcCanSyncTakeoff(cert) || pack == null) return;
            final percent = total == 0 ? 0.0 : _number(pack['executedAmount']) / total * 100;
            if (pack['contractValue'] == total && pack['executedPercent'] == percent) return;
            tx.update(package, {'contractValue': total, 'executedPercent': percent});
          });
          } catch (e) {
            failedBoqs++;
            final reason = e is FirebaseException ? '${e.code}: ${e.message ?? ''}' : '$e';
            failures.add('${boqNames[id] ?? 'BOQ'}: $reason');
            if (e is TimeoutException || (e is FirebaseException && e.code == 'resource-exhausted')) {
              dirty = false;
              break;
            }
          } finally {
            if (mounted) setState(() => completedBoqs++);
          }
        }
      } while (dirty && draft && mounted);
      if (mounted) setState(() => error = failures.isEmpty ? null : 'Some BOQs could not sync. ${failures.join('; ')}');
    } catch (e) { failed(e); }
    finally { slowTimer?.cancel(); if (mounted) setState(() { running = false; initialSettled = true; }); else running = false; }
  }

  @override
  void dispose() {
    debounce?.cancel();
    slowTimer?.cancel();
    initialTimeout?.cancel();
    for (final s in [...subscriptions, ...sources.values.expand((v) => v)]) { s.cancel(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IpcLoadingOverlay(loading: (!initialSettled || running) && !slowSync,
    progress: totalBoqs > 0 ? completedBoqs / totalBoqs : null,
    detail: totalBoqs > 0
        ? '$completedBoqs of $totalBoqs BOQs processed${failedBoqs > 0 ? ' · $failedBoqs failed' : ''}\n$currentBoq · $syncStep'
        : 'Preparing BOQs…',
    message: initialLoading ? 'Loading IPC data…' : 'Updating IPC BOQ values…', child: Column(children: [
    if (running && slowSync) Material(color: const Color(0xFFFFF3E0), child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text('Sync is taking longer than expected: $syncStep. $completedBoqs of $totalBoqs BOQs processed. Values may be out of date. Avoid editing until sync finishes; no duplicate sync will be started.'),
    )),
    if (error != null) Material(color: const Color(0xFFFFF3E0), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text(error!)), TextButton(onPressed: running || initialLoading ? null : schedule, child: const Text('Retry sync'))]))),
    Expanded(child: widget.child),
  ]));
}
