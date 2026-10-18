import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'ipc_dashboard.dart';
import 'ipc_dates.dart';
import 'ipc_boq_valuation.dart';
import 'ipc_draft_link.dart';

/// BOQ selection for a project's IPC preparation workspace.
/// Exclusions belong to this workspace, never to the source building BOQ.
class IpcPage extends StatefulWidget {
  const IpcPage({super.key, this.projectId, this.certificateId});
  final String? projectId;
  final String? certificateId;
  @override
  State<IpcPage> createState() => _IpcPageState();
}

class _IpcPageState extends State<IpcPage> {
  late final _projects =
      FirebaseFirestore.instance.collection('projects').stateSnapshots();
  String? _projectId;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> _workspace(String project) =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(project)
          .collection('ipcs')
          .doc(widget.certificateId);

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      if (widget.projectId != null) {
        final certificate = await _workspace(widget.projectId!).get();
        if (certificate.data()?['status'] != 'draft' ||
            certificate.data()?['isDeleted'] == true) {
          throw StateError(
            'This IPC is no longer a draft. Reopen it from the dashboard.',
          );
        }
      }
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update IPC: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(String project) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) throw StateError('The selected file could not be read.');
    final workbook = xl.Excel.decodeBytes(bytes);
    final rows = <Map<String, dynamic>>[];
    String normal(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final sheet in workbook.tables.entries) {
      var description = -1;
      var code = -1;
      var unit = -1;
      var quantity = -1;
      var rate = -1;
      var amount = -1;
      for (final row in sheet.value.rows) {
        final values =
            row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
        final headers = values.map(normal).toList();
        int column(List<String> aliases) =>
            headers.indexWhere(aliases.contains);
        final descHeader = column([
          'description',
          'particulars',
          'itemdescription',
        ]);
        final unitHeader = column(['unit', 'uom']);
        if (descHeader >= 0 && unitHeader >= 0) {
          description = descHeader;
          unit = unitHeader;
          code = column(['item', 'itemno', 'itemcode', 'boqcode', 'code']);
          quantity = column(['quantity', 'qty']);
          rate = column(['rate', 'unitrate']);
          amount = column(['amount', 'totalamount', 'total']);
          continue;
        }
        if (description < 0) continue;
        String at(int index) =>
            index < 0 || index >= values.length ? '' : values[index];
        if (at(description).isEmpty) continue;
        final heading =
            at(unit).isEmpty &&
            at(quantity).isEmpty &&
            at(rate).isEmpty &&
            at(amount).isEmpty;
        rows.add({
          'sheet': sheet.key,
          'order': rows.length,
          'rowType': heading ? 'heading' : 'item',
          'boqCode': at(code),
          'description': at(description),
          'unit': at(unit),
          'quantity': at(quantity),
          'rate': at(rate),
          'amount': at(amount),
        });
      }
    }
    if (!rows.any((row) => row['rowType'] == 'item')) {
      throw FormatException(
        'No BOQ items found. Include Description and Unit column headings.',
      );
    }
    final package = _workspace(project).collection('externalBoqs').doc();
    // Publish the package only after every row has been stored.
    for (var offset = 0; offset < rows.length; offset += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in rows.skip(offset).take(400)) {
        batch.set(package.collection('items').doc(), row);
      }
      await batch.commit();
    }
    await package.set({
      'name': picked.files.single.name,
      'itemCount': rows.where((row) => row['rowType'] == 'item').length,
      'createdAt': FieldValue.serverTimestamp(),
      'contractValue': rows
          .where((row) => row['rowType'] == 'item')
          .fold<double>(
            0,
            (sum, row) =>
                sum + (_number(row['quantity']) * _number(row['rate'])),
          ),
      'executedPercent': 0,
      'executedAmount': 0,
    });
  }

  Future<void> _addProjectBoq(String project) async {
    final workspace = _workspace(project);
    final buildings =
        (await FirebaseFirestore.instance
                .collection('projects')
                .doc(project)
                .collection('buildings')
                .get())
            .docs
            .where((doc) => doc.data()['isDeleted'] != true)
            .toList();
    final existing =
        (await workspace.collection('boqs').get()).docs
            .map((doc) => doc.id)
            .toSet();
    if (!mounted) return;
    final id = await showDialog<String>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: const Text('Add project BOQ'),
            children:
                buildings.isEmpty
                    ? [
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No building BOQs available. Import an external Excel BOQ instead.',
                        ),
                      ),
                    ]
                    : buildings
                        .map(
                          (doc) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, doc.id),
                            child: Text(
                              '${doc.data()['name'] ?? 'Building'}${existing.contains(doc.id) ? ' — restore inclusion' : ''}',
                            ),
                          ),
                        )
                        .toList(),
          ),
    );
    if (id == null) return;
    if (!existing.contains(id)) {
      final building = buildings[buildings.indexWhere((doc) => doc.id == id)];
      final target = workspace.collection('boqs').doc(id);
      final contract = await snapshotMeasuredBoq(building.reference, target);
      await target.set({
        'name': building.data()['name'] ?? 'Building',
        'contractValue': contract,
        'executedAmount': 0,
        'executedPercent': 0,
        'previousExecutedAmount': 0,
      }, SetOptions(merge: true));
    }
    await workspace.update({
      'excluded': FieldValue.arrayRemove(['building:$id']),
    });
  }

  void _openBoq(
    String name,
    CollectionReference<Map<String, dynamic>> source, {
    bool building = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              appBar: AppBar(title: Text(name)),
              body: StreamBuilder<List<Map<String, dynamic>>>(
                stream: source.stateSnapshots().asyncMap((initial) async {
                  var snapshot = initial;
                  if (building && snapshot.docs.isEmpty) {
                    snapshot =
                        await source.parent!.collection('boqItems').get();
                  }
                  return snapshot.docs.map((doc) => doc.data()).toList()..sort(
                    (a, b) =>
                        _number(a['order']).compareTo(_number(b['order'])),
                  );
                }),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                      child: Text('Could not load BOQ: ${snapshot.error}'),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.isEmpty)
                    return const Center(child: Text('No BOQ items yet.'));
                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: snapshot.data!.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (_, index) {
                      final row = snapshot.data![index];
                      return ListTile(
                        leading: Text('${row['boqCode'] ?? ''}'),
                        title: Text(
                          '${row['description'] ?? row['billLabel'] ?? ''}',
                        ),
                        subtitle: Text(
                          'Unit: ${row['unit'] ?? ''}   Quantity: ${row['qtyOverride'] ?? row['quantity'] ?? row['qty'] ?? '—'}   Rate: ${row['rate'] ?? '—'}',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
      ),
    );
  }

  double _number(dynamic value) =>
      double.tryParse('$value'.replaceAll(',', '')) ?? 0;

  Future<void> _editExecution(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> values,
  ) async {
    final contract = TextEditingController(
      text: _number(values['contractValue']).toStringAsFixed(2),
    );
    final percent = TextEditingController(
      text: _number(values['executedPercent']).toStringAsFixed(2),
    );
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cumulative work executed'),
            content: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter the total executed to date, including previous IPCs. Verify the BOQ contract value before submitting.',
                  ),
                  TextFormField(
                    controller: contract,
                    decoration: const InputDecoration(
                      labelText: 'BOQ contract value (TZS)',
                    ),
                    keyboardType: TextInputType.number,
                    validator:
                        (value) =>
                            double.tryParse(
                                          (value ?? '').replaceAll(',', ''),
                                        ) ==
                                        null ||
                                    _number(value) <= 0
                                ? 'Enter a positive contract value'
                                : null,
                  ),
                  TextFormField(
                    controller: percent,
                    decoration: const InputDecoration(
                      labelText: 'Work executed (%)',
                    ),
                    keyboardType: TextInputType.number,
                    validator:
                        (value) =>
                            double.tryParse(value ?? '') == null ||
                                    _number(value) < 0 ||
                                    _number(value) > 100
                                ? 'Enter a percentage from 0 to 100'
                                : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (form.currentState!.validate())
                    Navigator.pop(context, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
    final amount = _number(contract.text);
    final progress = _number(percent.text);
    contract.dispose();
    percent.dispose();
    if (save == true && mounted)
      await _run(
        () => reference.update({
          'contractValue': amount,
          'executedPercent': progress,
          'executedAmount': amount * progress / 100,
        }),
      );
  }

  @override
  Widget build(BuildContext context) => widget.certificateId != null && widget.projectId != null
      ? IpcDraftLink(certificate: _workspace(widget.projectId!), child: _content(context))
      : _content(context);

  Widget _content(BuildContext context) =>
      widget.certificateId == null
          ? const IpcDashboard()
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  snapshot.data!.docs.where((doc) {
                    final data = doc.data();
                    return uid != null &&
                        data['isDeleted'] != true &&
                        (data['ownerId'] == uid ||
                            ((data['members'] as List?) ?? []).contains(uid));
                  }).toList();
              if (projects.isEmpty)
                return const Center(
                  child: Text('Create a project to prepare an IPC.'),
                );
              // Avoid an orElse callback on Firestore's concrete snapshot list: on
              // web its runtime type can be narrower than QueryDocumentSnapshot.
              final projectIndex = projects.indexWhere(
                (doc) => doc.id == (widget.projectId ?? _projectId),
              );
              if (widget.projectId != null && projectIndex < 0) {
                return const Center(
                  child: Text('This project is no longer available.'),
                );
              }
              final project = projects[projectIndex < 0 ? 0 : projectIndex];
              final workspace = _workspace(project.id);
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Interim Payment Certificate · BOQ preparation',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'BOQs and executed values are carried forward from the latest submitted IPC. The first IPC starts with all building BOQs. Changes here do not alter source project BOQs.',
                  ),
                  const SizedBox(height: 20),
                  if (widget.projectId == null)
                    DropdownButtonFormField<String>(
                      initialValue: project.id,
                      key: ValueKey(project.id),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Project'),
                      items:
                          projects
                              .map(
                                (doc) => DropdownMenuItem(
                                  value: doc.id,
                                  child: Text(
                                    '${doc.data()['name'] ?? 'Project'}',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged:
                          _busy
                              ? null
                              : (value) => setState(() => _projectId = value),
                    ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: workspace.stateSnapshots(),
                    builder:
                        (context, certificate) => Text(
                          'IPC No. ${certificate.data?.data()?['number'] ?? ''} · ${project.data()['name'] ?? 'Project'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : () => _run(() => _import(project.id)),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import external Excel BOQ'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : () => _run(() => _addProjectBoq(project.id)),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add project BOQ'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _busy
                                ? null
                                : () => _run(
                                  () => workspace.set({
                                    'excluded': [],
                                  }, SetOptions(merge: true)),
                                ),
                        child: const Text('Include all BOQs'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : () => _run(() async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text('Submit IPC?'),
                                          content: const Text(
                                            'This freezes the BOQ selection and executed values. The next IPC will carry these values forward.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    true,
                                                  ),
                                              child: const Text('Submit'),
                                            ),
                                          ],
                                        ),
                                  );
                                  if (confirm != true) return;
                                  if (!context.mounted ||
                                      !await editIpcDates(context, workspace))
                                    return;
                                  await IpcStore.submit(workspace);
                                  if (context.mounted)
                                    Navigator.of(context).pop();
                                }),
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Submit IPC'),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 20),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: workspace.stateSnapshots(),
                    builder: (context, selection) {
                      if (selection.hasError)
                        return Text(
                          'Could not load IPC selection: ${selection.error}',
                        );
                      if (!selection.hasData)
                        return const LinearProgressIndicator();
                      final excluded = List<String>.from(
                        selection.data?.data()?['excluded'] ?? [],
                      );
                      Widget card(
                        String id,
                        String name,
                        String subtitle,
                        VoidCallback open,
                        DocumentReference<Map<String, dynamic>> reference,
                        Map<String, dynamic> values,
                      ) {
                        final included = !excluded.contains(id);
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              included
                                  ? Icons.check_circle
                                  : Icons.remove_circle_outline,
                              color: included ? Colors.green : Colors.grey,
                            ),
                            title: Text(name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$subtitle · ${included ? 'Included in IPC' : 'Removed from IPC'}',
                                ),
                                Text(
                                  'Work executed: ${_number(values['executedPercent']).toStringAsFixed(2)}% · ${ipcMoney(_number(values['executedAmount']))}',
                                ),
                                Text(
                                  'Previous: ${ipcMoney(_number(values['previousExecutedAmount']))}',
                                ),
                                TextButton.icon(
                                  onPressed:
                                      _busy
                                          ? null
                                          : () =>
                                              _editExecution(reference, values),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Update work executed'),
                                ),
                              ],
                            ),
                            onTap: open,
                            trailing: IconButton(
                              tooltip:
                                  included
                                      ? 'Remove from IPC'
                                      : 'Include in IPC',
                              icon: Icon(
                                included
                                    ? Icons.remove_circle_outline
                                    : Icons.add_circle_outline,
                              ),
                              onPressed:
                                  _busy
                                      ? null
                                      : () => _run(
                                        () => workspace.set({
                                          'excluded':
                                              included
                                                  ? FieldValue.arrayUnion([id])
                                                  : FieldValue.arrayRemove([
                                                    id,
                                                  ]),
                                        }, SetOptions(merge: true)),
                                      ),
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Building BOQs',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: workspace.collection('boqs').stateSnapshots(),
                            builder: (context, buildings) {
                              if (buildings.hasError)
                                return Text(
                                  'Could not load buildings: ${buildings.error}',
                                );
                              if (!buildings.hasData)
                                return const LinearProgressIndicator();
                              final docs =
                                  buildings.data!.docs
                                      .where(
                                        (doc) =>
                                            doc.data()['isDeleted'] != true,
                                      )
                                      .toList();
                              if (docs.isEmpty)
                                return const Text(
                                  'No buildings. You can import an external BOQ above.',
                                );
                              return Column(
                                children:
                                    docs.map((doc) {
                                      final name =
                                          '${doc.data()['name'] ?? 'Building'}';
                                      return card(
                                        'building:${doc.id}',
                                        name,
                                        'Building BOQ',
                                        () => _openBoq(
                                          name,
                                          doc.reference.collection('items'),
                                        ),
                                        doc.reference,
                                        doc.data(),
                                      );
                                    }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'External BOQs',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream:
                                workspace
                                    .collection('externalBoqs')
                                    .stateSnapshots(),
                            builder: (context, external) {
                              if (external.hasError)
                                return Text(
                                  'Could not load external BOQs: ${external.error}',
                                );
                              if (!external.hasData)
                                return const LinearProgressIndicator();
                              if (external.data!.docs.isEmpty)
                                return const Text('No external BOQs imported.');
                              return Column(
                                children:
                                    external.data!.docs.map((doc) {
                                      final name = '${doc.data()['name']}';
                                      return card(
                                        'external:${doc.id}',
                                        name,
                                        '${doc.data()['itemCount']} items',
                                        () => _openBoq(
                                          name,
                                          doc.reference.collection('items'),
                                        ),
                                        doc.reference,
                                        doc.data(),
                                      );
                                    }).toList(),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          );
}
