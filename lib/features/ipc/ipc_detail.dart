import 'package:aqs/core/state/firestore_state.dart';
import 'ipc_summary_page.dart';
import 'ipc_certificate_page.dart';
import 'ipc_certificate_amount.dart';
import 'ipc_gross_summary_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ipc_dashboard.dart';
import 'ipc_boq_valuation.dart';
import 'ipc_boq_table.dart';
import 'ipc_deductions.dart';
import 'ipc_site_breakdown.dart';
import 'ipc_site_filter.dart';
import 'ipc_draft_link.dart';
import 'ipc_shared_cost_picker.dart';
import 'execution_outbox.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class IpcDetail extends StatelessWidget {
  const IpcDetail({super.key, required this.certificate});
  final DocumentReference<Map<String, dynamic>> certificate;
  static const blue = Color(0xFF1557E8);
  static const navy = Color(0xFF172B4D);

  Future<void> _addNonMeasured(BuildContext context) async {
    final name = TextEditingController(),
        description = TextEditingController(),
        value = TextEditingController();
    final form = GlobalKey<FormState>();
    var category = 'Preliminaries';
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialog) => StatefulBuilder(
            builder:
                (context, update) => AlertDialog(
                  title: const Text('Add non-measured BOQ'),
                  content: SizedBox(
                    width: 520,
                    child: Form(
                      key: form,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButtonFormField<String>(
                              value: category,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                              items:
                                  [
                                        'Preliminaries',
                                        'Prime Costs',
                                        'Provisional Sums',
                                        'Variations',
                                      ]
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(c),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  busy
                                      ? null
                                      : (v) => update(() => category = v!),
                            ),
                            TextFormField(
                              controller: name,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'BOQ name',
                              ),
                              validator:
                                  (v) =>
                                      (v ?? '').trim().isEmpty
                                          ? 'Enter a name.'
                                          : null,
                            ),
                            TextFormField(
                              controller: description,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'Item description',
                              ),
                              minLines: 2,
                              maxLines: 4,
                              validator:
                                  (v) =>
                                      (v ?? '').trim().isEmpty
                                          ? 'Enter a description.'
                                          : null,
                            ),
                            TextFormField(
                              controller: value,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'Full BOQ value (TZS)',
                              ),
                              keyboardType: TextInputType.number,
                              validator:
                                  (v) =>
                                      !ipcNumber(v).isFinite ||
                                              ipcNumber(v) <= 0
                                          ? 'Enter a value greater than zero.'
                                          : null,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Execution is entered as a percentage of this value. 100% represents the full BOQ value.',
                            ),
                            if (error != null)
                              Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(dialog),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          busy
                              ? null
                              : () async {
                                if (!form.currentState!.validate()) return;
                                update(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  final history =
                                      await certificate.parent.get();
                                  final target =
                                      certificate
                                          .collection('externalBoqs')
                                          .doc();
                                  final result = await FirebaseFirestore
                                      .instance
                                      .runTransaction<String?>((tx) async {
                                        final c =
                                            (await tx.get(certificate)).data();
                                        if (c == null ||
                                            c['isDeleted'] == true ||
                                            ![
                                              'draft',
                                              'submitted',
                                            ].contains(c['status']) ||
                                            c['ipcType'] == 'advance')
                                          return 'Add BOQs only to a draft or submitted work IPC.';
                                        if (history.docs.any(
                                          (d) =>
                                              d.id != certificate.id &&
                                              d.data()['isDeleted'] != true &&
                                              ipcNumber(d.data()['number']) >
                                                  ipcNumber(c['number']),
                                        ))
                                          return 'Add BOQs to the latest IPC only.';
                                        tx.set(target, {
                                          'name': name.text.trim(),
                                          'category': category,
                                          'executionMode': 'percentage',
                                          'contractValue': ipcNumber(
                                            value.text,
                                          ),
                                          'executedAmount': 0,
                                          'executedPercent': 0,
                                          'previousExecutedAmount': 0,
                                        });
                                        tx.set(
                                          target.collection('items').doc('1'),
                                          {
                                            'boqCode': '1',
                                            'description':
                                                description.text.trim(),
                                            'rowType': 'item',
                                            'order': 1,
                                            'unit': '%',
                                            'quantity': 100,
                                            'rate': ipcNumber(value.text) / 100,
                                            'previousExecutedQuantity': 0,
                                            'cumulativeExecutedQuantity': 0,
                                          },
                                        );
                                        return null;
                                      });
                                  if (result != null) throw StateError(result);
                                  if (dialog.mounted) Navigator.pop(dialog);
                                } catch (e) {
                                  if (context.mounted)
                                    update(() {
                                      busy = false;
                                      error = '$e';
                                    });
                                }
                              },
                      child: Text(busy ? 'Saving…' : 'Add BOQ'),
                    ),
                  ],
                ),
          ),
    );
    name.dispose();
    description.dispose();
    value.dispose();
  }

  Future<void> syncExecution(
    DocumentReference<Map<String, dynamic>> package,
    String itemId,
    String rfi,
    String sheet,
    double qty, {
    double? rawQuantity,
    double factor = 1,
    String correctionReason = '',
    String? entryId,
    bool delete = false,
    required String operationId,
    required String owner,
    bool newEntry = false,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != owner) {
      throw StateError('Sign in with the account that saved this quantity.');
    }
    if (!delete &&
        (!qty.isFinite ||
            qty == 0 ||
            !factor.isFinite ||
            factor <= 0 ||
            !(rawQuantity ?? qty).isFinite ||
            (rawQuantity ?? qty) == 0)) {
      throw StateError('Enter a valid non-zero quantity and positive factor.');
    }
    if (!delete && qty < 0 && correctionReason.trim().isEmpty) {
      throw StateError('A reason is required for a negative correction.');
    }
    final history = await certificate.parent.get();
    final item = package.collection('items').doc(itemId);
    final entry = item.collection('executionEntries').doc(entryId);
    final error = await FirebaseFirestore.instance.runTransaction<String?>((
      tx,
    ) async {
      final cert = (await tx.get(certificate)).data();
      final pack = (await tx.get(package)).data();
      final row = (await tx.get(item)).data();
      final oldEntry = entryId == null ? null : (await tx.get(entry)).data();
      if ((oldEntry?['appliedOperationIds'] as List? ?? []).contains(
        operationId,
      ))
        return null;
      if (FirebaseAuth.instance.currentUser?.uid != owner)
        return 'Account changed during sync.';
      if (!newEntry &&
          entryId != null &&
          (oldEntry == null || oldEntry['isDeleted'] == true))
        return 'This entry is no longer available.';
      if (cert == null ||
          pack == null ||
          row == null ||
          cert['isDeleted'] == true)
        return 'IPC or item is unavailable.';
      if (!['draft', 'submitted'].contains(cert['status']) ||
          cert['ipcType'] == 'advance')
        return 'Only draft or submitted work IPCs can record quantities.';
      if (history.docs.any(
        (d) =>
            d.id != certificate.id &&
            d.data()['isDeleted'] != true &&
            ipcNumber(d.data()['number']) > ipcNumber(cert['number']),
      ))
        return 'A later IPC exists. Edit the latest IPC to protect carried-forward quantities.';
      final values = ipcItemExecution(row, pack);
      if (values.first == null || values.last == null)
        return 'This older BOQ has building-level execution only. Its item-level opening quantities must be reconciled before adding work.';
      final change = (delete ? 0 : qty) - ipcNumber(oldEntry?['quantity']);
      final cumulative = values.last! + change;
      if (pack['executionMode'] == 'percentage' && cumulative > 100.000001)
        return 'Cumulative execution cannot exceed 100%.';
      if (cumulative < -0.000001)
        return 'Correction cannot reduce cumulative work below zero.';
      final delta = change * ipcNumber(row['rate']);
      final executed = ipcNumber(pack['executedAmount']) + delta;
      final gross = ipcNumber(cert['grossWorkValue']) + delta;
      final terms = Map<String, dynamic>.from(cert['terms'] ?? {});
      final deductions =
          terms.isEmpty
              ? <String, double>{}
              : calculateIpcDeductions(
                gross: gross,
                contract: ipcNumber(terms['contractPrice']),
                advancePercent: ipcNumber(terms['advancePercent']),
                recoveryPercent: ipcNumber(terms['recoveryPercent']),
                retentionPercent: ipcNumber(terms['retentionPercent']),
                retentionLimitPercent: ipcNumber(
                  terms['retentionLimitPercent'],
                ),
                recovered:
                    ipcNumber(cert['advancePaymentRecovered']) -
                    ipcNumber(cert['advanceRecovery']),
                retained:
                    ipcNumber(cert['retentionHeld']) -
                    ipcNumber(cert['retentionDeduction']),
              );
      tx.set(entry, {
        'appliedOperationIds': FieldValue.arrayUnion([operationId]),
        'rfiNumber': rfi,
        'measurementSheetNumber': sheet,
        'quantity': qty,
        if (!delete) 'rawQuantity': rawQuantity ?? qty,
        if (!delete) 'factor': factor,
        if (!delete) 'correctionReason': correctionReason.trim(),
        if (!delete) 'isCorrection': qty < 0,
        if (newEntry) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isDeleted': delete,
      }, SetOptions(merge: true));
      tx.update(item, {
        'lastExecutionOperationId': operationId,
        'previousExecutedQuantity': values.first,
        if (!delete) 'executionFactor': factor,
        'cumulativeExecutedQuantity': cumulative,
      });
      tx.update(package, {
        'executedAmount': executed,
        'itemExecutionBaselineZero':
            pack['itemExecutionBaselineZero'] == true ||
            ipcNumber(pack['executedAmount']) == 0,
        'executedPercent':
            ipcNumber(pack['contractValue']) == 0
                ? 0
                : executed / ipcNumber(pack['contractValue']) * 100,
      });
      tx.update(certificate, {
        ...deductions,
        'grossWorkValue': gross,
        'cumulativeExecutedAmount':
            ipcNumber(cert['cumulativeExecutedAmount']) + delta,
        'calculatedAmountApplied': deductions['amountApplied'] ?? gross,
        // Keep the QS-entered application amount separate from measured work.
        'amountApplied':
            cert['enteredAmountApplied'] ??
            deductions['amountApplied'] ??
            gross,
      });
      return null;
    });
    if (error != null) throw StateError(error);
  }

  Future<void> _queueExecution(
    DocumentReference<Map<String, dynamic>> package,
    Map<String, dynamic> row,
    Map<String, dynamic> details,
    Map<String, dynamic> loadedCertificate,
    String rfi,
    String sheet,
    double qty,
  ) async {
    final deleting = row['_delete'] == true;
    final factor = (row['_factor'] as num?)?.toDouble() ?? 1;
    final raw = (row['_rawQuantity'] as num?)?.toDouble() ?? qty;
    final reason = '${row['_correctionReason'] ?? ''}'.trim();
    if (!deleting &&
        (!qty.isFinite ||
            qty == 0 ||
            !raw.isFinite ||
            raw == 0 ||
            !factor.isFinite ||
            factor <= 0)) {
      throw StateError('Enter a valid non-zero quantity and positive factor.');
    }
    if (!deleting && qty < 0 && reason.isEmpty)
      throw StateError('A correction reason is required.');
    final cert = certificate.stateSnapshot?.data() ?? loadedCertificate;
    if (!ipcCanSyncTakeoff(cert) || cert?['ipcType'] == 'advance') {
      throw StateError(
        'Only loaded draft or submitted work IPCs can record quantities.',
      );
    }
    final values = ipcItemExecution(row, details);
    if (values.first == null || values.last == null)
      throw StateError('Item opening quantities must be reconciled first.');
    final old = ipcNumber(row['_oldEntryQuantity']);
    final delta = (deleting ? 0 : qty) - old;
    final cumulative = values.last! + delta;
    if (cumulative < -0.000001 ||
        (details['executionMode'] == 'percentage' && cumulative > 100.000001)) {
      throw StateError(
        'The correction would put cumulative execution outside its allowed range.',
      );
    }
    await executionOutbox.enqueue({
      'id': const Uuid().v4(),
      'certificate': certificate.path,
      'package': package.path,
      'item': row['_itemId'],
      'entry': row['_entryId'] ?? const Uuid().v4(),
      'newEntry': row['_entryId'] == null,
      'rfi': rfi,
      'sheet': sheet,
      'quantity': qty,
      'rawQuantity': raw,
      'factor': factor,
      'reason': reason,
      'delete': deleting,
      'delta': delta,
      'baseCumulative': values.last,
      'label': '${details['name'] ?? 'BOQ'} · ${row['code'] ?? row['_itemId']}',
    });
  }

  Future<void> _refreshValues(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Correct BOQ snapshot values?'),
            content: const Text(
              'Reload building BOQs using current report quantities. This updates BOQ snapshot rows and values only; executed work and certificate payment amounts remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Correct values'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      final project = certificate.parent.parent!;
      for (final package in (await certificate.collection('boqs').get()).docs) {
        final building = project.collection('buildings').doc(package.id);
        if (!(await building.get()).exists) continue;
        await snapshotMeasuredBoq(building, package.reference);
      }
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BOQ values corrected from current report quantities.',
            ),
          ),
        );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not finish correction. Please retry.'),
          ),
        );
    }
  }

  void _openBoq(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> package,
    String sheetIpcNumber,
    String siteName,
    Map<String, dynamic> loadedCertificate,
  ) {
    final details = Map<String, dynamic>.from(package.data());
    details['siteName'] = siteName;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              appBar: AppBar(
                title: Text(
                  '${package.data()['name'] ?? 'BOQ'} · IPC snapshot',
                ),
              ),
              body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                initialData:
                    package.reference.collection('items').stateSnapshot,
                stream: package.reference.collection('items').stateSnapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return const Center(
                      child: Text(
                        'Could not load this BOQ. Please reopen it to retry.',
                      ),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final rows =
                      snapshot.data!.docs.toList()..sort(
                        (a, b) => ipcNumber(
                          a.data()['order'],
                        ).compareTo(ipcNumber(b.data()['order'])),
                      );
                  if (rows.isEmpty)
                    return Center(
                      child: Text(
                        snapshot.data!.metadata.isFromCache
                            ? 'BOQ items are not available offline yet.\nConnect to the internet to load them into shared state.'
                            : 'No BOQ items were saved in this IPC.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream:
                        package.reference
                            .collection('measurementSheetSettings')
                            .doc('details')
                            .stateSnapshots(),
                    builder:
                        (context, settingsSnapshot) => ListenableBuilder(
                          listenable: executionOutbox,
                          builder:
                              (context, _) => Column(
                                children: [
                                  Expanded(
                                    child: IpcBoqTable(
                                      sheetDetails:
                                          settingsSnapshot.data?.data() ??
                                          const {},
                                      onSaveSheetDetails: (details) async {
                                        await package.reference
                                            .collection(
                                              'measurementSheetSettings',
                                            )
                                            .doc('details')
                                            .set(
                                              details,
                                              SetOptions(merge: true),
                                            );
                                      },
                                      rows:
                                          rows
                                              .map(
                                                (doc) =>
                                                    executionOutbox.projectRow(
                                                      package.reference.path,
                                                      {
                                                        ...doc.data(),
                                                        '_itemId': doc.id,
                                                      },
                                                    ),
                                              )
                                              .toList(),
                                      package: details,
                                      ipcNumber: sheetIpcNumber,
                                      entries:
                                          (row) => executionOutbox.entries(
                                            package.reference.path,
                                            row['_itemId'] as String,
                                            package.reference
                                                .collection('items')
                                                .doc(row['_itemId'] as String)
                                                .collection('executionEntries')
                                                .stateSnapshots()
                                                .map(
                                                  (s) =>
                                                      s.docs
                                                          .where(
                                                            (d) =>
                                                                d.data()['isDeleted'] !=
                                                                true,
                                                          )
                                                          .map(
                                                            (d) => {
                                                              ...d.data(),
                                                              '_entryId': d.id,
                                                            },
                                                          )
                                                          .toList(),
                                                ),
                                          ),
                                      onExecute:
                                          (row, rfi, sheet, qty) =>
                                              _queueExecution(
                                                package.reference,
                                                row,
                                                details,
                                                loadedCertificate,
                                                rfi,
                                                sheet,
                                                qty,
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                        ),
                  );
                },
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IpcDraftLink(
    key: ValueKey(certificate.path),
    certificate: certificate,
    initialSources: [
      certificate.stateSnapshots(),
      certificate.collection('boqs').stateSnapshots(),
      certificate.collection('externalBoqs').stateSnapshots(),
      certificate.parent.parent!.collection('sites').stateSnapshots(),
      certificate.parent.parent!.collection('buildings').stateSnapshots(),
    ],
    child: _content(context),
  );

  Widget _content(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: certificate.stateSnapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const Center(child: Text('Could not load IPC.'));
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!.data();
      if (data == null || data['isDeleted'] == true)
        return const Center(child: Text('IPC is no longer available.'));
      final metrics = [
        (
          'Amount applied',
          'amountApplied',
          Icons.account_balance_wallet_outlined,
          blue,
        ),
        (
          'Gross work',
          'grossWorkValue',
          Icons.domain_outlined,
          const Color(0xFF008777),
        ),
        (
          'Advance recovery',
          'advanceRecovery',
          Icons.currency_exchange,
          const Color(0xFF7955CA),
        ),
        (
          'Retention',
          'retentionDeduction',
          Icons.shield_outlined,
          const Color(0xFFC78113),
        ),
        (
          'This IPC value',
          'thisIpcValue',
          Icons.receipt_long_outlined,
          const Color(0xFF087F5B),
        ),
        (
          'Advance balance',
          'advanceOutstanding',
          Icons.payments_outlined,
          const Color(0xFF087EB2),
        ),
      ];
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: certificate.parent.stateSnapshots(),
        builder: (context, historySnapshot) {
          final history =
              historySnapshot.data?.docs.map((doc) => doc.data()).toList();
          final certificateValue =
              history == null ? null : ipcCertificatePayable(data, history);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 12,
                children: [
                  const Text(
                    'Certificate overview',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _refreshValues(context),
                    icon: const Icon(Icons.sync),
                    label: const Text('Correct BOQ values'),
                  ),
                  Chip(
                    avatar: Icon(
                      ipcCanSyncTakeoff(data)
                          ? Icons.edit_outlined
                          : Icons.lock_outline,
                      size: 18,
                    ),
                    label: Text(
                      '${data['status'] ?? 'Submitted'} · ${ipcCanSyncTakeoff(data) ? 'QS editable' : 'Read-only'}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Payment values for this period and the BOQs included in this certificate.',
                style: TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 24),
              IpcSiteBreakdownScope(
                certificate: certificate,
                data: data,
                builder:
                    (siteWeights) => LayoutBuilder(
                      builder: (context, c) {
                        final columns =
                            c.maxWidth >= 1800
                                ? 6
                                : c.maxWidth >= 850
                                ? 3
                                : c.maxWidth >= 550
                                ? 2
                                : 1;
                        final cards =
                            metrics
                                .map(
                                  (m) => Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE2E9F3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(9),
                                              decoration: BoxDecoration(
                                                color: m.$4.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                m.$3,
                                                color: m.$4,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                m.$1,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF52627A),
                                                ),
                                              ),
                                            ),
                                            if (m.$2 == 'thisIpcValue' ||
                                                m.$2 == 'grossWorkValue') ...[
                                              const SizedBox(width: 8),
                                              OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                  textStyle: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  foregroundColor: m.$4,
                                                ),
                                                onPressed:
                                                    () => Navigator.of(
                                                      context,
                                                    ).push(
                                                      MaterialPageRoute(
                                                        builder:
                                                            (_) =>
                                                                m.$2 == 'grossWorkValue'
                                                                    ? IpcGrossSummaryPage(
                                                                      certificate:
                                                                          certificate,
                                                                    )
                                                                    : IpcCertificatePage(
                                                                      certificate:
                                                                          certificate,
                                                                    ),
                                                      ),
                                                    ),
                                                child: const Text(
                                                  'View Details',
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            ipcMoney(
                                              m.$2 == 'thisIpcValue'
                                                  ? certificateValue ??
                                                      'Complete Item 7'
                                                  : data[m.$2],
                                            ),
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              color: m.$4,
                                            ),
                                          ),
                                        ),
                                        if (m.$2 != 'amountApplied')
                                          IpcSiteLines(
                                            weights: siteWeights,
                                            gross: m.$2 == 'grossWorkValue',
                                            total:
                                                m.$2 == 'thisIpcValue'
                                                    ? (certificateValue ?? 0.0)
                                                    : ipcNumber(data[m.$2]),
                                          ),
                                        if (m.$2 == 'amountApplied')
                                          const Padding(
                                            padding: EdgeInsets.only(top: 18),
                                            child: Text(
                                              'QS application amount\nRecorded separately from measured work.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.6,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList();
                        return Column(
                          children: [
                            for (
                              var start = 0;
                              start < cards.length;
                              start += columns
                            )
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var j = 0; j < columns; j++) ...[
                                        if (j > 0) const SizedBox(width: 16),
                                        Expanded(
                                          child:
                                              start + j < cards.length
                                                  ? cards[start + j]
                                                  : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
              ),
              const SizedBox(height: 32),
              for (final type in ['boqs', 'externalBoqs'])
                IpcSiteFilter(
                  project: certificate.parent.parent!,
                  enabled: type == 'boqs',
                  builder:
                      (
                        includesSite,
                        siteLabel,
                        siteFilter,
                      ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: certificate.collection(type).stateSnapshots(),
                        builder: (context, packages) {
                          if (packages.hasError)
                            return const Text('Could not load BOQ cards.');
                          if (!packages.hasData)
                            return const LinearProgressIndicator();
                          final excluded = List<String>.from(
                            data['excluded'] ?? [],
                          );
                          final docs =
                              packages.data!.docs
                                  .where(
                                    (doc) =>
                                        (type != 'boqs' ||
                                            includesSite(doc.id)) &&
                                        !excluded.contains(
                                          '${type == 'boqs' ? 'building' : 'external'}:${doc.id}',
                                        ),
                                  )
                                  .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final heading = Text(
                                    '${type == 'boqs' ? 'Measured Works BOQs' : 'Non-measured Works BOQs'} (${docs.length})',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.bold,
                                      color: navy,
                                    ),
                                  );
                                  if (siteFilter == null) return heading;
                                  if (constraints.maxWidth < 650) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        heading,
                                        const SizedBox(height: 16),
                                        siteFilter,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: heading),
                                      const SizedBox(width: 24),
                                      siteFilter,
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              if (type == 'externalBoqs')
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        final manual = await showDialog<bool>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder:
                                              (_) => IpcSharedCostPicker(
                                                certificate: certificate,
                                              ),
                                        );
                                        if (manual == true && context.mounted)
                                          await _addNonMeasured(context);
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add non-measured BOQ'),
                                    ),
                                  ),
                                ),
                              if (docs.isEmpty)
                                const Text(
                                  'No BOQs match this section or site filter.',
                                  style: TextStyle(color: Colors.blueGrey),
                                ),
                              LayoutBuilder(
                                builder: (context, c) {
                                  final columns =
                                      c.maxWidth >= 1100
                                          ? 3
                                          : c.maxWidth >= 700
                                          ? 2
                                          : 1;
                                  return Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children:
                                        docs.map((doc) {
                                          final row = doc.data();
                                          final percent = ipcNumber(
                                            row['executedPercent'],
                                          );
                                          return SizedBox(
                                            width:
                                                (c.maxWidth -
                                                    16 * (columns - 1)) /
                                                columns,
                                            child: Card(
                                              margin: EdgeInsets.zero,
                                              color: Colors.white,
                                              clipBehavior: Clip.antiAlias,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                side: const BorderSide(
                                                  color: Color(0xFFE2E9F3),
                                                ),
                                              ),
                                              child: InkWell(
                                                onTap:
                                                    () => _openBoq(
                                                      context,
                                                      doc,
                                                      '${data['number'] ?? ''}',
                                                      siteLabel(doc.id),
                                                      data,
                                                    ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    22,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .domain_outlined,
                                                            color: blue,
                                                            size: 28,
                                                          ),
                                                          const SizedBox(
                                                            width: 12,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              '${row['name'] ?? 'BOQ'}',
                                                              style: const TextStyle(
                                                                fontSize: 17,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: navy,
                                                              ),
                                                            ),
                                                          ),
                                                          const Icon(
                                                            Icons.arrow_forward,
                                                            color: blue,
                                                            size: 20,
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Row(
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .location_on_outlined,
                                                            size: 14,
                                                            color:
                                                                Colors.blueGrey,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              siteLabel(doc.id),
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    Colors
                                                                        .blueGrey,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      Text(
                                                        'Work executed · ${percent.toStringAsFixed(2)}%',
                                                        style: const TextStyle(
                                                          color:
                                                              Colors.blueGrey,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      LinearProgressIndicator(
                                                        value: (percent / 100)
                                                            .clamp(0, 1),
                                                        minHeight: 6,
                                                        color: blue,
                                                        backgroundColor:
                                                            const Color(
                                                              0xFFEAF0FC,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 18,
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          ipcMoney(
                                                            row['executedAmount'],
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 22,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: navy,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      const Text(
                                                        'BOQ value',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.blueGrey,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment:
                                                            Alignment
                                                                .centerLeft,
                                                        child: Text(
                                                          ipcMoney(
                                                            row['contractValue'],
                                                          ),
                                                          maxLines: 1,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 20,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: navy,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 18,
                                                      ),
                                                      const Text(
                                                        'Open BOQ →',
                                                        style: TextStyle(
                                                          color: blue,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 28),
                            ],
                          );
                        },
                      ),
                ),
            ],
          );
        },
      );
    },
  );
}
