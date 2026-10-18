import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'ipc_page.dart';
import 'ipc_overview.dart';
import 'ipc_detail.dart';
import 'ipc_dates.dart';
import 'ipc_boq_valuation.dart';
import 'ipc_work_setup.dart';
import 'ipc_advance_review.dart';
import 'ipc_deductions.dart';

double ipcNumber(dynamic value) =>
    double.tryParse('$value'.replaceAll(',', '')) ?? 0;
String ipcMoney(dynamic value) =>
    'TZS ${NumberFormat('#,##0.00').format(ipcNumber(value))}';

/// Certificates own BOQ snapshots; source project documents are never changed.
class IpcStore {
  static CollectionReference<Map<String, dynamic>> certificates(
    String project,
  ) => FirebaseFirestore.instance
      .collection('projects')
      .doc(project)
      .collection('ipcs');

  static Future<void> copyRows(
    CollectionReference<Map<String, dynamic>> source,
    CollectionReference<Map<String, dynamic>> target,
  ) async {
    final rows = (await source.get()).docs;
    for (var offset = 0; offset < rows.length; offset += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in rows.skip(offset).take(400)) {
        batch.set(target.doc(row.id), {
          ...row.data(),
          if (row.data()['cumulativeExecutedQuantity'] != null)
            'previousExecutedQuantity':
                row.data()['cumulativeExecutedQuantity'],
        });
      }
      await batch.commit();
    }
  }

  static Future<String> prepare(
    String project, {
    Map<String, dynamic>? terms,
    Map<String, dynamic>? application,
  }) async {
    final collection = certificates(project);
    final all =
        (await collection.get()).docs
            .where((doc) => doc.data()['isDeleted'] != true)
            .toList();
    final drafts = all.where((doc) => doc.data()['status'] == 'draft').toList();
    if (drafts.isNotEmpty) {
      if (application != null) await drafts.first.reference.update(application);
      return drafts.first.id;
    }
    if (all.isEmpty && terms == null)
      throw StateError('Set advance payment and retention terms first.');
    final submitted =
        all.where((doc) => doc.data()['submittedAt'] is Timestamp).toList()
          ..sort(
            (a, b) => (b.data()['submittedAt'] as Timestamp).compareTo(
              a.data()['submittedAt'] as Timestamp,
            ),
          );
    final previous = submitted.isEmpty ? null : submitted.first;
    final destination = collection.doc();
    // Allocate unique certificate numbers even when two users prepare concurrently.
    final projectRef = collection.parent!;
    final number = await FirebaseFirestore.instance.runTransaction<int>((
      transaction,
    ) async {
      final state = await transaction.get(projectRef);
      final existingMax = all.fold<int>(
        0,
        (max, doc) =>
            ipcNumber(doc.data()['number']).toInt() > max
                ? ipcNumber(doc.data()['number']).toInt()
                : max,
      );
      final stored = ipcNumber(state.data()?['ipcSequence']).toInt();
      final next =
          application?['number'] as int? ??
          (all.isEmpty ? 1 : (stored > existingMax ? stored : existingMax) + 1);
      final reserved = List<int>.from(
        state.data()?['ipcReservedNumbers'] ?? [],
      );
      if (next < 1 ||
          reserved.contains(next) ||
          all.any((doc) => ipcNumber(doc.data()['number']).toInt() == next))
        throw StateError(
          'IPC number $next is already in use. Choose another number.',
        );
      transaction.update(projectRef, {
        'ipcSequence': next > stored ? next : stored,
        'ipcReservedNumbers': FieldValue.arrayUnion([next]),
      });
      return next;
    });
    if (previous != null) {
      final excluded = List<String>.from(previous.data()['excluded'] ?? []);
      for (final type in ['boqs', 'externalBoqs']) {
        final packages = (await previous.reference.collection(type).get()).docs;
        for (final package in packages) {
          final key =
              '${type == 'boqs' ? 'building' : 'external'}:${package.id}';
          if (excluded.contains(key)) continue;
          final target = destination.collection(type).doc(package.id);
          await copyRows(
            package.reference.collection('items'),
            target.collection('items'),
          );
          await target.set({
            ...package.data(),
            'previousExecutedAmount': ipcNumber(
              package.data()['executedAmount'],
            ),
          });
          // Carry forward execution, but value the new building snapshot using
          // the same current measurements as Reports, not a legacy IPC total.
          if (type == 'boqs') {
            final building = projectRef.collection('buildings').doc(package.id);
            if ((await building.get()).exists) {
              await snapshotMeasuredBoq(building, target);
            }
          }
        }
      }
    } else {
      final buildings = (await projectRef.collection('buildings').get()).docs;
      for (final building in buildings) {
        if (building.data()['isDeleted'] == true) continue;
        final target = destination.collection('boqs').doc(building.id);
        final contract = await snapshotMeasuredBoq(building.reference, target);
        await target.set({
          'name': building.data()['name'] ?? 'Building',
          'sourcePath': building.reference.path,
          'contractValue': contract,
          'executedPercent': 0,
          'executedAmount': 0,
          'previousExecutedAmount': 0,
        }, SetOptions(merge: true));
      }
    }
    // Publish only when all packages and rows are copied successfully.
    await destination.set({
      'number': number,
      'period': DateFormat('MMMM yyyy').format(
        terms?['ipcDate'] is Timestamp
            ? (terms!['ipcDate'] as Timestamp).toDate()
            : DateTime.now(),
      ),
      'ipcDate': terms?['ipcDate'] ?? Timestamp.fromDate(DateTime.now()),
      if (terms != null) ...{
        for (final key in [
          'periodFrom',
          'periodTo',
          'submissionDate',
          'period',
        ])
          if (terms[key] != null) key: terms[key],
      },
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
      'previousIpcId': previous?.id,
      'excluded': [],
      'amountApplied': 0,
      ...?application,
      'amountCertified': 0,
      'amountPaid': 0,
      'retentionHeld': 0,
      'advancePaymentRecovered': 0,
      'ipcType':
          all.isEmpty && terms?['withoutAdvance'] != true ? 'advance' : 'work',
      'terms': terms ?? previous?.data()['terms'],
      if (all.isEmpty && terms != null && terms['withoutAdvance'] != true)
        ...calculateIpcDeductions(
          gross: 0,
          contract: ipcNumber(terms['contractPrice']),
          advancePercent: ipcNumber(terms['advancePercent']),
          recoveryPercent: ipcNumber(terms['recoveryPercent']),
          retentionPercent: ipcNumber(terms['retentionPercent']),
          retentionLimitPercent: ipcNumber(terms['retentionLimitPercent']),
          advance: true,
        ),
      if (terms != null) 'contractValue': terms['contractPrice'],
    });
    return destination.id;
  }

  static Future<void> submit(
    DocumentReference<Map<String, dynamic>> certificate,
  ) async {
    final data = (await certificate.get()).data()!;
    if (data['submissionDate'] is! Timestamp ||
        data['periodFrom'] is! Timestamp ||
        data['periodTo'] is! Timestamp)
      throw StateError(
        'Select the period and submission date before submitting.',
      );
    if (data['status'] != 'draft' || data['isDeleted'] == true)
      throw StateError('Only a draft can be submitted.');
    final excluded = List<String>.from(data['excluded'] ?? []);
    double cumulative = 0, previous = 0, contract = 0;
    var count = 0;
    for (final type in ['boqs', 'externalBoqs']) {
      for (final package in (await certificate.collection(type).get()).docs) {
        if (excluded.contains(
          '${type == 'boqs' ? 'building' : 'external'}:${package.id}',
        ))
          continue;
        count++;
        cumulative += ipcNumber(package.data()['executedAmount']);
        previous += ipcNumber(package.data()['previousExecutedAmount']);
        contract += ipcNumber(package.data()['contractValue']);
      }
    }
    if (count == 0 && data['ipcType'] != 'advance')
      throw StateError('Include at least one BOQ before submitting.');
    final terms = Map<String, dynamic>.from(data['terms'] ?? {});
    final history = (await certificate.parent.get()).docs.where(
      (doc) =>
          doc.id != certificate.id &&
          doc.data()['isDeleted'] != true &&
          doc.data()['submittedAt'] is Timestamp,
    );
    final recovered = history.fold<double>(
      0,
      (total, doc) => total + ipcNumber(doc.data()['advanceRecovery']),
    );
    final retained = history.fold<double>(
      0,
      (total, doc) => total + ipcNumber(doc.data()['retentionDeduction']),
    );
    final deductions =
        terms.isEmpty
            ? <String, double>{}
            : calculateIpcDeductions(
              gross: cumulative - previous,
              contract: ipcNumber(terms['contractPrice']),
              advancePercent: ipcNumber(terms['advancePercent']),
              recoveryPercent: ipcNumber(terms['recoveryPercent']),
              retentionPercent: ipcNumber(terms['retentionPercent']),
              retentionLimitPercent: ipcNumber(terms['retentionLimitPercent']),
              recovered: recovered,
              retained: retained,
              advance: data['ipcType'] == 'advance',
            );
    await certificate.update({
      'status': 'submitted',
      'submittedAt': data['submissionDate'],
      'submissionRecordedAt': FieldValue.serverTimestamp(),
      'amountApplied': cumulative - previous,
      'cumulativeExecutedAmount': cumulative,
      'previousExecutedAmount': previous,
      'contractValue':
          terms.isEmpty ? contract : ipcNumber(terms['contractPrice']),
      ...deductions,
      if (data['enteredAmountApplied'] != null) ...{
        'calculatedAmountApplied':
            deductions['amountApplied'] ?? cumulative - previous,
        'amountApplied': data['enteredAmountApplied'],
      },
    });
  }
}

class IpcDashboard extends StatefulWidget {
  const IpcDashboard({super.key});
  @override
  State<IpcDashboard> createState() => _IpcDashboardState();
}

class _IpcDashboardState extends State<IpcDashboard> {
  late final _projects =
      FirebaseFirestore.instance.collection('projects').stateSnapshots();
  String? _project;
  bool _busy = false;

  Future<void> _updateStatus(String project, String id) async {
    final ref = IpcStore.certificates(project).doc(id);
    try {
      final data = (await ref.get()).data();
      if (data == null || data['isDeleted'] == true)
        throw StateError('IPC unavailable.');
      if (data['submittedAt'] is! Timestamp)
        throw StateError('Submit the draft before updating its status.');
      const stages = ['reviewed', 'certified', 'sent_to_employer', 'paid'];
      const labels = ['Reviewed', 'Certified', 'Sent to Employer', 'Paid'];
      const keys = ['reviewedAt', 'certifiedAt', 'sentToEmployerAt', 'paidAt'];
      var selected =
          stages.contains(data['status']) ? '${data['status']}' : 'reviewed';
      var actionDate =
          data[keys[stages.indexOf(selected)]] is Timestamp
              ? (data[keys[stages.indexOf(selected)]] as Timestamp).toDate()
              : DateTime.now();
      final amount = TextEditingController(
        text: NumberFormat('#,##0.00').format(
          ipcNumber(
            data[selected == 'paid' ? 'amountPaid' : 'amountCertified'],
          ),
        ),
      );
      final form = GlobalKey<FormState>();
      String? formError;
      bool saving = false;
      Future<String?> persistStatus() async {
        final value = ipcNumber(amount.text);
        return FirebaseFirestore.instance.runTransaction<String?>((
          transaction,
        ) async {
          final current = (await transaction.get(ref)).data()!;
          if (current['isDeleted'] == true ||
              current['submittedAt'] is! Timestamp)
            return 'IPC is no longer submitted.';
          final index = stages.indexOf(selected);
          final prior = current[index == 0 ? 'submittedAt' : keys[index - 1]];
          if (prior is! Timestamp) return 'Record the preceding status first.';
          DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
          if (day(actionDate).isBefore(day(prior.toDate())))
            return 'Action date cannot precede the previous stage.';
          for (var i = index + 1; i < keys.length; i++) {
            final later = current[keys[i]];
            if (later is Timestamp &&
                day(actionDate).isAfter(day(later.toDate())))
              return 'Action date cannot be after a later completed stage.';
          }
          if (selected == 'paid' &&
              value != ipcNumber(current['amountCertified']))
            return 'Paid status requires the total paid to equal the certified amount.';
          if (selected == 'certified' &&
              value < ipcNumber(current['amountPaid']))
            return 'Certified amount cannot be less than payments already recorded.';
          final highest = keys.lastIndexWhere(
            (key) => current[key] is Timestamp,
          );
          transaction.update(ref, {
            'status': highest > index ? stages[highest] : selected,
            keys[index]: Timestamp.fromDate(
              DateTime(actionDate.year, actionDate.month, actionDate.day),
            ),
            'statusUpdatedAt': FieldValue.serverTimestamp(),
            if (selected == 'certified') 'amountCertified': value,
            if (selected == 'paid') 'amountPaid': value,
          });
          return null;
        });
      }

      if (!mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder:
            (context) => StatefulBuilder(
              builder:
                  (context, refresh) => AlertDialog(
                    scrollable: true,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    actionsPadding: const EdgeInsets.all(24),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF4FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.published_with_changes,
                            color: Color(0xFF1557EE),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Update IPC status',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'IPC No. ${data['number']} · ${data['period'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF68758B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    content: SizedBox(
                      width: 480,
                      child: Form(
                        key: form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: selected,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                prefixIcon: Icon(Icons.task_alt),
                                filled: true,
                                fillColor: Color(0xFFF7F9FC),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (var i = 0; i < stages.length; i++)
                                  DropdownMenuItem(
                                    value: stages[i],
                                    child: Text(labels[i]),
                                  ),
                              ],
                              onChanged:
                                  (value) => refresh(() {
                                    selected = value!;
                                    final saved =
                                        data[keys[stages.indexOf(selected)]];
                                    actionDate =
                                        saved is Timestamp
                                            ? saved.toDate()
                                            : DateTime.now();
                                    amount.text = NumberFormat(
                                      '#,##0.00',
                                    ).format(
                                      ipcNumber(
                                        data[selected == 'paid'
                                            ? 'amountPaid'
                                            : 'amountCertified'],
                                      ),
                                    );
                                  }),
                            ),
                            const SizedBox(height: 16),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Action date',
                                  prefixIcon: Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                  suffixIcon: Icon(Icons.expand_more),
                                  filled: true,
                                  fillColor: Color(0xFFF7F9FC),
                                  border: OutlineInputBorder(),
                                ),
                                child: Text(
                                  DateFormat('dd MMM yyyy').format(actionDate),
                                ),
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: actionDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null && context.mounted)
                                  refresh(() => actionDate = picked);
                              },
                            ),
                            const SizedBox(height: 20),
                            if (selected == 'certified' || selected == 'paid')
                              TextFormField(
                                controller: amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  prefixText: 'TZS  ',
                                  filled: true,
                                  fillColor: const Color(0xFFF7F9FC),
                                  border: const OutlineInputBorder(),
                                  labelText:
                                      selected == 'paid'
                                          ? 'Total amount paid'
                                          : 'Amount certified',
                                ),
                                validator: (value) {
                                  final n = double.tryParse(
                                    (value ?? '').replaceAll(',', ''),
                                  );
                                  return n == null || !n.isFinite || n < 0
                                      ? 'Enter a valid amount'
                                      : null;
                                },
                              ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF4FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: Color(0xFF1557EE),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Record stages in order. This action date will appear in IPC Progress.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: Color(0xFF465A78),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed:
                            saving
                                ? null
                                : () async {
                                  if (!form.currentState!.validate()) return;
                                  refresh(() {
                                    saving = true;
                                    formError = null;
                                  });
                                  try {
                                    final error = await persistStatus();
                                    if (!context.mounted) return;
                                    if (error == null) {
                                      Navigator.pop(context, true);
                                    } else {
                                      refresh(() {
                                        formError = error;
                                        saving = false;
                                      });
                                    }
                                  } catch (error) {
                                    if (context.mounted)
                                      refresh(() {
                                        saving = false;
                                        formError =
                                            'Could not save status. Check your connection and access, then retry.';
                                      });
                                  }
                                },
                        label: Text(saving ? 'Saving…' : 'Save status'),
                      ),
                      if (formError != null)
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                formError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
            ),
      );
      if (save != true) return;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IPC status and action date saved.')),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _changeIpc(
    String project,
    String id, {
    required bool delete,
  }) async {
    setState(() => _busy = true);
    try {
      final collection = IpcStore.certificates(project);
      final docs =
          (await collection.get()).docs
              .where((doc) => doc.data()['isDeleted'] != true)
              .toList();
      final index = docs.indexWhere((doc) => doc.id == id);
      if (index < 0) throw StateError('IPC no longer available.');
      final doc = docs[index];
      final data = doc.data();
      if (docs.any(
        (other) =>
            other.id != id &&
            ipcNumber(other.data()['number']) > ipcNumber(data['number']),
      )) {
        throw StateError(
          'Change or remove later IPCs first. They depend on this certificate.',
        );
      }
      if (!['draft', 'submitted'].contains(data['status']) ||
          ipcNumber(data['amountCertified']) != 0 ||
          ipcNumber(data['amountPaid']) != 0) {
        throw StateError(
          'Reviewed, certified or paid IPCs cannot be edited or deleted here.',
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                '${delete ? 'Delete' : 'Edit'} IPC No. ${data['number']}?',
              ),
              content: Text(
                delete
                    ? 'Remove this IPC from history and totals? Its saved BOQs will be retained for recovery; source project BOQs will not change.'
                    : 'Open this IPC as a draft for editing? A submitted IPC must be submitted again after editing.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(delete ? 'Delete IPC' : 'Edit IPC'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
      Map<String, dynamic>? terms;
      if (!delete && data['ipcType'] == 'advance') {
        terms = await _advanceSetup(
          initial: {
            ...Map<String, dynamic>.from(data['terms'] ?? {}),
            for (final key in ['periodFrom', 'periodTo', 'submissionDate'])
              if (data[key] != null) key: data[key],
            if (data['submissionDate'] == null &&
                data['submittedAt'] is Timestamp)
              'submissionDate': data['submittedAt'],
          },
        );
        if (terms == null) return;
      }
      await doc.reference.update(
        delete
            ? {'isDeleted': true, 'deletedAt': FieldValue.serverTimestamp()}
            : {
              'status': 'draft',
              'submittedAt': FieldValue.delete(),
              'editedAt': FieldValue.serverTimestamp(),
              if (terms != null) ...{
                'terms': terms,
                'ipcDate': terms['ipcDate'],
                'period': DateFormat(
                  'MMMM yyyy',
                ).format((terms['ipcDate'] as Timestamp).toDate()),
                for (final key in [
                  'periodFrom',
                  'periodTo',
                  'submissionDate',
                  'period',
                ])
                  if (terms[key] != null) key: terms[key],
                'ipcType': terms['withoutAdvance'] == true ? 'work' : 'advance',
                ...calculateIpcDeductions(
                  gross: 0,
                  contract: ipcNumber(terms['contractPrice']),
                  advancePercent: ipcNumber(terms['advancePercent']),
                  recoveryPercent: ipcNumber(terms['recoveryPercent']),
                  retentionPercent: ipcNumber(terms['retentionPercent']),
                  retentionLimitPercent: ipcNumber(
                    terms['retentionLimitPercent'],
                  ),
                  advance: terms['withoutAdvance'] != true,
                ),
              },
            },
      );
      if (mounted) {
        if (delete) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'IPC removed. Its saved data is retained for recovery.',
              ),
            ),
          );
        } else {
          _openDraft(project, id);
        }
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>?> _advanceSetup({
    Map<String, dynamic>? initial,
  }) async {
    final form = GlobalKey<FormState>();
    final fields = {
      'contractPrice': ('Contract price (TZS)', TextEditingController()),
      'advancePercent': (
        'Advance payment (%)',
        TextEditingController(text: '10'),
      ),
      'recoveryPercent': (
        'Recovery from each subsequent IPC (%)',
        TextEditingController(text: '10'),
      ),
      'retentionPercent': (
        'Retention from each subsequent IPC (%)',
        TextEditingController(text: '5'),
      ),
      'retentionLimitPercent': (
        'Maximum retention (% of contract price)',
        TextEditingController(text: '5'),
      ),
    };
    for (final entry in fields.entries) {
      if (initial?[entry.key] != null)
        entry.value.$2.text = '${initial![entry.key]}';
    }
    var ipcDate =
        initial?['ipcDate'] is Timestamp
            ? (initial!['ipcDate'] as Timestamp).toDate()
            : DateTime.now();
    final dates = <String, DateTime?>{
      for (final key in ['periodFrom', 'periodTo', 'submissionDate'])
        key:
            initial?[key] is Timestamp
                ? (initial![key] as Timestamp).toDate()
                : null,
    };
    Map<String, dynamic> dateValues() => {
      for (final entry in dates.entries)
        entry.key: Timestamp.fromDate(entry.value!),
      'period':
          '${DateFormat('dd MMM yyyy').format(dates['periodFrom']!)} – ${DateFormat('dd MMM yyyy').format(dates['periodTo']!)}',
    };
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, refresh) => AlertDialog(
                  title: const Text('IPC No. 1 — Payment setup'),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Form(
                        key: form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Confirm the percentages required by your contract. No recovery or retention is deducted from this advance. Future deductions use current-period work before deductions.',
                            ),
                            const SizedBox(height: 16),
                            for (final key in [
                              'periodFrom',
                              'periodTo',
                              'submissionDate',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: FormField<DateTime>(
                                  validator: (_) {
                                    if (dates[key] == null)
                                      return 'Select a date';
                                    if (key == 'periodTo' &&
                                        dates['periodFrom'] != null &&
                                        dates[key]!.isBefore(
                                          dates['periodFrom']!,
                                        ))
                                      return 'End date must be on or after start date';
                                    return null;
                                  },
                                  builder:
                                      (field) => InkWell(
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: dates[key] ?? ipcDate,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                          );
                                          if (picked != null && context.mounted)
                                            refresh(() {
                                              dates[key] = picked;
                                              field.didChange(picked);
                                            });
                                        },
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText:
                                                key == 'periodFrom'
                                                    ? 'Period From'
                                                    : key == 'periodTo'
                                                    ? 'Period To'
                                                    : 'Submission Date',
                                            errorText: field.errorText,
                                            prefixIcon: const Icon(
                                              Icons.calendar_month_outlined,
                                            ),
                                            border: const OutlineInputBorder(),
                                          ),
                                          child: Text(
                                            dates[key] == null
                                                ? 'Select date'
                                                : DateFormat(
                                                  'dd MMM yyyy',
                                                ).format(dates[key]!),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            for (final entry in fields.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  controller: entry.value.$2,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: entry.value.$1,
                                  ),
                                  validator: (value) {
                                    final number = double.tryParse(
                                      (value ?? '').replaceAll(',', ''),
                                    );
                                    if (number == null ||
                                        !number.isFinite ||
                                        number < 0 ||
                                        (entry.key == 'contractPrice' &&
                                            number <= 0) ||
                                        (entry.key != 'contractPrice' &&
                                            number > 100))
                                      return 'Enter a valid ${entry.key == 'contractPrice' ? 'positive amount' : 'percentage from 0 to 100'}';
                                    if (entry.key == 'retentionPercent' &&
                                        number +
                                                ipcNumber(
                                                  fields['recoveryPercent']!
                                                      .$2
                                                      .text,
                                                ) >
                                            100)
                                      return 'Recovery plus retention cannot exceed 100%';
                                    return null;
                                  },
                                ),
                              ),
                            const Text(
                              'Recovery stops when the advance is fully repaid. Retention stops at the specified contract limit.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        fields['advancePercent']!.$2.text = '0';
                        fields['recoveryPercent']!.$2.text = '0';
                        if (form.currentState!.validate()) {
                          Navigator.pop(context, {
                            for (final entry in fields.entries)
                              entry.key: ipcNumber(entry.value.$2.text),
                            'withoutAdvance': true,
                            ...dateValues(),
                            'ipcDate': Timestamp.fromDate(
                              DateTime(
                                ipcDate.year,
                                ipcDate.month,
                                ipcDate.day,
                              ),
                            ),
                          });
                        }
                      },
                      child: const Text('Continue as normal IPC'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(context, {
                            ...dateValues(),
                            'ipcDate': Timestamp.fromDate(
                              DateTime(
                                ipcDate.year,
                                ipcDate.month,
                                ipcDate.day,
                              ),
                            ),
                            for (final entry in fields.entries)
                              entry.key: ipcNumber(entry.value.$2.text),
                          });
                      },
                      child: const Text('Continue to IPC 1 as Advance Payment'),
                    ),
                  ],
                ),
          ),
    );
    // Let the closing dialog dispose its fields before releasing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final field in fields.values) {
      field.$2.dispose();
    }
    return result;
  }

  Future<void> _prepare(String project) async {
    setState(() => _busy = true);
    try {
      Map<String, dynamic>? terms;
      Map<String, dynamic>? application;
      final existing =
          (await IpcStore.certificates(project).get()).docs
              .where((doc) => doc.data()['isDeleted'] != true)
              .toList();
      final drafts =
          existing.where((doc) => doc.data()['status'] == 'draft').toList();
      if (drafts.isNotEmpty) {
        if (mounted) _openDraft(project, drafts.first.id);
        return;
      }
      if (existing.isEmpty) {
        if (!mounted) return;
        terms = await _advanceSetup();
        if (terms == null) return;
      } else {
        if (!mounted) return;
        final projectData =
            (await FirebaseFirestore.instance
                    .collection('projects')
                    .doc(project)
                    .get())
                .data() ??
            {};
        final used = {
          for (final doc in existing) ipcNumber(doc.data()['number']).toInt(),
          ...List<int>.from(projectData['ipcReservedNumbers'] ?? []),
        };
        final highest = used.fold<int>(
          ipcNumber(projectData['ipcSequence']).toInt(),
          (a, b) => a > b ? a : b,
        );
        if (!mounted) return;
        application = await showWorkIpcSetup(
          context,
          nextNumber: highest + 1,
          usedNumbers: used,
        );
        if (application == null) return;
      }
      final id = await IpcStore.prepare(
        project,
        terms: terms,
        application: application,
      );
      if (mounted) _openDraft(project, id);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare IPC: $error')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDraft(String project, String id) => Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => Scaffold(
            appBar: AppBar(title: const Text('Prepare IPC')),
            body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: IpcStore.certificates(project).doc(id).stateSnapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(
                    child: Text('Could not load IPC: ${snapshot.error}'),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final data = snapshot.data!.data() ?? {};
                if (data['ipcType'] != 'advance')
                  return IpcPage(projectId: project, certificateId: id);
                final terms = Map<String, dynamic>.from(data['terms'] ?? {});
                return IpcAdvanceReview(
                  data: data,
                  terms: terms,
                  submitButton: FilledButton.icon(
                    onPressed:
                        data['status'] != 'draft'
                            ? null
                            : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder:
                                    (context) => AlertDialog(
                                      title: const Text(
                                        'Submit advance payment IPC?',
                                      ),
                                      content: Text(
                                        'Submit ${ipcMoney(data['amountApplied'])} with no deductions?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () =>
                                                  Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed:
                                              () =>
                                                  Navigator.pop(context, true),
                                          child: const Text('Submit'),
                                        ),
                                      ],
                                    ),
                              );
                              if (confirmed != true) return;
                              try {
                                if (!context.mounted ||
                                    !await editIpcDates(
                                      context,
                                      IpcStore.certificates(project).doc(id),
                                    ))
                                  return;
                                await IpcStore.submit(
                                  IpcStore.certificates(project).doc(id),
                                );
                                if (context.mounted) Navigator.pop(context);
                              } catch (error) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Could not submit IPC: $error',
                                      ),
                                    ),
                                  );
                              }
                            },
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit advance payment IPC'),
                  ),
                );
              },
            ),
          ),
    ),
  );

  void _open(String project, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (doc.data()['status'] == 'draft') {
      _openDraft(project, doc.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              appBar: AppBar(
                title: Text(
                  'IPC No. ${doc.data()['number']} · ${doc.data()['period'] ?? ''}',
                ),
              ),
              body: IpcDetail(certificate: doc.reference),
            ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _projects,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(
          child: Text('Could not load projects: ${snapshot.error}'),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final projects =
          snapshot.data!.docs
              .where(
                (doc) =>
                    doc.data()['isDeleted'] != true &&
                    uid != null &&
                    (doc.data()['ownerId'] == uid ||
                        ((doc.data()['members'] as List?) ?? []).contains(uid)),
              )
              .toList();
      if (projects.isEmpty) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Interim Payment Certificates',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text('Create a project to prepare a new IPC.'),
            const SizedBox(height: 24),
            IpcOverview(records: const [], onOpen: (_) {}),
          ],
        );
      }
      final index = projects.indexWhere((doc) => doc.id == _project);
      final project = projects[index < 0 ? 0 : index];
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const title = Text(
                'Interim Payment Certificates',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A153D),
                ),
              );
              final dropdown = DropdownButtonFormField<String>(
                initialValue: project.id,
                key: ValueKey(project.id),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                items:
                    projects
                        .map(
                          (doc) => DropdownMenuItem(
                            value: doc.id,
                            child: Text(
                              '${doc.data()['name'] ?? 'Project'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged:
                    _busy
                        ? null
                        : (value) => setState(() {
                          _project = value;
                        }),
              );
              final prepare = FilledButton.icon(
                onPressed: _busy ? null : () => _prepare(project.id),
                icon: const Icon(Icons.add),
                label: Text(_busy ? 'Preparing…' : 'Prepare New IPC'),
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 24),
                    dropdown,
                    const SizedBox(height: 16),
                    prepare,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: title),
                  const SizedBox(width: 48),
                  Expanded(flex: 2, child: dropdown),
                  const SizedBox(width: 20),
                  prepare,
                ],
              );
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 24),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey(project.id),
            stream: IpcStore.certificates(project.id).stateSnapshots(),
            builder: (context, certificates) {
              if (certificates.hasError)
                return Text('Could not load IPCs: ${certificates.error}');
              if (!certificates.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs =
                  certificates.data!.docs
                      .where((doc) => doc.data()['isDeleted'] != true)
                      .toList()
                    ..sort(
                      (a, b) => ipcNumber(
                        b.data()['number'],
                      ).compareTo(ipcNumber(a.data()['number'])),
                    );
              return IpcOverview(
                onDates:
                    (id) => editIpcDates(
                      context,
                      IpcStore.certificates(project.id).doc(id),
                    ),
                onStatus: (id) => _updateStatus(project.id, id),
                onEdit:
                    _busy
                        ? null
                        : (id) => _changeIpc(project.id, id, delete: false),
                onDelete:
                    _busy
                        ? null
                        : (id) => _changeIpc(project.id, id, delete: true),
                records:
                    docs.map((doc) => {...doc.data(), 'id': doc.id}).toList(),
                onOpen: (id) {
                  final index = docs.indexWhere((doc) => doc.id == id);
                  if (index >= 0) _open(project.id, docs[index]);
                },
              );
            },
          ),
        ],
      );
    },
  );
}
