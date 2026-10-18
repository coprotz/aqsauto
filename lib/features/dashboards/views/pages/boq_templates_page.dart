import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TemplatesPage extends StatefulWidget {
  final String projectId;
  const TemplatesPage({super.key, required this.projectId});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  final _tab = ValueNotifier<int>(0); // 0=Default, 1=My Templates
  final _search = TextEditingController();

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get globalTemplates =>
      FirebaseFirestore.instance.collection('boq_templates');

  CollectionReference<Map<String, dynamic>> userTemplates() => FirebaseFirestore
      .instance
      .collection('projects')
      .doc(widget.projectId)
      .collection('boq_templates');

  Stream<QuerySnapshot<Map<String, dynamic>>> _templatesStream(bool mine) {
    final q =
        mine
            ? userTemplates().orderBy('createdAt', descending: true)
            : globalTemplates.orderBy('createdAt', descending: true);

    return q.snapshots();
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<int> _countItems({
    required bool mine,
    required String templateId,
  }) async {
    final itemsRef =
        mine
            ? userTemplates().doc(templateId).collection('items')
            : globalTemplates.doc(templateId).collection('items');

    try {
      final agg = await itemsRef.count().get();
      return agg.count ?? 0; // ✅ fix int? -> int
    } catch (_) {
      final snap = await itemsRef.limit(5000).get();
      return snap.docs.length;
    }
  }

  Future<void> _createNewTemplate() async {
    final name = await _promptText(
      title: 'New template',
      hint: 'Template name',
    );
    if (name == null || name.trim().isEmpty) return;

    await userTemplates().add({
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'visibility': 'private',
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Template created')));
      _tab.value = 1; // jump to My Templates
    }
  }

  Future<void> _renameTemplate(String templateId) async {
    final name = await _promptText(
      title: 'Rename template',
      hint: 'Template name',
    );
    if (name == null || name.trim().isEmpty) return;

    await userTemplates().doc(templateId).update({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Renamed')));
    }
  }

  Future<void> _deleteTemplate(String templateId) async {
    final ok = await _confirm(
      'Delete template?',
      'This will remove the template and all its items.',
    );
    if (ok != true) return;

    // Delete items in batch (basic approach)
    final itemsRef = userTemplates().doc(templateId).collection('items');
    final items = await itemsRef.get();

    final batch = FirebaseFirestore.instance.batch();
    for (final d in items.docs) {
      batch.delete(d.reference);
    }
    batch.delete(userTemplates().doc(templateId));
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted')));
    }
  }

  Future<void> _copyGlobalToMine({
    required String globalTemplateId,
    required String globalName,
  }) async {
    // Create my template
    final myDoc = await userTemplates().add({
      'name': '$globalName (copy)',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'sourceTemplateId': globalTemplateId,
      'visibility': 'private',
    });

    // Copy items
    final srcItems =
        await globalTemplates.doc(globalTemplateId).collection('items').get();
    final batch = FirebaseFirestore.instance.batch();

    for (final it in srcItems.docs) {
      batch.set(myDoc.collection('items').doc(), it.data());
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to My Templates')));
      _tab.value = 1;
    }
  }

  Future<void> _openTemplate({
    required bool mine,
    required String templateId,
    required String name,
  }) async {
    // For now, navigate to a template detail page (preview/edit items).
    // Replace with your own route.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => BoqTemplateDetailPage(
              mine: mine,
              templateId: templateId,
              templateName: name,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BOQ Templates'),
        actions: [
          IconButton(
            tooltip: 'New Template',
            onPressed: _createNewTemplate,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search + toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search templates...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                ValueListenableBuilder<int>(
                  valueListenable: _tab,
                  builder: (context, t, _) {
                    return SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Default')),
                        ButtonSegment(value: 1, label: Text('My Templates')),
                      ],
                      selected: {t},
                      onSelectionChanged: (s) => _tab.value = s.first,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // List
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _tab,
              builder: (context, t, _) {
                final mine = t == 1;
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _templatesStream(mine),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snap.error}',
                          style: TextStyle(color: cs.error),
                        ),
                      );
                    }

                    final docs = snap.data?.docs ?? const [];
                    final q = _search.text.trim().toLowerCase();

                    final filtered =
                        q.isEmpty
                            ? docs
                            : docs.where((d) {
                              final name =
                                  (d.data()['name'] ?? '')
                                      .toString()
                                      .toLowerCase();
                              return name.contains(q);
                            }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          mine
                              ? 'No personal templates yet.'
                              : 'No default templates found.',
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = filtered[i];
                        final data = d.data();
                        final name = (data['name'] ?? 'Template').toString();
                        final createdAt =
                            (data['createdAt'] as Timestamp?)?.toDate();

                        return Card(
                          elevation: 1,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  mine
                                      ? cs.primaryContainer
                                      : cs.secondaryContainer,
                              child: Icon(
                                mine ? Icons.person : Icons.public,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: FutureBuilder<int>(
                              future: _countItems(mine: mine, templateId: d.id),
                              builder: (context, cSnap) {
                                final count = cSnap.data;
                                final dateText =
                                    createdAt == null
                                        ? ''
                                        : '${createdAt.day.toString().padLeft(2, '0')}-'
                                            '${createdAt.month.toString().padLeft(2, '0')}-'
                                            '${createdAt.year}';
                                return Text(
                                  '${count == null ? '…' : '$count'} items'
                                  '${dateText.isEmpty ? '' : ' • $dateText'}',
                                );
                              },
                            ),
                            onTap:
                                () => _openTemplate(
                                  mine: mine,
                                  templateId: d.id,
                                  name: name,
                                ),
                            trailing:
                                mine
                                    ? PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'open') {
                                          await _openTemplate(
                                            mine: true,
                                            templateId: d.id,
                                            name: name,
                                          );
                                        } else if (v == 'rename') {
                                          await _renameTemplate(d.id);
                                        } else if (v == 'delete') {
                                          await _deleteTemplate(d.id);
                                        } else if (v == 'duplicate') {
                                          await _copyMyToMy(d.id, name);
                                        }
                                      },
                                      itemBuilder:
                                          (_) => const [
                                            PopupMenuItem(
                                              value: 'open',
                                              child: Text('Open'),
                                            ),
                                            PopupMenuItem(
                                              value: 'rename',
                                              child: Text('Rename'),
                                            ),
                                            PopupMenuItem(
                                              value: 'duplicate',
                                              child: Text('Duplicate'),
                                            ),
                                            PopupMenuDivider(),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete'),
                                            ),
                                          ],
                                    )
                                    : PopupMenuButton<String>(
                                      onSelected: (v) async {
                                        if (v == 'open') {
                                          await _openTemplate(
                                            mine: false,
                                            templateId: d.id,
                                            name: name,
                                          );
                                        } else if (v == 'copy') {
                                          await _copyGlobalToMine(
                                            globalTemplateId: d.id,
                                            globalName: name,
                                          );
                                        }
                                      },
                                      itemBuilder:
                                          (_) => const [
                                            PopupMenuItem(
                                              value: 'open',
                                              child: Text('Preview'),
                                            ),
                                            PopupMenuItem(
                                              value: 'copy',
                                              child: Text(
                                                'Copy to My Templates',
                                              ),
                                            ),
                                          ],
                                    ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewTemplate,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
    );
  }

  Future<void> _copyMyToMy(String templateId, String name) async {
    final src = userTemplates().doc(templateId);
    final srcDoc = await src.get();
    final srcData = srcDoc.data();
    if (srcData == null) return;

    final myDoc = await userTemplates().add({
      'name': '$name (copy)',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'sourceTemplateId': templateId,
      'visibility': 'private',
    });

    final srcItems = await src.collection('items').get();
    final batch = FirebaseFirestore.instance.batch();
    for (final it in srcItems.docs) {
      batch.set(myDoc.collection('items').doc(), it.data());
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Duplicated')));
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
  }) async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: c,
              decoration: InputDecoration(hintText: hint),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, c.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    c.dispose();
    return res;
  }

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
    );
  }
}

/// DETAIL PAGE: preview + edit items (basic shell)
class BoqTemplateDetailPage extends StatelessWidget {
  final bool mine;
  final String templateId;
  final String templateName;

  const BoqTemplateDetailPage({
    super.key,
    required this.mine,
    required this.templateId,
    required this.templateName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(templateName)),
      body: Center(
        child: Text(mine ? 'Edit items here' : 'Preview only (copy to edit)'),
      ),
    );
  }
}
