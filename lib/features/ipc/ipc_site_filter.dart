import 'package:aqs/core/state/firestore_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class IpcSiteFilter extends StatefulWidget {
  const IpcSiteFilter({super.key, required this.project, required this.enabled, required this.builder});
  final DocumentReference<Map<String, dynamic>> project;
  final bool enabled;
  final Widget Function(bool Function(String) includes, String Function(String) label, Widget? filter) builder;
  @override
  State<IpcSiteFilter> createState() => _IpcSiteFilterState();
}

class _IpcSiteFilterState extends State<IpcSiteFilter> {
  String selected = '*';
  late final sites = widget.project.collection('sites').stateSnapshots();
  late final buildings = widget.project.collection('buildings').stateSnapshots();
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder((_) => true, (_) => 'Project shared costs', null);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: sites, builder: (context, s) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: buildings, builder: (context, b) {
      if (s.hasError || b.hasError) return const Text('Could not load site filter. Reopen the IPC to retry.');
      if (!s.hasData || !b.hasData) return const LinearProgressIndicator();
      final names = {for (final d in s.data!.docs) d.id: '${d.data()['name'] ?? d.id}'};
      final mapping = {for (final d in b.data!.docs) d.id: '${d.data()['siteId'] ?? ''}'};
      String siteFor(String id) => names.containsKey(mapping[id]) ? mapping[id]! : '';
      final current = selected == '*' || selected == '' || names.containsKey(selected) ? selected : '*';
      final filter = SizedBox(width: 300, child: DropdownButtonFormField<String>(
          value: current, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Filter by site', prefixIcon: Icon(Icons.location_on_outlined), border: OutlineInputBorder()),
          items: [const DropdownMenuItem(value: '*', child: Text('All sites')), for (final e in names.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)), const DropdownMenuItem(value: '', child: Text('Unassigned site'))],
          onChanged: (v) => setState(() => selected = v ?? '*'),
        ));
      return widget.builder((id) => current == '*' || siteFor(id) == current, (id) => names[siteFor(id)] ?? 'Unassigned site', filter);
    }));
  }
}
