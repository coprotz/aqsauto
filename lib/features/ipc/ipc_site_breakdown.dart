import 'package:aqs/core/state/firestore_state.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Map<String, double> allocateIpcSites(double total, Map<String, double> weights) {
  final positive = weights.entries.where((e) => e.value > 0).toList();
  final sum = positive.fold<double>(0, (s, e) => s + e.value);
  if (sum == 0) return {'Unallocated': total};
  final cents = (total * 100).round();
  var remaining = cents;
  return {for (var i = 0; i < positive.length; i++) positive[i].key: () {
    final amount = i == positive.length - 1 ? remaining : (cents * positive[i].value / sum).round();
    remaining -= amount;
    return amount / 100;
  }()};
}

class IpcSiteBreakdownScope extends StatefulWidget {
  const IpcSiteBreakdownScope({super.key, required this.certificate, required this.data, required this.builder});
  final DocumentReference<Map<String, dynamic>> certificate;
  final Map<String, dynamic> data;
  final Widget Function(Map<String, double>? weights) builder;
  @override
  State<IpcSiteBreakdownScope> createState() => _IpcSiteBreakdownScopeState();
}

class _IpcSiteBreakdownScopeState extends State<IpcSiteBreakdownScope> {
  final subscriptions = <StreamSubscription>[];
  final snapshots = <String, QuerySnapshot<Map<String, dynamic>>>{};
  bool failed = false;
  double n(dynamic v) => double.tryParse('$v'.replaceAll(',', '')) ?? 0;
  @override
  void initState() {
    super.initState();
    final project = widget.certificate.parent.parent!;
    for (final entry in {
      'buildings': project.collection('buildings'), 'sites': project.collection('sites'),
      'boqs': widget.certificate.collection('boqs'), 'externalBoqs': widget.certificate.collection('externalBoqs'),
    }.entries) {
      subscriptions.add(entry.value.stateSnapshots().listen((s) {
        if (mounted) setState(() => snapshots[entry.key] = s);
      }, onError: (_) { if (mounted) setState(() => failed = true); }));
    }
  }
  @override
  void dispose() { for (final s in subscriptions) { s.cancel(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (failed || snapshots.length != 4) return widget.builder(null);
    final sites = {for (final d in snapshots['sites']!.docs) d.id: '${d.data()['name'] ?? d.id}'};
    final buildings = {for (final d in snapshots['buildings']!.docs) d.id: d.data()};
    final excluded = List<String>.from(widget.data['excluded'] ?? []);
    final weights = <String, double>{};
    for (final type in ['boqs', 'externalBoqs']) {
      for (final p in snapshots[type]!.docs) {
        if (excluded.contains('${type == 'boqs' ? 'building' : 'external'}:${p.id}')) continue;
        final d = p.data();
        final building = buildings[p.id] ?? <String, dynamic>{};
        final siteId = d['siteId'] ?? (type == 'boqs' ? building['siteId'] : null);
        final label = sites[siteId] ?? (type == 'boqs' ? 'Unassigned site' : 'Project shared costs');
        final gross = n(d['executedAmount']) - n(d['previousExecutedAmount']);
        weights[label] = (weights[label] ?? 0) + gross;
      }
    }
    final difference = n(widget.data['grossWorkValue']) - weights.values.fold<double>(0, (a, b) => a + b);
    if (difference.abs() >= 0.005) weights['Unallocated adjustment'] = difference;
    return widget.builder(weights);
  }
}

class IpcSiteLines extends StatelessWidget {
  const IpcSiteLines({super.key, required this.weights, required this.total, required this.gross});
  final Map<String, double>? weights;
  final double total;
  final bool gross;
  @override
  Widget build(BuildContext context) {
    final values = weights == null ? null : gross ? weights! : allocateIpcSites(total, weights!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
      Text(gross ? 'By site · this period' : 'Allocated by gross-work share', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
      const SizedBox(height: 8),
      if (values == null) const Text('Site breakdown unavailable', style: TextStyle(fontSize: 11, color: Colors.blueGrey))
      else for (final e in values.entries) Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9), decoration: BoxDecoration(color: const Color(0xFFF6F8FC), borderRadius: BorderRadius.circular(8)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(e.key, style: const TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF667085)))),
        const SizedBox(width: 8),
        Expanded(flex: 5, child: Text('TZS ${NumberFormat('#,##0.00').format(e.value)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFF344054)))),
      ])),
    ]);
  }
}
