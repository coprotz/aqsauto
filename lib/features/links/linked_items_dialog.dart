// }
// import 'package:aqs/features/boq/dialogs/show_pick_source_measure_dialog.dart';
// import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/links/links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// import 'package:aqs/features/links/links_context.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> showLinkedItemsDialog({
  required BuildContext context,
  required LinkedAutoSyncController linkedCtrl,
  required LinkRepository repo,
  required LinksContext ctxp,
  required Future<BoqPick?> Function(BuildContext ctx) pickTargetBoq,
}) async {
  final measurementsRef = ctxp.measurementsRef;
  final projectId = ctxp.projectId;
  final buildingId = ctxp.buildingId;
  final drawingId = ctxp.drawingId;

  // -------- safe helpers --------
  String _s(dynamic v) => (v ?? '').toString();
  double _num(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  double _parseNum(String s, double fallback) =>
      double.tryParse(s.trim()) ?? fallback;

  // If your path differs, change this:
  CollectionReference<Map<String, dynamic>> _boqRefFromCtx() {
    return FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .collection('buildings')
        .doc(buildingId)
        .collection('boq');
  }

  final boqRef = _boqRefFromCtx();

  Query<Map<String, dynamic>> _existingLinksQuery() {
    return measurementsRef
        .where('projectId', isEqualTo: projectId)
        .where('buildingId', isEqualTo: buildingId)
        .where('drawingId', isEqualTo: drawingId)
        .where('isDerived', isEqualTo: true)
        .where('derivedFromMode', whereIn: ['doc', 'boq']);
  }

  String _modeLabel(QtySourceDoc s0) {
    switch (s0.sourceKind) {
      case QtySourceMode.measured:
        return 'MEASURED';
      case QtySourceMode.boqOverride:
        return 'BOQ OVERRIDE';
    }
  }

  // ------------------------------------------------------------
  // PICK SOURCE (Measured / BOQ Overrides)  ✅ returns QtySourceDoc
  // ------------------------------------------------------------
  Future<QtySourceDoc?> _pickSourceAny(BuildContext dctx) async {
    return showDialog<QtySourceDoc>(
      context: dctx,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final searchCtrl = TextEditingController();
        final search = ''.obs;

        Widget measuredTab() {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick from measured items (from Measurements)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Open measured picker'),
                  onPressed: () async {
                    final out = await showPickSourceMeasuredOutcomeDialog(
                      measurementsRef: measurementsRef,
                      projectId: projectId,
                      buildingId: buildingId,
                      allDrawingsInBuilding: true,
                      drawingId: drawingId,
                    );

                    if (out.error != null) {
                      Get.snackbar('Pick failed', out.error!);
                      return;
                    }
                    if (out.source == null) return;

                    final s0 = out.source!;
                    // ✅ Return QtySourceDoc
                    Navigator.pop(
                      dialogCtx,
                      QtySourceDoc(
                        docId: s0.docId, // measured doc id
                        boqItemId: null,
                        boqCode: s0.boqCode,
                        boqDescription: s0.boqDescription,
                        unit: s0.unit,
                        value: s0.value,
                        sourceKind: QtySourceMode.measured,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tip: Use this when source qty comes from actual measurements.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          );
        }

        Widget overridesTab() {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Pick from BOQ qtyOverride (manual override)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search (code / description)...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => search.value = v.trim().toLowerCase(),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream:
                        boqRef
                            .where('qtyOverride', isGreaterThan: 0)
                            .snapshots(),
                    builder: (c, snap) {
                      if (snap.hasError) return Text('Error: ${snap.error}');
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data!.docs.toList();

                      int billInt(String x) => int.tryParse(x.trim()) ?? 9999;
                      String codeOf(Map<String, dynamic> d) {
                        final r = _s(d['resolvedBoqCode']).trim();
                        final b = _s(d['boqCode']).trim();
                        return r.isNotEmpty ? r : b;
                      }

                      docs.sort((a, b) {
                        final da = a.data();
                        final db = b.data();
                        final ba = billInt(_s(da['billCode']));
                        final bb = billInt(_s(db['billCode']));
                        final c1 = ba.compareTo(bb);
                        if (c1 != 0) return c1;
                        return codeOf(da).compareTo(codeOf(db));
                      });

                      return Obx(() {
                        final q = search.value;
                        final filtered =
                            q.isEmpty
                                ? docs
                                : docs.where((x) {
                                  final d = x.data();
                                  final code = codeOf(d).toLowerCase();
                                  final desc =
                                      _s(d['description']).toLowerCase();
                                  return code.contains(q) || desc.contains(q);
                                }).toList();

                        if (filtered.isEmpty) {
                          return const Center(
                            child: Text('No override items found.'),
                          );
                        }

                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final doc = filtered[i];
                            final d = doc.data();
                            final code = codeOf(d);
                            final desc = _s(d['description']).trim();
                            final unit = _s(d['unit']).trim();
                            final qtyO = _num(d['qtyOverride']);

                            return ListTile(
                              dense: true,
                              title: Text(
                                '$code — $desc',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Override: ${qtyO.toStringAsFixed(3)} $unit',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(
                                  dialogCtx,
                                  QtySourceDoc(
                                    docId: null,
                                    boqItemId: doc.id, // ✅ BOQ doc id
                                    boqCode: code,
                                    boqDescription: desc,
                                    unit: unit,
                                    value: qtyO,
                                    sourceKind: QtySourceMode.boqOverride,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          title: const Text('Pick link source'),
          content: SizedBox(
            width: 820,
            height: 520,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [Tab(text: 'Measured'), Tab(text: 'BOQ Overrides')],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [measuredTab(), overridesTab()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createLinks() async {
    linkedCtrl.clearError();

    final src = linkedCtrl.source.value;
    if (src == null) {
      linkedCtrl.setError('Pick a SOURCE first.');
      return;
    }
    if (linkedCtrl.targets.isEmpty) {
      linkedCtrl.setError('Add at least one TARGET BOQ.');
      return;
    }

    Get.dialog(
      const AlertDialog(
        content: SizedBox(
          height: 54,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Creating links...')),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      await repo.upsertDerivedLinks(
        measurementsRef: measurementsRef,
        projectId: projectId,
        buildingId: buildingId,
        drawingId: drawingId,
        source: src, // ✅ QtySourceDoc
        targets: linkedCtrl.targets.toList(),
      );

      if (Get.isDialogOpen == true) Get.back();
      Get.snackbar('Done', 'Links created / updated.');
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      linkedCtrl.setError('Create links failed:\n$e');
    }
  }

  Widget _errorBox() {
    return Obx(() {
      final msg = linkedCtrl.inlineError.value.trim();
      if (msg.isEmpty) return const SizedBox.shrink();

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
            IconButton(
              onPressed: linkedCtrl.clearError,
              icon: const Icon(Icons.close, size: 18),
              color: Colors.red,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    });
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dctx) {
      return AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        backgroundColor: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
        actionsPadding: const EdgeInsets.fromLTRB(28, 10, 28, 22),
        title: Container(
          padding: const EdgeInsets.fromLTRB(28, 22, 18, 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF17366D), Color(0xFF2563EB)],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Linked BOQ items',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manage every auto-sync source and target pair',
                      style: TextStyle(
                        color: Color(0xFFDCE8FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 1080,
          height: 680,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                _errorBox(),
                const TabBar(
                  tabs: [
                    Tab(text: 'Existing links'),
                    Tab(text: 'Create new link'),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      // ------------------------------------------------------------
                      // TAB 1: EXISTING LINKS
                      // ------------------------------------------------------------
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _existingLinksQuery().snapshots(),
                        builder: (ctx, snap) {
                          if (snap.hasError) {
                            return Center(child: Text('Error: ${snap.error}'));
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return const Center(child: Text('No links found.'));
                          }

                          // One derived document represents one source-target
                          // relationship. Keep each relationship as its own pair
                          // so either side can be corrected independently.
                          final groups = <String, List<Map<String, dynamic>>>{};
                          for (final d in docs) {
                            final m = d.data();
                            final key = d.id;
                            groups.putIfAbsent(
                              key,
                              () => <Map<String, dynamic>>[],
                            );
                            groups[key]!.add({...m, '__id': d.id});
                          }

                          final keys = groups.keys.toList()..sort();

                          return ListView.builder(
                            itemCount: keys.length,
                            itemBuilder: (ctx, i) {
                              final k = keys[i];
                              final items =
                                  groups[k]!..sort(
                                    (a, b) => _s(
                                      a['boqCode'],
                                    ).compareTo(_s(b['boqCode'])),
                                  );

                              final first = items.first;
                              final mode = _s(first['derivedFromMode']).trim();
                              final srcCode = _s(first['sourceBoqCode']).trim();
                              final srcDesc =
                                  _s(first['sourceBoqDescription']).trim();

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${mode.toUpperCase()} SOURCE: $srcCode — $srcDesc',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final picked =
                                                  await _pickSourceAny(dctx);
                                              if (picked == null) return;
                                              try {
                                                await repo.replaceDerivedSource(
                                                  derivedRef: measurementsRef
                                                      .doc(_s(first['__id'])),
                                                  source: picked,
                                                  factor: _num(
                                                    first['derivedFactor'],
                                                  ),
                                                  offset: _num(
                                                    first['derivedOffset'],
                                                  ),
                                                );
                                              } catch (e) {
                                                linkedCtrl.setError(
                                                  'Could not change source: $e',
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.swap_horiz),
                                            label: const Text('Change source'),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              final ok = await showDialog<bool>(
                                                context: dctx,
                                                builder:
                                                    (_) => AlertDialog(
                                                      title: const Text(
                                                        'Delete this link pair?',
                                                      ),
                                                      content: Text(
                                                        'This removes the connection between this source and target. Continue?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    dctx,
                                                                    false,
                                                                  ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        FilledButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    dctx,
                                                                    true,
                                                                  ),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );
                                              if (ok != true) return;

                                              try {
                                                await measurementsRef
                                                    .doc(_s(first['__id']))
                                                    .delete();
                                                Get.snackbar(
                                                  'Deleted',
                                                  'Link pair removed.',
                                                );
                                              } catch (e) {
                                                Get.snackbar(
                                                  'Delete failed',
                                                  '$e',
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            label: const Text('Delete pair'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ...items.map((m) {
                                        final tgt = _s(m['boqCode']).trim();
                                        final desc =
                                            _s(m['boqDescription']).trim();
                                        final f = _num(m['derivedFactor']);
                                        final off = _num(m['derivedOffset']);
                                        final unit = _s(m['unit']).trim();
                                        final v = _num(m['value']);

                                        return Container(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Color(0xFFE2E8F0),
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.south_rounded,
                                                color: Color(0xFF2563EB),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'TARGET: $tgt — $desc',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Rule: source × ${f.toStringAsFixed(3)} + ${off.toStringAsFixed(3)}  =  ${v.toStringAsFixed(3)} $unit',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              OutlinedButton.icon(
                                                onPressed: () async {
                                                  try {
                                                    final picked =
                                                        await pickTargetBoq(
                                                          dctx,
                                                        );
                                                    if (picked == null) return;
                                                    await repo
                                                        .replaceDerivedTarget(
                                                          derivedRef:
                                                              measurementsRef
                                                                  .doc(
                                                                    _s(
                                                                      m['__id'],
                                                                    ),
                                                                  ),
                                                          target: picked,
                                                        );
                                                  } catch (e) {
                                                    linkedCtrl.setError(
                                                      'Could not change target: $e',
                                                    );
                                                  }
                                                },
                                                icon: const Icon(
                                                  Icons.swap_horiz,
                                                ),
                                                label: const Text(
                                                  'Change target',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),

                      // ------------------------------------------------------------
                      // TAB 2: CREATE NEW LINK
                      // ------------------------------------------------------------
                      SingleChildScrollView(
                        child: Obx(() {
                          final src = linkedCtrl.source.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // SOURCE
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Source (Measured or BOQ Override)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      linkedCtrl.clearError();
                                      final picked = await _pickSourceAny(dctx);
                                      if (picked != null) {
                                        linkedCtrl.setSource(
                                          picked,
                                        ); // ✅ QtySourceDoc
                                      }
                                    },
                                    icon: const Icon(Icons.search),
                                    label: const Text('Pick source'),
                                  ),
                                  const SizedBox(width: 8),
                                  if (src != null)
                                    OutlinedButton(
                                      onPressed: () {
                                        linkedCtrl.clearError();
                                        linkedCtrl.source.value = null;
                                      },
                                      child: const Text('Clear'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              if (src == null)
                                const Text(
                                  'No source selected.',
                                  style: TextStyle(fontSize: 12),
                                )
                              else
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_modeLabel(src)}: ${src.boqCode} — ${src.value.toStringAsFixed(3)} ${src.unit}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          src.boqDescription,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              const Divider(height: 24),

                              // TARGETS
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Targets (BOQ items to receive qty)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      linkedCtrl.clearError();
                                      try {
                                        final p = await pickTargetBoq(dctx);
                                        if (p != null) linkedCtrl.addTarget(p);
                                      } catch (e) {
                                        linkedCtrl.setError(
                                          'Pick target failed:\n$e',
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.add_link),
                                    label: const Text('Add target'),
                                  ),
                                  const SizedBox(width: 8),
                                  if (linkedCtrl.targets.isNotEmpty)
                                    OutlinedButton(
                                      onPressed: () {
                                        linkedCtrl.clearError();
                                        linkedCtrl.targets.clear();
                                      },
                                      child: const Text('Clear'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              if (linkedCtrl.targets.isEmpty)
                                const Text(
                                  'No targets yet.',
                                  style: TextStyle(fontSize: 12),
                                )
                              else
                                ...List.generate(linkedCtrl.targets.length, (
                                  i,
                                ) {
                                  final t = linkedCtrl.targets[i];
                                  final srcVal = src?.value ?? 0.0;
                                  final srcUnit = src?.unit ?? '';
                                  final derived =
                                      (srcVal * t.factor) + t.offset;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${t.boq.code} — ${t.boq.description}',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  linkedCtrl.clearError();
                                                  linkedCtrl.removeTargetAt(i);
                                                },
                                                icon: const Icon(Icons.close),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            src == null
                                                ? 'Pick a source to preview derived qty.'
                                                : 'Derived qty: ${derived.toStringAsFixed(3)} $srcUnit',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  initialValue:
                                                      t.factor.toString(),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  decoration:
                                                      const InputDecoration(
                                                        border:
                                                            OutlineInputBorder(),
                                                        isDense: true,
                                                        labelText: 'Factor (×)',
                                                      ),
                                                  onChanged:
                                                      (v) =>
                                                          linkedCtrl.setFactor(
                                                            i,
                                                            _parseNum(v, 1.0),
                                                          ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextFormField(
                                                  initialValue:
                                                      t.offset.toString(),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  decoration:
                                                      const InputDecoration(
                                                        border:
                                                            OutlineInputBorder(),
                                                        isDense: true,
                                                        labelText: 'Offset (+)',
                                                      ),
                                                  onChanged:
                                                      (v) =>
                                                          linkedCtrl.setOffset(
                                                            i,
                                                            _parseNum(v, 0.0),
                                                          ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          );
                        }),
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
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Close'),
          ),
          Obx(() {
            final enabled =
                linkedCtrl.source.value != null &&
                linkedCtrl.targets.isNotEmpty;
            return FilledButton.icon(
              onPressed: enabled ? _createLinks : null,
              icon: const Icon(Icons.link),
              label: const Text('Create links'),
            );
          }),
        ],
      );
    },
  );
}

// Future<void> showLinkedItemsDialog({
//   required BuildContext context,
//   required LinkedAutoSyncController linkedCtrl,
//   required LinkRepository repo,
//   required LinksContext ctxp,
//   required Future<BoqPick?> Function(BuildContext ctx) pickTargetBoq,
// }) async {
//   final measurementsRef = ctxp.measurementsRef;
//   final projectId = ctxp.projectId;
//   final buildingId = ctxp.buildingId;
//   final drawingId = ctxp.drawingId;

//   // -------- safe helpers --------
//   String _s(dynamic v) => (v ?? '').toString();
//   double _num(dynamic v) =>
//       (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

//   double _parseNum(String s, double fallback) =>
//       double.tryParse(s.trim()) ?? fallback;

//   // If your path differs, change this:
//   CollectionReference<Map<String, dynamic>> _boqRefFromCtx() {
//     return FirebaseFirestore.instance
//         .collection('projects')
//         .doc(projectId)
//         .collection('buildings')
//         .doc(buildingId)
//         .collection('boq');
//   }

//   final boqRef = _boqRefFromCtx();

//   Query<Map<String, dynamic>> _existingLinksQuery() {
//     return measurementsRef
//         .where('projectId', isEqualTo: projectId)
//         .where('buildingId', isEqualTo: buildingId)
//         .where('drawingId', isEqualTo: drawingId)
//         .where('isDerived', isEqualTo: true)
//         .where('derivedFromMode', whereIn: ['doc', 'boq']);
//   }

//   Future<void> _deleteLinkGroup({
//     required String derivedFromMode,
//     required String fromId,
//   }) async {
//     final base = measurementsRef
//         .where('projectId', isEqualTo: projectId)
//         .where('buildingId', isEqualTo: buildingId)
//         .where('drawingId', isEqualTo: drawingId)
//         .where('isDerived', isEqualTo: true)
//         .where('derivedFromMode', isEqualTo: derivedFromMode);

//     final QuerySnapshot<Map<String, dynamic>> snap;
//     if (derivedFromMode == 'boq') {
//       snap = await base.where('derivedFromBoqItemId', isEqualTo: fromId).get();
//     } else {
//       snap = await base.where('derivedFromDocId', isEqualTo: fromId).get();
//     }

//     if (snap.docs.isEmpty) return;

//     final batch = FirebaseFirestore.instance.batch();
//     for (final d in snap.docs) {
//       batch.delete(d.reference);
//     }
//     await batch.commit();
//   }

//   String _modeLabel(QtySourceDoc s0) {
//     // adjust if your enum names differ
//     switch (s0.sourceKind) {
//       case QtySourceMode.measured:
//         return 'MEASURED';
//       case QtySourceMode.boqOverride:
//         return 'BOQ OVERRIDE';
//       default:
//         return 'SOURCE';
//     }
//   }

//   // ------------------------------------------------------------
//   // PICK SOURCE (Measured / BOQ Overrides)  ✅ returns QtySourceDoc
//   // ------------------------------------------------------------
//   Future<QtySourceDoc?> _pickSourceAny(BuildContext dctx) async {
//     return showDialog<QtySourceDoc>(
//       context: dctx,
//       barrierDismissible: true,
//       builder: (dialogCtx) {
//         final searchCtrl = TextEditingController();
//         final search = ''.obs;

//         Widget measuredTab() {
//           return Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Text(
//                   'Pick from measured items (from Measurements)',
//                   style: TextStyle(fontWeight: FontWeight.w700),
//                 ),
//                 const SizedBox(height: 10),
//                 FilledButton.icon(
//                   icon: const Icon(Icons.search),
//                   label: const Text('Open measured picker'),
//                   onPressed: () async {
//                     final out = await showPickSourceMeasuredOutcomeDialog(
//                       measurementsRef: measurementsRef,
//                       projectId: projectId,
//                       buildingId: buildingId,
//                       allDrawingsInBuilding: true,
//                       drawingId: drawingId,
//                     );

//                     if (out.error != null) {
//                       Get.snackbar('Pick failed', out.error!);
//                       return;
//                     }
//                     if (out.source == null) return;

//                     final s0 = out.source!;
//                     // ✅ Return QtySourceDoc
//                     Navigator.pop(
//                       dialogCtx,
//                       QtySourceDoc(
//                         docId: s0.docId, // measured doc id
//                         boqItemId: null,
//                         boqCode: s0.boqCode,
//                         boqDescription: s0.boqDescription,
//                         unit: s0.unit,
//                         value: s0.value,
//                         sourceKind: QtySourceMode.measured,
//                       ),
//                     );
//                   },
//                 ),
//                 const SizedBox(height: 10),
//                 const Text(
//                   'Tip: Use this when source qty comes from actual measurements.',
//                   style: TextStyle(fontSize: 12),
//                 ),
//               ],
//             ),
//           );
//         }

//         Widget overridesTab() {
//           return Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               children: [
//                 const Align(
//                   alignment: Alignment.centerLeft,
//                   child: Text(
//                     'Pick from BOQ qtyOverride (manual override)',
//                     style: TextStyle(fontWeight: FontWeight.w700),
//                   ),
//                 ),
//                 const SizedBox(height: 10),
//                 TextField(
//                   controller: searchCtrl,
//                   decoration: const InputDecoration(
//                     prefixIcon: Icon(Icons.search),
//                     hintText: 'Search (code / description)...',
//                     border: OutlineInputBorder(),
//                     isDense: true,
//                   ),
//                   onChanged: (v) => search.value = v.trim().toLowerCase(),
//                 ),
//                 const SizedBox(height: 10),
//                 Expanded(
//                   child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                     stream: boqRef
//                         .where('qtyOverride', isGreaterThan: 0)
//                         .snapshots(),
//                     builder: (c, snap) {
//                       if (snap.hasError) return Text('Error: ${snap.error}');
//                       if (!snap.hasData) {
//                         return const Center(child: CircularProgressIndicator());
//                       }

//                       final docs = snap.data!.docs.toList();

//                       int billInt(String x) => int.tryParse(x.trim()) ?? 9999;
//                       String codeOf(Map<String, dynamic> d) {
//                         final r = _s(d['resolvedBoqCode']).trim();
//                         final b = _s(d['boqCode']).trim();
//                         return r.isNotEmpty ? r : b;
//                       }

//                       docs.sort((a, b) {
//                         final da = a.data();
//                         final db = b.data();
//                         final ba = billInt(_s(da['billCode']));
//                         final bb = billInt(_s(db['billCode']));
//                         final c1 = ba.compareTo(bb);
//                         if (c1 != 0) return c1;
//                         return codeOf(da).compareTo(codeOf(db));
//                       });

//                       return Obx(() {
//                         final q = search.value;
//                         final filtered = q.isEmpty
//                             ? docs
//                             : docs.where((x) {
//                                 final d = x.data();
//                                 final code = codeOf(d).toLowerCase();
//                                 final desc = _s(d['description']).toLowerCase();
//                                 return code.contains(q) || desc.contains(q);
//                               }).toList();

//                         if (filtered.isEmpty) {
//                           return const Center(child: Text('No override items found.'));
//                         }

//                         return ListView.separated(
//                           itemCount: filtered.length,
//                           separatorBuilder: (_, __) => const Divider(height: 1),
//                           itemBuilder: (_, i) {
//                             final doc = filtered[i];
//                             final d = doc.data();
//                             final code = codeOf(d);
//                             final desc = _s(d['description']).trim();
//                             final unit = _s(d['unit']).trim();
//                             final qtyO = _num(d['qtyOverride']);

//                             return ListTile(
//                               dense: true,
//                               title: Text(
//                                 '$code — $desc',
//                                 maxLines: 2,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                               subtitle: Text(
//                                 'Override: ${qtyO.toStringAsFixed(3)} $unit',
//                               ),
//                               trailing: const Icon(Icons.chevron_right),
//                               onTap: () {
//                                 Navigator.pop(
//                                   dialogCtx,
//                                   QtySourceDoc(
//                                     docId: null,
//                                     boqItemId: doc.id, // ✅ BOQ doc id
//                                     boqCode: code,
//                                     boqDescription: desc,
//                                     unit: unit,
//                                     value: qtyO,
//                                     sourceKind: QtySourceMode.boqOverride,
//                                   ),
//                                 );
//                               },
//                             );
//                           },
//                         );
//                       });
//                     },
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }

//         return AlertDialog(
//           title: const Text('Pick link source'),
//           content: SizedBox(
//             width: 820,
//             height: 520,
//             child: DefaultTabController(
//               length: 2,
//               child: Column(
//                 children: [
//                   const TabBar(
//                     tabs: [Tab(text: 'Measured'), Tab(text: 'BOQ Overrides')],
//                   ),
//                   const SizedBox(height: 10),
//                   Expanded(
//                     child: TabBarView(
//                       children: [
//                         measuredTab(),
//                         overridesTab(),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(dialogCtx),
//               child: const Text('Close'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   Future<void> _createLinks() async {
//     linkedCtrl.clearError();

//     final src = linkedCtrl.source.value;
//     if (src == null) {
//       linkedCtrl.setError('Pick a SOURCE first.');
//       return;
//     }
//     if (linkedCtrl.targets.isEmpty) {
//       linkedCtrl.setError('Add at least one TARGET BOQ.');
//       return;
//     }

//     Get.dialog(
//       const AlertDialog(
//         content: SizedBox(
//           height: 54,
//           child: Row(
//             children: [
//               SizedBox(
//                 width: 22,
//                 height: 22,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               ),
//               SizedBox(width: 12),
//               Expanded(child: Text('Creating links...')),
//             ],
//           ),
//         ),
//       ),
//       barrierDismissible: false,
//     );

//     try {
//       await repo.upsertDerivedLinks(
//         measurementsRef: measurementsRef,
//         projectId: projectId,
//         buildingId: buildingId,
//         drawingId: drawingId,
//         source: src, // ✅ QtySourceDoc
//         targets: linkedCtrl.targets.toList(),
//       );

//       if (Get.isDialogOpen == true) Get.back();
//       Get.snackbar('Done', 'Links created / updated.');
//     } catch (e) {
//       if (Get.isDialogOpen == true) Get.back();
//       linkedCtrl.setError('Create links failed:\n$e');
//     }
//   }

//   Widget _errorBox() {
//     return Obx(() {
//       final msg = linkedCtrl.inlineError.value.trim();
//       if (msg.isEmpty) return const SizedBox.shrink();

//       return Container(
//         width: double.infinity,
//         padding: const EdgeInsets.all(10),
//         margin: const EdgeInsets.only(bottom: 10),
//         decoration: BoxDecoration(
//           color: Colors.red.withOpacity(0.08),
//           border: Border.all(color: Colors.red.withOpacity(0.35)),
//           borderRadius: BorderRadius.circular(10),
//         ),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Icon(Icons.error_outline, size: 18, color: Colors.red),
//             const SizedBox(width: 8),
//             Expanded(
//               child: Text(
//                 msg,
//                 style: const TextStyle(fontSize: 12, color: Colors.red),
//               ),
//             ),
//             IconButton(
//               onPressed: linkedCtrl.clearError,
//               icon: const Icon(Icons.close, size: 18),
//               color: Colors.red,
//               padding: EdgeInsets.zero,
//               constraints: const BoxConstraints(),
//             ),
//           ],
//         ),
//       );
//     });
//   }

//   await showDialog<void>(
//     context: context,
//     barrierDismissible: true,
//     builder: (dctx) {
//       return AlertDialog(
//         title: const Text('Linked items (auto-sync)'),
//         content: SizedBox(
//           width: 860,
//           height: 600,
//           child: DefaultTabController(
//             length: 2,
//             child: Column(
//               children: [
//                 const TabBar(
//                   tabs: [
//                     Tab(text: 'Existing links'),
//                     Tab(text: 'Create new link'),
//                   ],
//                 ),
//                 const SizedBox(height: 10),
//                 Expanded(
//                   child: TabBarView(
//                     children: [
//                       // ------------------------------------------------------------
//                       // TAB 1: EXISTING LINKS
//                       // ------------------------------------------------------------
//                       StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                         stream: _existingLinksQuery().snapshots(),
//                         builder: (ctx, snap) {
//                           if (snap.hasError) {
//                             return Center(child: Text('Error: ${snap.error}'));
//                           }
//                           if (!snap.hasData) {
//                             return const Center(child: CircularProgressIndicator());
//                           }

//                           final docs = snap.data!.docs;
//                           if (docs.isEmpty) {
//                             return const Center(child: Text('No links found.'));
//                           }

//                           // group by source key (doc or boq)
//                           final groups = <String, List<Map<String, dynamic>>>{};
//                           for (final d in docs) {
//                             final m = d.data();
//                             final mode = _s(m['derivedFromMode']).trim();
//                             final key = (mode == 'boq')
//                                 ? 'boq:${_s(m['derivedFromBoqItemId']).trim()}'
//                                 : 'doc:${_s(m['derivedFromDocId']).trim()}';
//                             groups.putIfAbsent(key, () => <Map<String, dynamic>>[]);
//                             groups[key]!.add({...m, '__id': d.id});
//                           }

//                           final keys = groups.keys.toList()..sort();

//                           return ListView.builder(
//                             itemCount: keys.length,
//                             itemBuilder: (ctx, i) {
//                               final k = keys[i];
//                               final items = groups[k]!
//                                 ..sort((a, b) => _s(a['boqCode']).compareTo(_s(b['boqCode'])));

//                               final first = items.first;
//                               final mode = _s(first['derivedFromMode']).trim();
//                               final fromId = mode == 'boq'
//                                   ? _s(first['derivedFromBoqItemId']).trim()
//                                   : _s(first['derivedFromDocId']).trim();

//                               final srcCode = _s(first['sourceBoqCode']).trim();
//                               final srcDesc = _s(first['sourceBoqDescription']).trim();

//                               return Card(
//                                 margin: const EdgeInsets.only(bottom: 10),
//                                 child: Padding(
//                                   padding: const EdgeInsets.all(12),
//                                   child: Column(
//                                     crossAxisAlignment: CrossAxisAlignment.start,
//                                     children: [
//                                       Row(
//                                         children: [
//                                           Expanded(
//                                             child: Text(
//                                               '${mode.toUpperCase()} SOURCE: $srcCode — $srcDesc',
//                                               style: const TextStyle(fontWeight: FontWeight.w800),
//                                             ),
//                                           ),
//                                           OutlinedButton.icon(
//                                             onPressed: () async {
//                                               final ok = await showDialog<bool>(
//                                                 context: dctx,
//                                                 builder: (_) => AlertDialog(
//                                                   title: const Text('Delete link group?'),
//                                                   content: Text(
//                                                     'This will delete ${items.length} derived rows. Continue?',
//                                                   ),
//                                                   actions: [
//                                                     TextButton(
//                                                       onPressed: () => Navigator.pop(dctx, false),
//                                                       child: const Text('Cancel'),
//                                                     ),
//                                                     FilledButton(
//                                                       onPressed: () => Navigator.pop(dctx, true),
//                                                       child: const Text('Delete'),
//                                                     ),
//                                                   ],
//                                                 ),
//                                               );
//                                               if (ok != true) return;

//                                               try {
//                                                 await _deleteLinkGroup(
//                                                   derivedFromMode: mode,
//                                                   fromId: fromId,
//                                                 );
//                                                 Get.snackbar('Deleted', 'Link group removed.');
//                                               } catch (e) {
//                                                 Get.snackbar('Delete failed', '$e');
//                                               }
//                                             },
//                                             icon: const Icon(Icons.delete_outline),
//                                             label: const Text('Delete'),
//                                           ),
//                                         ],
//                                       ),
//                                       const SizedBox(height: 10),
//                                       ...items.map((m) {
//                                         final tgt = _s(m['boqCode']).trim();
//                                         final desc = _s(m['boqDescription']).trim();
//                                         final f = _num(m['derivedFactor']);
//                                         final off = _num(m['derivedOffset']);
//                                         final unit = _s(m['unit']).trim();
//                                         final v = _num(m['value']);

//                                         return Padding(
//                                           padding: const EdgeInsets.only(bottom: 8),
//                                           child: Text(
//                                             '$tgt — $desc\n'
//                                             'rule: (src × ${f.toStringAsFixed(3)}) + ${off.toStringAsFixed(3)}  →  ${v.toStringAsFixed(3)} $unit',
//                                             style: const TextStyle(fontSize: 12),
//                                           ),
//                                         );
//                                       }),
//                                     ],
//                                   ),
//                                 ),
//                               );
//                             },
//                           );
//                         },
//                       ),

//                       // ------------------------------------------------------------
//                       // TAB 2: CREATE NEW LINK
//                       // ------------------------------------------------------------
//                       SingleChildScrollView(
//                         child: Obx(() {
//                           final src = linkedCtrl.source.value;

//                           return Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               _errorBox(),

//                               // SOURCE
//                               Row(
//                                 children: [
//                                   const Expanded(
//                                     child: Text(
//                                       'Source (Measured or BOQ Override)',
//                                       style: TextStyle(fontWeight: FontWeight.w800),
//                                     ),
//                                   ),
//                                   OutlinedButton.icon(
//                                     onPressed: () async {
//                                       linkedCtrl.clearError();
//                                       final picked = await _pickSourceAny(dctx);
//                                       if (picked != null) {
//                                         linkedCtrl.setSource(picked); // ✅ QtySourceDoc
//                                       }
//                                     },
//                                     icon: const Icon(Icons.search),
//                                     label: const Text('Pick source'),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   if (src != null)
//                                     OutlinedButton(
//                                       onPressed: () {
//                                         linkedCtrl.clearError();
//                                         linkedCtrl.source.value = null;
//                                       },
//                                       child: const Text('Clear'),
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),

//                               if (src == null)
//                                 const Text('No source selected.', style: TextStyle(fontSize: 12))
//                               else
//                                 Card(
//                                   child: Padding(
//                                     padding: const EdgeInsets.all(10),
//                                     child: Column(
//                                       crossAxisAlignment: CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           '${_modeLabel(src)}: ${src.boqCode} — ${src.value.toStringAsFixed(3)} ${src.unit}',
//                                           style: const TextStyle(fontWeight: FontWeight.w700),
//                                         ),
//                                         const SizedBox(height: 6),
//                                         Text(src.boqDescription, style: const TextStyle(fontSize: 12)),
//                                       ],
//                                     ),
//                                   ),
//                                 ),

//                               const Divider(height: 24),

//                               // TARGETS
//                               Row(
//                                 children: [
//                                   const Expanded(
//                                     child: Text(
//                                       'Targets (BOQ items to receive qty)',
//                                       style: TextStyle(fontWeight: FontWeight.w800),
//                                     ),
//                                   ),
//                                   OutlinedButton.icon(
//                                     onPressed: () async {
//                                       linkedCtrl.clearError();
//                                       try {
//                                         final p = await pickTargetBoq(dctx);
//                                         if (p != null) linkedCtrl.addTarget(p);
//                                       } catch (e) {
//                                         linkedCtrl.setError('Pick target failed:\n$e');
//                                       }
//                                     },
//                                     icon: const Icon(Icons.add_link),
//                                     label: const Text('Add target'),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   if (linkedCtrl.targets.isNotEmpty)
//                                     OutlinedButton(
//                                       onPressed: () {
//                                         linkedCtrl.clearError();
//                                         linkedCtrl.targets.clear();
//                                       },
//                                       child: const Text('Clear'),
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 10),

//                               if (linkedCtrl.targets.isEmpty)
//                                 const Text('No targets yet.', style: TextStyle(fontSize: 12))
//                               else
//                                 ...List.generate(linkedCtrl.targets.length, (i) {
//                                   final t = linkedCtrl.targets[i];
//                                   final srcVal = src?.value ?? 0.0;
//                                   final srcUnit = src?.unit ?? '';
//                                   final derived = (srcVal * t.factor) + t.offset;

//                                   return Card(
//                                     margin: const EdgeInsets.only(bottom: 10),
//                                     child: Padding(
//                                       padding: const EdgeInsets.all(10),
//                                       child: Column(
//                                         crossAxisAlignment: CrossAxisAlignment.start,
//                                         children: [
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: Text(
//                                                   '${t.boq.code} — ${t.boq.description}',
//                                                   maxLines: 2,
//                                                   overflow: TextOverflow.ellipsis,
//                                                   style: const TextStyle(fontWeight: FontWeight.w700),
//                                                 ),
//                                               ),
//                                               IconButton(
//                                                 onPressed: () {
//                                                   linkedCtrl.clearError();
//                                                   linkedCtrl.removeTargetAt(i);
//                                                 },
//                                                 icon: const Icon(Icons.close),
//                                               ),
//                                             ],
//                                           ),
//                                           const SizedBox(height: 6),
//                                           Text(
//                                             src == null
//                                                 ? 'Pick a source to preview derived qty.'
//                                                 : 'Derived qty: ${derived.toStringAsFixed(3)} $srcUnit',
//                                             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
//                                           ),
//                                           const SizedBox(height: 8),
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: TextFormField(
//                                                   initialValue: t.factor.toString(),
//                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
//                                                   decoration: const InputDecoration(
//                                                     border: OutlineInputBorder(),
//                                                     isDense: true,
//                                                     labelText: 'Factor (×)',
//                                                   ),
//                                                   onChanged: (v) => linkedCtrl.setFactor(i, _parseNum(v, 1.0)),
//                                                 ),
//                                               ),
//                                               const SizedBox(width: 8),
//                                               Expanded(
//                                                 child: TextFormField(
//                                                   initialValue: t.offset.toString(),
//                                                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
//                                                   decoration: const InputDecoration(
//                                                     border: OutlineInputBorder(),
//                                                     isDense: true,
//                                                     labelText: 'Offset (+)',
//                                                   ),
//                                                   onChanged: (v) => linkedCtrl.setOffset(i, _parseNum(v, 0.0)),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   );
//                                 }),
//                             ],
//                           );
//                         }),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(dctx),
//             child: const Text('Close'),
//           ),
//           Obx(() {
//             final enabled = linkedCtrl.source.value != null && linkedCtrl.targets.isNotEmpty;
//             return FilledButton.icon(
//               onPressed: enabled ? _createLinks : null,
//               icon: const Icon(Icons.link),
//               label: const Text('Create links'),
//             );
//           }),
//         ],
//       );
//     },
//   );

// // Future<void> showLinkedItemsDialog({
// //   required BuildContext context,}
// //   required LinkedAutoSyncController linkedCtrl,
// //   required LinkRepository repo,
// //   required LinksContext ctxp,
// //   required Future<BoqPick?> Function(BuildContext ctx) pickTargetBoq,
// // }) async {
// //   final measurementsRef = ctxp.measurementsRef;
// //   final projectId = ctxp.projectId;
// //   final buildingId = ctxp.buildingId;
// //   final drawingId = ctxp.drawingId;

// //   // -------- safe helpers --------
// //   String _s(dynamic v) => (v ?? '').toString();
// //   double _num(dynamic v) =>
// //       (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

// //   double _parseNum(String s, double fallback) =>
// //       double.tryParse(s.trim()) ?? fallback;

// //   // If your path differs, change this:
// //   CollectionReference<Map<String, dynamic>> _boqRefFromCtx() {
// //     return FirebaseFirestore.instance
// //         .collection('projects')
// //         .doc(projectId)
// //         .collection('buildings')
// //         .doc(buildingId)
// //         .collection('boq');
// //   }

// //   final boqRef = _boqRefFromCtx();

// //   Query<Map<String, dynamic>> _existingLinksQuery() {
// //     // derived docs live in measurementsRef
// //     return measurementsRef
// //         .where('projectId', isEqualTo: projectId)
// //         .where('buildingId', isEqualTo: buildingId)
// //         .where('drawingId', isEqualTo: drawingId)
// //         .where('isDerived', isEqualTo: true)
// //         .where('derivedFromMode', whereIn: ['doc', 'boq']);
// //   }

// //   Future<void> _deleteLinkGroup({
// //     required String derivedFromMode,
// //     required String fromId,
// //   }) async {
// //     // delete all derived docs created from this source
// //     final q = measurementsRef
// //         .where('projectId', isEqualTo: projectId)
// //         .where('buildingId', isEqualTo: buildingId)
// //         .where('drawingId', isEqualTo: drawingId)
// //         .where('isDerived', isEqualTo: true)
// //         .where('derivedFromMode', isEqualTo: derivedFromMode);

// //     final QuerySnapshot<Map<String, dynamic>> snap;
// //     if (derivedFromMode == 'boq') {
// //       snap = await q.where('derivedFromBoqItemId', isEqualTo: fromId).get();
// //     } else {
// //       snap = await q.where('derivedFromDocId', isEqualTo: fromId).get();
// //     }

// //     if (snap.docs.isEmpty) return;

// //     final batch = FirebaseFirestore.instance.batch();
// //     for (final d in snap.docs) {
// //       batch.delete(d.reference);
// //     }
// //     await batch.commit();
// //   }

// //   Future<LinkSource?> _pickSourceAny(BuildContext dctx) async {
// //     return showDialog<LinkSource>(
// //       context: dctx,
// //       barrierDismissible: true,
// //       builder: (dialogCtx) {
// //         final searchCtrl = TextEditingController();
// //         final search = ''.obs;

// //         String _s(dynamic v) => (v ?? '').toString();
// //         double _num(dynamic v) =>
// //             (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

// //         Widget measuredTab() {
// //           return Padding(
// //             padding: const EdgeInsets.all(12),
// //             child: Column(
// //               crossAxisAlignment: CrossAxisAlignment.start,
// //               children: [
// //                 const Text(
// //                   'Pick from measured items (from Measurements)',
// //                   style: TextStyle(fontWeight: FontWeight.w700),
// //                 ),
// //                 const SizedBox(height: 10),
// //                 FilledButton.icon(
// //                   icon: const Icon(Icons.search),
// //                   label: const Text('Open measured picker'),
// //                   onPressed: () async {
// //                     final out = await showPickSourceMeasuredOutcomeDialog(
// //                       measurementsRef: measurementsRef,
// //                       projectId: projectId,
// //                       buildingId: buildingId,
// //                       allDrawingsInBuilding: true,
// //                       drawingId: drawingId,
// //                     );

// //                     if (out.error != null) {
// //                       Get.snackbar('Pick failed', out.error!);
// //                       return;
// //                     }
// //                     if (out.source == null) return;

// //                     final s0 = out.source!;

// //                     // ✅ return LinkSource (measured doc)
// //                     Get.back(
// //                       result: LinkSource.doc(
// //                         docId: s0.docId!,
// //                         boqCode: s0.boqCode,
// //                         boqDescription: s0.boqDescription,
// //                         unit: s0.unit,
// //                         value: s0.value,
// //                       ),
// //                     );
// //                   },
// //                 ),
// //                 const SizedBox(height: 10),
// //                 const Text(
// //                   'Tip: use this for quantities coming from actual measurements.',
// //                   style: TextStyle(fontSize: 12),
// //                 ),
// //               ],
// //             ),
// //           );
// //         }

// //         Widget overridesTab() {
// //           return Padding(
// //             padding: const EdgeInsets.all(12),
// //             child: Column(
// //               children: [
// //                 const Align(
// //                   alignment: Alignment.centerLeft,
// //                   child: Text(
// //                     'Pick from BOQ qtyOverride (manual override)',
// //                     style: TextStyle(fontWeight: FontWeight.w700),
// //                   ),
// //                 ),
// //                 const SizedBox(height: 10),
// //                 TextField(
// //                   controller: searchCtrl,
// //                   decoration: const InputDecoration(
// //                     prefixIcon: Icon(Icons.search),
// //                     hintText: 'Search (code / description)...',
// //                     border: OutlineInputBorder(),
// //                     isDense: true,
// //                   ),
// //                   onChanged: (v) => search.value = v.trim().toLowerCase(),
// //                 ),
// //                 const SizedBox(height: 10),

// //                 Expanded(
// //                   child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
// //                     stream:
// //                         boqRef
// //                             .where('qtyOverride', isGreaterThan: 0)
// //                             .snapshots(),
// //                     builder: (c, snap) {
// //                       if (snap.hasError) return Text('Error: ${snap.error}');
// //                       if (!snap.hasData) {
// //                         return const Center(child: CircularProgressIndicator());
// //                       }

// //                       final docs = snap.data!.docs.toList();

// //                       int billInt(String x) => int.tryParse(x.trim()) ?? 9999;

// //                       String codeOf(Map<String, dynamic> d) {
// //                         final r = _s(d['resolvedBoqCode']).trim();
// //                         final b = _s(d['boqCode']).trim();
// //                         return r.isNotEmpty ? r : b;
// //                       }

// //                       // sort stable + predictable
// //                       docs.sort((a, b) {
// //                         final da = a.data();
// //                         final db = b.data();
// //                         final ba = billInt(_s(da['billCode']));
// //                         final bb = billInt(_s(db['billCode']));
// //                         final c1 = ba.compareTo(bb);
// //                         if (c1 != 0) return c1;
// //                         return codeOf(da).compareTo(codeOf(db));
// //                       });

// //                       return Obx(() {
// //                         final q = search.value;
// //                         final filtered =
// //                             q.isEmpty
// //                                 ? docs
// //                                 : docs.where((x) {
// //                                   final d = x.data();
// //                                   final code = codeOf(d).toLowerCase();
// //                                   final desc =
// //                                       _s(d['description']).toLowerCase();
// //                                   return code.contains(q) || desc.contains(q);
// //                                 }).toList();

// //                         if (filtered.isEmpty) {
// //                           return const Center(
// //                             child: Text('No override items found.'),
// //                           );
// //                         }

// //                         return ListView.separated(
// //                           itemCount: filtered.length,
// //                           separatorBuilder: (_, __) => const Divider(height: 1),
// //                           itemBuilder: (_, i) {
// //                             final doc = filtered[i];
// //                             final d = doc.data();

// //                             final code = codeOf(d);
// //                             final desc = _s(d['description']).trim();
// //                             final unit = _s(d['unit']).trim();
// //                             final qtyO = _num(d['qtyOverride']);

// //                             return ListTile(
// //                               dense: true,
// //                               title: Text(
// //                                 '$code — $desc',
// //                                 maxLines: 2,
// //                                 overflow: TextOverflow.ellipsis,
// //                               ),
// //                               subtitle: Text(
// //                                 'Override: ${qtyO.toStringAsFixed(3)} $unit',
// //                               ),
// //                               trailing: const Icon(Icons.chevron_right),
// //                               onTap: () {
// //                                 // ✅ return LinkSource (boq override)
// //                                 Get.back(
// //                                   result: LinkSource.boq(
// //                                     boqItemId: doc.id,
// //                                     boqCode: code,
// //                                     boqDescription: desc,
// //                                     unit: unit,
// //                                     value: qtyO,
// //                                   ),
// //                                 );
// //                               },
// //                             );
// //                           },
// //                         );
// //                       });
// //                     },
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           );
// //         }

// //         return AlertDialog(
// //           title: const Text('Pick link source'),
// //           content: SizedBox(
// //             width: 820,
// //             height: 520,
// //             child: DefaultTabController(
// //               length: 2,
// //               child: Column(
// //                 children: [
// //                   const TabBar(
// //                     tabs: [Tab(text: 'Measured'), Tab(text: 'BOQ Overrides')],
// //                   ),
// //                   const SizedBox(height: 10),
// //                   Expanded(
// //                     child: TabBarView(
// //                       children: [measuredTab(), overridesTab()],
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ),
// //           actions: [
// //             TextButton(
// //               onPressed: () => Navigator.pop(dialogCtx),
// //               child: const Text('Close'),
// //             ),
// //           ],
// //         );
// //       },
// //     );
// //   }

//   Future<void> _createLinks() async {
//     linkedCtrl.clearError();

//     final src = linkedCtrl.source.value;
//     if (src == null) {
//       linkedCtrl.setError('Pick a SOURCE first.');
//       return;
//     }
//     if (linkedCtrl.targets.isEmpty) {
//       linkedCtrl.setError('Add at least one TARGET BOQ.');
//       return;
//     }

//     // progress
//     Get.dialog(
//       const AlertDialog(
//         content: SizedBox(
//           height: 54,
//           child: Row(
//             children: [
//               SizedBox(
//                 width: 22,
//                 height: 22,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               ),
//               SizedBox(width: 12),
//               Expanded(child: Text('Creating links...')),
//             ],
//           ),
//         ),
//       ),
//       barrierDismissible: false,
//     );

//     try {
//       await repo.upsertDerivedLinks(
//         measurementsRef: measurementsRef,
//         projectId: projectId,
//         buildingId: buildingId,
//         drawingId: drawingId,
//         source: src, // LinkSource
//         targets: linkedCtrl.targets.toList(),
//       );

//       if (Get.isDialogOpen == true) Get.back();
//       Get.snackbar('Done', 'Links created / updated.');
//     } catch (e) {
//       if (Get.isDialogOpen == true) Get.back();
//       linkedCtrl.setError('Create links failed:\n$e');
//     }
//   }

//   Widget _errorBox() {
//     return Obx(() {
//       final msg = linkedCtrl.inlineError.value.trim();
//       if (msg.isEmpty) return const SizedBox.shrink();

//       return Container(
//         width: double.infinity,
//         padding: const EdgeInsets.all(10),
//         margin: const EdgeInsets.only(bottom: 10),
//         decoration: BoxDecoration(
//           color: Colors.red.withOpacity(0.08),
//           border: Border.all(color: Colors.red.withOpacity(0.35)),
//           borderRadius: BorderRadius.circular(10),
//         ),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Icon(Icons.error_outline, size: 18, color: Colors.red),
//             const SizedBox(width: 8),
//             Expanded(
//               child: Text(
//                 msg,
//                 style: const TextStyle(fontSize: 12, color: Colors.red),
//               ),
//             ),
//             IconButton(
//               onPressed: linkedCtrl.clearError,
//               icon: const Icon(Icons.close, size: 18),
//               color: Colors.red,
//               padding: EdgeInsets.zero,
//               constraints: const BoxConstraints(),
//             ),
//           ],
//         ),
//       );
//     });
//   }

//   await showDialog<void>(
//     context: context,
//     barrierDismissible: true,
//     builder: (dctx) {
//       return AlertDialog(
//         title: const Text('Linked items (auto-sync)'),
//         content: SizedBox(
//           width: 860,
//           height: 600,
//           child: DefaultTabController(
//             length: 2,
//             child: Column(
//               children: [
//                 const TabBar(
//                   tabs: [
//                     Tab(text: 'Existing links'),
//                     Tab(text: 'Create new link'),
//                   ],
//                 ),
//                 const SizedBox(height: 10),
//                 Expanded(
//                   child: TabBarView(
//                     children: [
//                       // ------------------------------------------------------------
//                       // TAB 1: EXISTING LINKS
//                       // ------------------------------------------------------------
//                       StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                         stream: _existingLinksQuery().snapshots(),
//                         builder: (ctx, snap) {
//                           if (snap.hasError) {
//                             return Center(child: Text('Error: ${snap.error}'));
//                           }
//                           if (!snap.hasData) {
//                             return const Center(
//                               child: CircularProgressIndicator(),
//                             );
//                           }

//                           final docs = snap.data!.docs;

//                           if (docs.isEmpty) {
//                             return const Center(child: Text('No links found.'));
//                           }

//                           // group by source key
//                           final groups = <String, List<Map<String, dynamic>>>{};
//                           for (final d in docs) {
//                             final m = d.data();
//                             final mode = _s(m['derivedFromMode']).trim();
//                             final key =
//                                 (mode == 'boq')
//                                     ? 'boq:${_s(m['derivedFromBoqItemId']).trim()}'
//                                     : 'doc:${_s(m['derivedFromDocId']).trim()}';
//                             groups.putIfAbsent(
//                               key,
//                               () => <Map<String, dynamic>>[],
//                             );
//                             groups[key]!.add({...m, '__id': d.id});
//                           }

//                           final keys = groups.keys.toList()..sort();

//                           return ListView.builder(
//                             itemCount: keys.length,
//                             itemBuilder: (ctx, i) {
//                               final k = keys[i];
//                               final items =
//                                   groups[k]!..sort(
//                                     (a, b) => _s(
//                                       a['boqCode'],
//                                     ).compareTo(_s(b['boqCode'])),
//                                   );

//                               final first = items.first;
//                               final mode = _s(first['derivedFromMode']).trim();
//                               final fromId =
//                                   mode == 'boq'
//                                       ? _s(first['derivedFromBoqItemId']).trim()
//                                       : _s(first['derivedFromDocId']).trim();

//                               final srcCode = _s(first['sourceBoqCode']).trim();
//                               final srcDesc =
//                                   _s(first['sourceBoqDescription']).trim();

//                               return Card(
//                                 margin: const EdgeInsets.only(bottom: 10),
//                                 child: Padding(
//                                   padding: const EdgeInsets.all(12),
//                                   child: Column(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.start,
//                                     children: [
//                                       Row(
//                                         children: [
//                                           Expanded(
//                                             child: Text(
//                                               '${mode.toUpperCase()} SOURCE: $srcCode — $srcDesc',
//                                               style: const TextStyle(
//                                                 fontWeight: FontWeight.w800,
//                                               ),
//                                             ),
//                                           ),
//                                           OutlinedButton.icon(
//                                             onPressed: () async {
//                                               final ok = await showDialog<bool>(
//                                                 context: dctx,
//                                                 builder:
//                                                     (_) => AlertDialog(
//                                                       title: const Text(
//                                                         'Delete link group?',
//                                                       ),
//                                                       content: Text(
//                                                         'This will delete ${items.length} derived rows. Continue?',
//                                                       ),
//                                                       actions: [
//                                                         TextButton(
//                                                           onPressed:
//                                                               () =>
//                                                                   Navigator.pop(
//                                                                     ctx,
//                                                                     false,
//                                                                   ),
//                                                           child: const Text(
//                                                             'Cancel',
//                                                           ),
//                                                         ),
//                                                         FilledButton(
//                                                           onPressed:
//                                                               () =>
//                                                                   Navigator.pop(
//                                                                     ctx,
//                                                                     true,
//                                                                   ),
//                                                           child: const Text(
//                                                             'Delete',
//                                                           ),
//                                                         ),
//                                                       ],
//                                                     ),
//                                               );
//                                               if (ok != true) return;

//                                               try {
//                                                 await _deleteLinkGroup(
//                                                   derivedFromMode: mode,
//                                                   fromId: fromId,
//                                                 );
//                                                 Get.snackbar(
//                                                   'Deleted',
//                                                   'Link group removed.',
//                                                 );
//                                               } catch (e) {
//                                                 Get.snackbar(
//                                                   'Delete failed',
//                                                   '$e',
//                                                 );
//                                               }
//                                             },
//                                             icon: const Icon(
//                                               Icons.delete_outline,
//                                             ),
//                                             label: const Text('Delete'),
//                                           ),
//                                         ],
//                                       ),
//                                       const SizedBox(height: 10),
//                                       ...items.map((m) {
//                                         final tgt = _s(m['boqCode']).trim();
//                                         final desc =
//                                             _s(m['boqDescription']).trim();
//                                         final f = _num(m['derivedFactor']);
//                                         final off = _num(m['derivedOffset']);
//                                         final unit = _s(m['unit']).trim();
//                                         final v = _num(m['value']);

//                                         return Padding(
//                                           padding: const EdgeInsets.only(
//                                             bottom: 8,
//                                           ),
//                                           child: Row(
//                                             crossAxisAlignment:
//                                                 CrossAxisAlignment.start,
//                                             children: [
//                                               Expanded(
//                                                 child: Text(
//                                                   '$tgt — $desc\n'
//                                                   'rule: (src × ${f.toStringAsFixed(3)}) + ${off.toStringAsFixed(3)}  →  ${v.toStringAsFixed(3)} $unit',
//                                                   style: const TextStyle(
//                                                     fontSize: 12,
//                                                   ),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                         );
//                                       }),
//                                     ],
//                                   ),
//                                 ),
//                               );
//                             },
//                           );
//                         },
//                       ),

//                       // ------------------------------------------------------------
//                       // TAB 2: CREATE NEW LINK
//                       // ------------------------------------------------------------
//                       SingleChildScrollView(
//                         child: Obx(() {
//                           final src = linkedCtrl.source.value;

//                           return Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               _errorBox(),

//                               // SOURCE
//                               Row(
//                                 children: [
//                                   const Expanded(
//                                     child: Text(
//                                       'Source (Measured or BOQ Override)',
//                                       style: TextStyle(
//                                         fontWeight: FontWeight.w800,
//                                       ),
//                                     ),
//                                   ),
//                                   OutlinedButton.icon(
//                                     onPressed: () async {
//                                       linkedCtrl.clearError();
//                                       final picked = await _pickSourceAny(dctx);
//                                       if (picked != null) {
//                                         linkedCtrl.setSource(picked);
//                                       }
//                                     },
//                                     icon: const Icon(Icons.search),
//                                     label: const Text('Pick source'),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   if (src != null)
//                                     OutlinedButton(
//                                       onPressed: () {
//                                         linkedCtrl.clearError();
//                                         linkedCtrl.source.value = null;
//                                       },
//                                       child: const Text('Clear'),
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),

//                               if (src == null)
//                                 const Text(
//                                   'No source selected.',
//                                   style: TextStyle(fontSize: 12),
//                                 )
//                               else
//                                 Card(
//                                   child: Padding(
//                                     padding: const EdgeInsets.all(10),
//                                     child: Column(
//                                       crossAxisAlignment:
//                                           CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           '${src.modeLabel}: ${src.boqCode} — ${src.value.toStringAsFixed(3)} ${src.unit}',
//                                           style: const TextStyle(
//                                             fontWeight: FontWeight.w700,
//                                           ),
//                                         ),
//                                         const SizedBox(height: 6),
//                                         Text(
//                                           src.boqDescription,
//                                           style: const TextStyle(fontSize: 12),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),

//                               const Divider(height: 24),

//                               // TARGETS
//                               Row(
//                                 children: [
//                                   const Expanded(
//                                     child: Text(
//                                       'Targets (BOQ items to receive qty)',
//                                       style: TextStyle(
//                                         fontWeight: FontWeight.w800,
//                                       ),
//                                     ),
//                                   ),
//                                   OutlinedButton.icon(
//                                     onPressed: () async {
//                                       linkedCtrl.clearError();
//                                       try {
//                                         final p = await pickTargetBoq(dctx);
//                                         if (p != null) linkedCtrl.addTarget(p);
//                                       } catch (e) {
//                                         linkedCtrl.setError(
//                                           'Pick target failed:\n$e',
//                                         );
//                                       }
//                                     },
//                                     icon: const Icon(Icons.add_link),
//                                     label: const Text('Add target'),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   if (linkedCtrl.targets.isNotEmpty)
//                                     OutlinedButton(
//                                       onPressed: () {
//                                         linkedCtrl.clearError();
//                                         linkedCtrl.targets.clear();
//                                       },
//                                       child: const Text('Clear'),
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 10),

//                               if (linkedCtrl.targets.isEmpty)
//                                 const Text(
//                                   'No targets yet.',
//                                   style: TextStyle(fontSize: 12),
//                                 )
//                               else
//                                 ...List.generate(linkedCtrl.targets.length, (
//                                   i,
//                                 ) {
//                                   final t = linkedCtrl.targets[i];
//                                   final srcVal = src?.value ?? 0.0;
//                                   final srcUnit = src?.unit ?? '';
//                                   final derived =
//                                       (srcVal * t.factor) + t.offset;

//                                   return Card(
//                                     margin: const EdgeInsets.only(bottom: 10),
//                                     child: Padding(
//                                       padding: const EdgeInsets.all(10),
//                                       child: Column(
//                                         crossAxisAlignment:
//                                             CrossAxisAlignment.start,
//                                         children: [
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: Text(
//                                                   '${t.boq.code} — ${t.boq.description}',
//                                                   maxLines: 2,
//                                                   overflow:
//                                                       TextOverflow.ellipsis,
//                                                   style: const TextStyle(
//                                                     fontWeight: FontWeight.w700,
//                                                   ),
//                                                 ),
//                                               ),
//                                               IconButton(
//                                                 onPressed: () {
//                                                   linkedCtrl.clearError();
//                                                   linkedCtrl.removeTargetAt(i);
//                                                 },
//                                                 icon: const Icon(Icons.close),
//                                               ),
//                                             ],
//                                           ),
//                                           const SizedBox(height: 6),
//                                           Text(
//                                             src == null
//                                                 ? 'Pick a source to preview derived qty.'
//                                                 : 'Derived qty: ${derived.toStringAsFixed(3)} $srcUnit',
//                                             style: const TextStyle(
//                                               fontSize: 12,
//                                               fontWeight: FontWeight.w600,
//                                             ),
//                                           ),
//                                           const SizedBox(height: 8),
//                                           Row(
//                                             children: [
//                                               Expanded(
//                                                 child: TextFormField(
//                                                   initialValue:
//                                                       t.factor.toString(),
//                                                   keyboardType:
//                                                       const TextInputType.numberWithOptions(
//                                                         decimal: true,
//                                                       ),
//                                                   decoration:
//                                                       const InputDecoration(
//                                                         border:
//                                                             OutlineInputBorder(),
//                                                         isDense: true,
//                                                         labelText: 'Factor (×)',
//                                                       ),
//                                                   onChanged:
//                                                       (v) =>
//                                                           linkedCtrl.setFactor(
//                                                             i,
//                                                             _parseNum(v, 1.0),
//                                                           ),
//                                                 ),
//                                               ),
//                                               const SizedBox(width: 8),
//                                               Expanded(
//                                                 child: TextFormField(
//                                                   initialValue:
//                                                       t.offset.toString(),
//                                                   keyboardType:
//                                                       const TextInputType.numberWithOptions(
//                                                         decimal: true,
//                                                       ),
//                                                   decoration:
//                                                       const InputDecoration(
//                                                         border:
//                                                             OutlineInputBorder(),
//                                                         isDense: true,
//                                                         labelText: 'Offset (+)',
//                                                       ),
//                                                   onChanged:
//                                                       (v) =>
//                                                           linkedCtrl.setOffset(
//                                                             i,
//                                                             _parseNum(v, 0.0),
//                                                           ),
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   );
//                                 }),
//                             ],
//                           );
//                         }),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(dctx),
//             child: const Text('Close'),
//           ),
//           Obx(() {
//             final enabled =
//                 linkedCtrl.source.value != null &&
//                 linkedCtrl.targets.isNotEmpty;
//             return FilledButton.icon(
//               onPressed: enabled ? _createLinks : null,
//               icon: const Icon(Icons.link),
//               label: const Text('Create links'),
//             );
//           }),
//         ],
//       );
//     },
//   );
// }
