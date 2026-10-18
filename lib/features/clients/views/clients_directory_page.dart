import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ClientsDirectoryPage extends StatefulWidget {
  const ClientsDirectoryPage({super.key});

  @override
  State<ClientsDirectoryPage> createState() => _ClientsDirectoryPageState();
}

class _ClientsDirectoryPageState extends State<ClientsDirectoryPage> {
  String? _lastSyncSignature;

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _clientKey(String value) {
    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'unknown-client' : cleaned;
  }

  String _projectClient(Map<String, dynamic> data) {
    final name = _s(data['clientName']);
    if (name.isNotEmpty) return name;
    final client = _s(data['client']);
    if (client.isNotEmpty) return client;
    return 'Unassigned client';
  }

  Map<String, _ClientGroup> _groupProjects(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final groups = <String, _ClientGroup>{};
    for (final doc in docs) {
      final data = doc.data();
      final clientName = _projectClient(data);
      final key = _clientKey(clientName);
      final group = groups.putIfAbsent(
        key,
        () => _ClientGroup(id: key, fallbackName: clientName),
      );
      group.projects.add(_ClientProject.fromDoc(doc));
    }
    return groups;
  }

  void _syncClientRecords(List<_ClientGroup> groups) {
    final signature = groups
        .map((group) => '${group.id}:${group.projects.map((p) => p.id).join(',')}')
        .join('|');
    if (signature == _lastSyncSignature) return;
    _lastSyncSignature = signature;

    Future.microtask(() async {
      final batch = FirebaseFirestore.instance.batch();
      final clients = FirebaseFirestore.instance.collection('clients');
      for (final group in groups) {
        final firstProject = group.projects.isEmpty ? null : group.projects.first;
        batch.set(clients.doc(group.id), {
          'sourceClientName': group.fallbackName,
          if (firstProject != null && firstProject.region.trim().isNotEmpty)
            'sourceRegion': firstProject.region.trim(),
          'projectIds': group.projects.map((p) => p.id).toList(),
          'projectNames': group.projects.map((p) => p.name).toList(),
          'createdFromProjects': true,
          'lastSyncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (groups.isNotEmpty) await batch.commit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('projects')
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Clients error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final visibleDocs =
            snap.data!.docs.where((doc) {
              final data = doc.data();
              final ownerId = (data['ownerId'] ?? '').toString();
              final members = (data['members'] as List?) ?? const [];
              return ownerId == uid ||
                  members.map((e) => e.toString()).contains(uid);
            }).toList();

        final groups = _groupProjects(visibleDocs).values.toList()
          ..sort(
            (a, b) => a.fallbackName.toLowerCase().compareTo(
              b.fallbackName.toLowerCase(),
            ),
          );
        _syncClientRecords(groups);

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                compact ? 16 : 22,
                compact ? 16 : 24,
                32,
              ),
              children: [
                _ClientsHero(clientCount: groups.length),
                const SizedBox(height: 18),
                if (groups.isEmpty)
                  const _EmptyClientsState()
                else
                  for (final group in groups) ...[
                    _ClientCard(group: group),
                    const SizedBox(height: 14),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _ClientGroup {
  _ClientGroup({required this.id, required this.fallbackName});

  final String id;
  final String fallbackName;
  final List<_ClientProject> projects = [];
}

class _ClientProject {
  const _ClientProject({
    required this.id,
    required this.name,
    required this.region,
    required this.currency,
  });

  final String id;
  final String name;
  final String region;
  final String currency;

  factory _ClientProject.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _ClientProject(
      id: doc.id,
      name: (data['name'] ?? 'Untitled project').toString(),
      region: (data['region'] ?? '').toString(),
      currency: (data['currency'] ?? 'TZS').toString(),
    );
  }
}

class _ClientsHero extends StatelessWidget {
  const _ClientsHero({required this.clientCount});

  final int clientCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22155EEF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.business_center_outlined,
              color: Color(0xFFD6E4FF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clients directory',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$clientCount clients created from your project register.',
                  style: const TextStyle(color: Color(0xFFD6E4FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.group});

  final _ClientGroup group;

  CollectionReference<Map<String, dynamic>> get _clientsRef =>
      FirebaseFirestore.instance.collection('clients');

  Future<double> _projectCost(_ClientProject project) async {
    final fs = FirebaseFirestore.instance;
    final projectRef = fs.collection('projects').doc(project.id);
    final buildings = await projectRef.collection('buildings').get();
    double total = 0;

    for (final building in buildings.docs) {
      final bRef = building.reference;
      var boqDocs = await bRef.collection('boq').get();
      if (boqDocs.docs.isEmpty) {
        boqDocs = await bRef.collection('boqItems').get();
      }
      final measurements = await bRef.collection('measurements').get();
      total += _buildingBoqAmount(boqDocs.docs, measurements.docs);
    }
    return total;
  }

  String _key(dynamic v) =>
      (v ?? '').toString().trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  String _rowType(dynamic v) {
    final text = (v ?? '').toString().trim().toLowerCase();
    return text.isEmpty ? 'item' : text;
  }

  double _buildingBoqAmount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> boqDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> measurementDocs,
  ) {
    final totalsByBoq = <String, double>{};
    for (final doc in measurementDocs) {
      final data = doc.data();
      final value = _num(data['value']);
      if (value == 0) continue;
      final keys = {
        _key(data['boqCode']),
        _key(data['resolvedBoqCode']),
        _key(data['boqCodeNorm']),
      }..removeWhere((key) => key.isEmpty);
      for (final key in keys) {
        totalsByBoq[key] = (totalsByBoq[key] ?? 0) + value;
      }
    }

    double total = 0;
    for (final doc in boqDocs) {
      final data = doc.data();
      if (_rowType(data['rowType']) != 'item') continue;
      final rate = _num(data['rate']);
      if (rate == 0) continue;

      final rawCode = (data['boqCode'] ?? '').toString();
      final displayCode = (data['displayCode'] ?? '').toString();
      final resolvedCode = (data['resolvedBoqCode'] ?? '').toString();
      final qtyOverride = data['qtyOverride'];
      final qty =
          qtyOverride is num
              ? qtyOverride.toDouble()
              : double.tryParse('${qtyOverride ?? ''}') ??
                  totalsByBoq[_key(resolvedCode)] ??
                  totalsByBoq[_key(displayCode)] ??
                  totalsByBoq[_key(rawCode)] ??
                  0;
      total += qty * rate;
    }
    return total;
  }

  String _money(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _clientsRef.doc(group.id).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final name =
            (data['clientName'] ?? group.fallbackName).toString().trim();
        final location = (data['location'] ?? '').toString().trim();
        final region = (data['region'] ?? '').toString().trim();
        final district = (data['district'] ?? '').toString().trim();
        final representatives =
            ((data['representatives'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AqsColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08101828),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFFEFF4FF),
                      child: Text(
                        name.isEmpty ? 'C' : name[0].toUpperCase(),
                        style: const TextStyle(
                          color: AqsColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Unnamed client' : name,
                            style: const TextStyle(
                              color: AqsColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (location.isNotEmpty) location,
                              if (district.isNotEmpty) district,
                              if (region.isNotEmpty) region,
                              '${group.projects.length} project${group.projects.length == 1 ? '' : 's'}',
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AqsColors.muted),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (_) => _EditClientDialog(
                                  clientId: group.id,
                                  fallbackName: group.fallbackName,
                                  initialData: data,
                                ),
                          ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Update'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (representatives.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final rep in representatives)
                        _RepresentativeChip(rep: rep),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Projects and BOQ value',
                  style: TextStyle(
                    color: AqsColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                for (final project in group.projects)
                  FutureBuilder<double>(
                    future: _projectCost(project),
                    builder: (context, costSnap) {
                      final loading =
                          costSnap.connectionState == ConnectionState.waiting;
                      final cost = costSnap.data ?? 0;
                      return _ClientProjectRow(
                        project: project,
                        costText:
                            loading
                                ? 'Calculating...'
                                : '${project.currency} ${_money(cost)}',
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RepresentativeChip extends StatelessWidget {
  const _RepresentativeChip({required this.rep});

  final Map<String, dynamic> rep;

  @override
  Widget build(BuildContext context) {
    final name = (rep['name'] ?? '').toString();
    final position = (rep['position'] ?? '').toString();
    final phone = (rep['phone'] ?? '').toString();
    final email = (rep['email'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline_rounded, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Representative' : name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                [
                  if (position.isNotEmpty) position,
                  if (phone.isNotEmpty) phone,
                  if (email.isNotEmpty) email,
                ].join(' • '),
                style: const TextStyle(color: AqsColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientProjectRow extends StatelessWidget {
  const _ClientProjectRow({required this.project, required this.costText});

  final _ClientProject project;
  final String costText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap:
          () => Get.toNamed(
            AppRoutes.projectBuildingsPath(project.id, project.name),
          ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, color: AqsColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (project.region.trim().isNotEmpty)
                    Text(
                      project.region,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              costText,
              style: const TextStyle(
                color: AqsColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditClientDialog extends StatefulWidget {
  const _EditClientDialog({
    required this.clientId,
    required this.fallbackName,
    required this.initialData,
  });

  final String clientId;
  final String fallbackName;
  final Map<String, dynamic> initialData;

  @override
  State<_EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<_EditClientDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _regionCtrl;
  late final TextEditingController _districtCtrl;
  final List<_RepControllers> _reps = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text:
          (widget.initialData['clientName'] ?? widget.fallbackName).toString(),
    );
    _locationCtrl = TextEditingController(
      text: (widget.initialData['location'] ?? '').toString(),
    );
    _regionCtrl = TextEditingController(
      text: (widget.initialData['region'] ?? '').toString(),
    );
    _districtCtrl = TextEditingController(
      text: (widget.initialData['district'] ?? '').toString(),
    );

    final reps = (widget.initialData['representatives'] as List?) ?? const [];
    for (final rep in reps.whereType<Map>()) {
      _reps.add(_RepControllers.fromMap(Map<String, dynamic>.from(rep)));
    }
    if (_reps.isEmpty) _reps.add(_RepControllers());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _regionCtrl.dispose();
    _districtCtrl.dispose();
    for (final rep in _reps) {
      rep.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final reps =
        _reps
            .map((rep) => rep.toMap())
            .where((rep) => rep.values.any((v) => v.toString().trim().isNotEmpty))
            .toList();

    try {
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .set({
            'clientName': _nameCtrl.text.trim(),
            'location': _locationCtrl.text.trim(),
            'region': _regionCtrl.text.trim(),
            'district': _districtCtrl.text.trim(),
            'representatives': reps,
            'updatedAt': FieldValue.serverTimestamp(),
            'createdFromProjects': true,
          }, SetOptions(merge: true));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update client details'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Client name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _locationCtrl,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regionCtrl,
                      decoration: const InputDecoration(labelText: 'Region'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _districtCtrl,
                      decoration: const InputDecoration(labelText: 'District'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Client representatives',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        () => setState(() => _reps.add(_RepControllers())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _reps.length; i++) ...[
                _RepresentativeEditor(
                  index: i,
                  rep: _reps[i],
                  onRemove:
                      _reps.length == 1
                          ? null
                          : () => setState(() => _reps.removeAt(i).dispose()),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon:
              _saving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.save_outlined),
          label: const Text('Save client'),
        ),
      ],
    );
  }
}

class _RepresentativeEditor extends StatelessWidget {
  const _RepresentativeEditor({
    required this.index,
    required this.rep,
    required this.onRemove,
  });

  final int index;
  final _RepControllers rep;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Representative ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          TextField(
            controller: rep.name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rep.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: rep.email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: rep.position,
            decoration: const InputDecoration(labelText: 'Position'),
          ),
        ],
      ),
    );
  }
}

class _RepControllers {
  _RepControllers({
    String name = '',
    String phone = '',
    String email = '',
    String position = '',
  }) : name = TextEditingController(text: name),
       phone = TextEditingController(text: phone),
       email = TextEditingController(text: email),
       position = TextEditingController(text: position);

  factory _RepControllers.fromMap(Map<String, dynamic> data) {
    return _RepControllers(
      name: (data['name'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      position: (data['position'] ?? '').toString(),
    );
  }

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController position;

  Map<String, String> toMap() => {
    'name': name.text.trim(),
    'phone': phone.text.trim(),
    'email': email.text.trim(),
    'position': position.text.trim(),
  };

  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    position.dispose();
  }
}

class _EmptyClientsState extends StatelessWidget {
  const _EmptyClientsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.business_outlined, size: 38, color: AqsColors.muted),
          SizedBox(height: 10),
          Text(
            'No clients yet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          SizedBox(height: 4),
          Text(
            'Create projects with client names and they will appear here.',
            style: TextStyle(color: AqsColors.muted),
          ),
        ],
      ),
    );
  }
}
