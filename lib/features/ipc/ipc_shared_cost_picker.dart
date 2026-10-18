import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

double _number(dynamic v) => double.tryParse('$v'.replaceAll(',', '')) ?? 0;

/// Retain source BOQ fields while using 100 percentage points as execution basis.
Map<String, dynamic> sharedCostIpcRow(Map<String, dynamic> source) {
  final type = '${source['rowType'] ?? 'item'}'.trim().toLowerCase();
  final item = type.isEmpty || type == 'item';
  final amount =
      source['amount'] == null
          ? _number(source['quantity']) * _number(source['rate'])
          : _number(source['amount']);
  if (item && (!amount.isFinite || amount < 0)) {
    throw StateError(
      'A shared-cost item has an invalid amount. Correct the source BOQ first.',
    );
  }
  return {
    ...source,
    'sourceBoq': source,
    'boqCode': source['code'] ?? source['boqCode'] ?? '',
    'displayCode':
        source['code'] ?? source['displayCode'] ?? source['boqCode'] ?? '',
    'order': source['sortOrder'] ?? source['order'] ?? 0,
    'rowType': item ? 'item' : type,
    if (item) ...{
      'unit': '%',
      'quantity': 100,
      'qtyOverride': 100,
      'rate': amount / 100,
      'amount': amount,
      'previousExecutedQuantity': 0,
      'cumulativeExecutedQuantity': 0,
    },
  };
}

class _SharedCostSource {
  const _SharedCostSource({required this.id, required this.title, required this.ref, required this.itemCount, required this.totalAmount, this.siteId, this.category});
  final String id;
  final String title;
  final DocumentReference<Map<String, dynamic>> ref;
  final int itemCount;
  final double totalAmount;
  final String? siteId;
  final String? category;
}

class IpcSharedCostPicker extends StatefulWidget {
  const IpcSharedCostPicker({super.key, required this.certificate});
  final DocumentReference<Map<String, dynamic>> certificate;
  @override
  State<IpcSharedCostPicker> createState() => _IpcSharedCostPickerState();
}

class _IpcSharedCostPickerState extends State<IpcSharedCostPicker> {
  late final project = widget.certificate.parent.parent!;
  late final packages = project.collection('projectBoqPackages').stateSnapshots();
  late final included =
      widget.certificate.collection('externalBoqs').stateSnapshots();
  late final sites = project.collection('sites').stateSnapshots();
  String? busy, error;
  final selectedSites = <String, String?>{};

  Future<List<_SharedCostSource>> _loadSiteSources(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> siteDocs,
  ) async {
    final result = <_SharedCostSource>[];
    for (final site in siteDocs) {
      final rows = await site.reference.collection('generalAllowances').get();
      final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final row in rows.docs) {
        final category = '${row.data()['category'] ?? ''}'.trim();
        if (category.isNotEmpty) (grouped[category] ??= []).add(row);
      }
      for (final entry in grouped.entries) {
        final items = entry.value.where((d) => '${d.data()['rowType'] ?? 'item'}' == 'item').toList();
        result.add(_SharedCostSource(
          id: 'site_${site.id}_${entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
          title: entry.key,
          ref: site.reference,
          itemCount: items.length,
          totalAmount: items.fold<double>(0, (sum, d) => sum + _number(d.data()['amount'])),
          siteId: site.id,
          category: entry.key,
        ));
      }
    }
    return result;
  }

  Future<void> include(
    _SharedCostSource source,
    {String? siteId}
  ) async {
    setState(() {
      busy = source.id;
      error = null;
    });
    try {
      final allRows = await source.ref.collection(source.id.startsWith('site_') ? 'generalAllowances' : 'items').get();
      final rows = source.category == null
          ? allRows.docs
          : allRows.docs.where((d) => '${d.data()['category'] ?? ''}'.trim() == source.category).toList();
      if (rows.isEmpty)
        throw StateError(
          'This shared cost has no BOQ yet. Upload its BOQ in Project shared costs first.',
        );
      if (rows.length > 490)
        throw StateError(
          'This BOQ exceeds the atomic import limit of 490 rows. It has not been imported.',
        );
      final converted = {
        for (final row in rows) row.id: sharedCostIpcRow(row.data()),
      };
      final total = converted.values
          .where((r) => r['rowType'] == 'item')
          .fold<double>(0, (sum, r) => sum + _number(r['amount']));
      final history = await widget.certificate.parent.get();
      final target = widget.certificate
          .collection('externalBoqs')
          .doc(source.id.startsWith('site_') ? source.id : 'project_shared_${source.id}');
      final failure = await project.firestore.runTransaction<String?>((
        tx,
      ) async {
        final cert = (await tx.get(widget.certificate)).data();
        final existing = await tx.get(target);
        if (cert == null ||
            cert['isDeleted'] == true ||
            !['draft', 'submitted'].contains(cert['status']) ||
            cert['ipcType'] == 'advance')
          return 'Only draft or submitted work IPCs can include BOQs.';
        if (history.docs.any(
          (d) =>
              d.id != widget.certificate.id &&
              d.data()['isDeleted'] != true &&
              _number(d.data()['number']) > _number(cert['number']),
        ))
          return 'Include BOQs in the latest IPC only.';
        // Upsert the package and its rows. This also repairs an earlier
        // zero-item import and applies a newly selected site scope without
        // resetting execution already recorded on the IPC.
        tx.set(target, {
          'name': source.title,
          if (siteId != null) 'siteId': siteId else 'siteId': FieldValue.delete(),
          'sourcePath': source.ref.path,
          'executionMode': 'percentage',
          'contractValue': total,
          'itemExecutionBaselineZero': true,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!existing.exists) ...{
            'executedAmount': 0,
            'previousExecutedAmount': 0,
            'executedPercent': 0,
            'importedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
        for (final row in converted.entries) {
          tx.set(target.collection('items').doc(row.key), row.value,
              SetOptions(merge: true));
        }
        tx.update(widget.certificate, {
          'excluded': FieldValue.arrayRemove(['external:${target.id}']),
        });
        return null;
      });
      if (failure != null) throw StateError(failure);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Include project and site shared costs'),
    content: SizedBox(
      width: 650,
      height: 450,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select the shared-cost BOQs to include in this IPC. Electricity, plumbing, preliminaries, prime cost sums, provisional sums, variations, and other saved shared-cost packages are listed separately. Execution is recorded as a percentage of each item’s value. Source BOQs remain unchanged.',
          ),
          const SizedBox(height: 16),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: included,
              builder:
                  (
                    context,
                    existing,
                  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: packages,
                    builder: (context, snapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: sites,
                      builder: (context, siteSnapshot) {
                      if (snapshot.hasError || existing.hasError || siteSnapshot.hasError)
                        return const Text(
                          'Could not load shared costs. Close and retry.',
                        );
                      if (!snapshot.hasData || !existing.hasData || !siteSnapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final projectSources = snapshot.data!.docs
                          .where((d) => d.data()['isDeleted'] != true)
                          .map((d) => _SharedCostSource(
                                id: d.id,
                                title: '${d.data()['title'] ?? d.id}',
                                ref: d.reference,
                                itemCount: int.tryParse('${d.data()['itemCount'] ?? 0}') ?? 0,
                                totalAmount: _number(d.data()['totalAmount']),
                                siteId: d.data()['siteId']?.toString(),
                              ))
                          .toList();
                      return FutureBuilder<List<_SharedCostSource>>(
                        future: _loadSiteSources(siteSnapshot.data!.docs),
                        builder: (context, siteCosts) {
                          if (!siteCosts.hasData) return const Center(child: CircularProgressIndicator());
                          final docs = [...projectSources, ...siteCosts.data!];
                          if (docs.isEmpty) return const Center(child: Text('No shared-cost packages yet. Create and upload the project or site shared-cost BOQs first.'));
                          return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final has = existing.data!.docs.any(
                            (d) => d.data()['sourcePath'] == doc.ref.path && d.id == (doc.id.startsWith('site_') ? doc.id : 'project_shared_${doc.id}'),
                          );
                          final siteId = doc.siteId;
                          final siteMatches = siteSnapshot.data!.docs.where((s) => s.id == siteId).toList();
                          final siteName = siteId == null
                              ? 'Project-wide shared cost'
                              : '${siteMatches.isEmpty ? siteId : siteMatches.first.data()['name'] ?? siteId} site shared cost';
                          final selectedSite = selectedSites.containsKey(doc.id)
                              ? selectedSites[doc.id]
                              : siteId;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(doc.title),
                            subtitle: Text('${siteName}\n${doc.itemCount} items · TZS ${NumberFormat('#,##0.00').format(doc.totalAmount)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButton<String?>(
                                  value: selectedSite,
                                  hint: const Text('Scope'),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('Project-wide')),
                                    ...siteSnapshot.data!.docs.map((site) => DropdownMenuItem<String?>(value: site.id, child: Text('${site.data()['name'] ?? site.id} site'))),
                                  ],
                                  onChanged: busy != null || has ? null : (value) => setState(() => selectedSites[doc.id] = value),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: busy != null || has ? null : () => include(doc, siteId: selectedSite),
                                  child: Text(busy == doc.id ? 'Including…' : has ? 'Included' : 'Include in IPC'),
                                ),
                              ],
                            ),
                          );
                        },
                          );
                        },
                      );
                    },
                    ),
                  ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy == null ? () => Navigator.pop(context, true) : null,
        child: const Text('Create manually instead'),
      ),
      FilledButton(
        onPressed: busy == null ? () => Navigator.pop(context) : null,
        child: const Text('Done'),
      ),
    ],
  );
}
