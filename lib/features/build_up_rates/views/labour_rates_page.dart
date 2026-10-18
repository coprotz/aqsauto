import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Labour wage library and productivity-based labour-only rate analyses.
/// Stored under the same user scope as existing AQS rate resources.
class LabourRatesPage extends StatefulWidget {
  const LabourRatesPage({super.key});
  @override
  State<LabourRatesPage> createState() => _LabourRatesPageState();
}

class _LabourRatesPageState extends State<LabourRatesPage> {
  final _money = NumberFormat('#,##0.00');
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'm²');
  final _output = TextEditingController(text: '10');
  final _allowance = TextEditingController(text: '0');
  final _markup = TextEditingController(text: '0');
  final List<_CrewLine> _crew = [];
  bool _saving = false;
  String? _editingId;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection(name);
  double _number(String value) => double.tryParse(value.trim()) ?? 0;
  double get _dailyCost => _crew.fold<double>(0.0, (total, line) => total + line.quantity * line.dailyRate);
  double get _directRate => _number(_output.text) > 0 ? _dailyCost / _number(_output.text) : 0;
  double get _allowanceCost => _directRate * _number(_allowance.text) / 100;
  double get _overheadProfit => (_directRate + _allowanceCost) * _number(_markup.text) / 100;
  double get _unitRate => _directRate + _allowanceCost + _overheadProfit;

  @override
  void dispose() {
    for (final c in [_name, _unit, _output, _allowance, _markup]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _editWage([QueryDocumentSnapshot<Map<String, dynamic>>? existing]) async {
    final data = existing?.data() ?? <String, dynamic>{};
    final name = TextEditingController(text: '${data['name'] ?? ''}');
    final daily = TextEditingController(text: '${data['dailyRate'] ?? ''}');
    final location = TextEditingController(text: '${data['location'] ?? ''}');
    final source = TextEditingController(text: '${data['source'] ?? ''}');
    final hours = TextEditingController(text: '${data['hoursPerDay'] ?? 8}');
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(existing == null ? 'Add labour wage' : 'Edit labour wage'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Labour category / trade *')),
        TextField(controller: daily, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Daily wage (TZS) *')),
        TextField(controller: hours, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Working hours per day')),
        TextField(controller: location, decoration: const InputDecoration(labelText: 'Location / region')),
        TextField(controller: source, decoration: const InputDecoration(labelText: 'Rate source / remarks')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (name.text.trim().isEmpty || _number(daily.text) <= 0 || _number(hours.text) <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a trade, positive daily wage and working hours.'))); return;
          }
          Navigator.pop(context, true);
        }, child: const Text('Save'))],
    ));
    if (result == true && _uid != null) {
      try {
        final ref = existing == null ? _collection('labour_rates').doc() : existing.reference;
        await ref.set({'name': name.text.trim(), 'dailyRate': _number(daily.text),
          'hoursPerDay': _number(hours.text), 'location': location.text.trim(),
          'source': source.text.trim(), 'currency': 'TZS', 'updatedAt': FieldValue.serverTimestamp(),
          if (existing == null) 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } catch (e) { _error(e); }
    }
    name.dispose(); daily.dispose(); hours.dispose(); location.dispose(); source.dispose();
  }

  void _error(Object e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Operation failed: $e'))); }
  Future<void> _addCrewLine(List<QueryDocumentSnapshot<Map<String, dynamic>>> wages) async {
    if (wages.isEmpty) { _error('Add a labour wage in the Library first.'); return; }
    String wageId = wages.first.id;
    final qty = TextEditingController(text: '1');
    final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
      title: const Text('Add labour to gang'), content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: wageId, isExpanded: true, decoration: const InputDecoration(labelText: 'Trade'), items: wages.map((w) => DropdownMenuItem(value: w.id, child: Text('${w.data()['name']} — TZS ${_money.format(w.data()['dailyRate'])}/day', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) { if(value != null) refresh(() => wageId = value); }),
        TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Number of workers')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (_number(qty.text) <= 0) return; Navigator.pop(context, true); }, child: const Text('Add'))],
    )));
    if (accepted == true) {
      final wage = wages.firstWhere((w) => w.id == wageId);
      setState(() => _crew.add(_CrewLine(wageId: wage.id, trade: '${wage.data()['name']}', quantity: _number(qty.text), dailyRate: (wage.data()['dailyRate'] as num).toDouble())));
    }
    qty.dispose();
  }

  Future<void> _saveBuildUp() async {
    if (_uid == null) { _error('Please sign in.'); return; }
    if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty || _crew.isEmpty || _number(_output.text) <= 0 || _number(_allowance.text) < 0 || _number(_markup.text) < 0) {
      _error('Enter activity name, unit, positive daily output, crew and valid percentages.'); return;
    }
    setState(() => _saving = true);
    try {
      final ref = _editingId == null ? _collection('labour_build_ups').doc() : _collection('labour_build_ups').doc(_editingId);
      await ref.set({'name': _name.text.trim(), 'unit': _unit.text.trim(), 'dailyOutput': _number(_output.text),
        'allowancePercent': _number(_allowance.text), 'overheadProfitPercent': _number(_markup.text),
        'dailyGangCost': _dailyCost, 'directUnitRate': _directRate, 'finalUnitRate': _unitRate,
        'currency': 'TZS', 'rateType': 'labour_only', 'revisionNote': 'Saved labour rate snapshot',
        'crew': _crew.map((line) => line.toMap()).toList(), 'updatedAt': FieldValue.serverTimestamp(),
        if (_editingId == null) 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      _editingId = ref.id;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Labour-only rate saved.')));
    } catch(e) { _error(e); } finally { if(mounted) setState(() => _saving = false); }
  }

  void _loadBuildUp(QueryDocumentSnapshot<Map<String,dynamic>> doc) {
    final d = doc.data();
    setState(() {
      _editingId = doc.id; _name.text = '${d['name'] ?? ''}'; _unit.text = '${d['unit'] ?? 'm²'}';
      _output.text = '${d['dailyOutput'] ?? 10}'; _allowance.text = '${d['allowancePercent'] ?? 0}'; _markup.text = '${d['overheadProfitPercent'] ?? 0}';
      _crew..clear()..addAll(((d['crew'] as List?) ?? []).whereType<Map>().map((item) => _CrewLine.fromMap(Map<String,dynamic>.from(item))));
    });
  }

  Widget _field(TextEditingController controller, String label, {bool numeric = true}) => TextField(
    controller: controller, onChanged: (_) => setState(() {}), keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const Scaffold(body: Center(child: Text('Sign in to manage labour rates.')));
    return Scaffold(appBar: AppBar(title: const Text('Labour Rates & Labour-Only Build-Up')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _collection('labour_rates').orderBy('name').snapshots(), builder: (context, wageSnapshot) {
        if (wageSnapshot.hasError) return Center(child: Text('Cannot load labour rates: ${wageSnapshot.error}'));
        final wages = wageSnapshot.data?.docs ?? [];
        return DefaultTabController(length: 2, child: Column(children: [
          const TabBar(tabs: [Tab(icon: Icon(Icons.people_outline), text: 'Labour Library'), Tab(icon: Icon(Icons.calculate_outlined), text: 'Labour-Only Build-Up')]),
          Expanded(child: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(20), children: [
              Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Trade wages', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                FilledButton.icon(onPressed: () => _editWage(), icon: const Icon(Icons.add), label: const Text('Add wage')),
              ]), const SizedBox(height: 12),
              const Text('Wages are entered per day. Hourly cost is calculated from working hours. Rates are snapshots when added to a build-up.'),
              if (!wageSnapshot.hasData) const LinearProgressIndicator(),
              ...wages.map((w) { final d=w.data(); final daily = (d['dailyRate'] as num?)?.toDouble() ?? 0; final hours=(d['hoursPerDay'] as num?)?.toDouble() ?? 8;
                return Card(child: ListTile(title: Text('${d['name']}'), subtitle: Text('${d['location'] ?? ''} • ${d['source'] ?? ''}'),
                  trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                    Text('TZS ${_money.format(daily)}/day\nTZS ${_money.format(hours>0?daily/hours:0)}/hr', textAlign: TextAlign.end),
                    IconButton(tooltip: 'Edit', onPressed: () => _editWage(w), icon: const Icon(Icons.edit_outlined)),
                    IconButton(tooltip: 'Delete', onPressed: () async { try { await w.reference.delete(); } catch(e) { _error(e); } }, icon: const Icon(Icons.delete_outline)),
                  ])));
              }),
            ]),
            ListView(padding: const EdgeInsets.all(20), children: [
              const Text('Productivity-based labour rate analysis', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 340, child: _field(_name, 'Activity / BOQ description', numeric: false)),
                SizedBox(width: 130, child: _field(_unit, 'Output unit', numeric: false)),
                SizedBox(width: 200, child: _field(_output, 'Gang daily output')),
              ]), const SizedBox(height: 18),
              Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Labour gang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                OutlinedButton.icon(onPressed: () => _addCrewLine(wages), icon: const Icon(Icons.person_add_alt), label: const Text('Add gang member')),
              ]),
              ..._crew.asMap().entries.map((entry) => Card(child: ListTile(title: Text(entry.value.trade),
                subtitle: Text('${entry.value.quantity} workers × TZS ${_money.format(entry.value.dailyRate)}/day'),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [Text('TZS ${_money.format(entry.value.quantity*entry.value.dailyRate)}'), IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _crew.removeAt(entry.key)))])))),
              if (_crew.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Add workers from your Labour Library.')),
              const SizedBox(height: 12), Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 210, child: _field(_allowance, 'Labour allowance (%)')),
                SizedBox(width: 210, child: _field(_markup, 'Overheads & profit (%)')),
              ]), const SizedBox(height: 16),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Daily gang cost: TZS ${_money.format(_dailyCost)}'),
                Text('Direct labour rate: TZS ${_money.format(_directRate)}/${_unit.text}'),
                Text('Labour allowance: TZS ${_money.format(_allowanceCost)}/${_unit.text}'),
                Text('Overhead & profit: TZS ${_money.format(_overheadProfit)}/${_unit.text}'),
                const Divider(), Text('LABOUR-ONLY RATE: TZS ${_money.format(_unitRate)}/${_unit.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const Text('Materials and plant excluded. O/H & profit applies after labour allowance.'),
              ]))), const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                FilledButton.icon(onPressed: _saving ? null : _saveBuildUp, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save build-up')),
                TextButton.icon(onPressed: () => setState(() { _editingId = null; _name.clear(); _crew.clear(); _output.text='10'; _allowance.text='0'; _markup.text='0'; }), icon: const Icon(Icons.add), label: const Text('New analysis')),
              ]), const Divider(height: 36),
              const Text('Saved labour-only analyses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: _collection('labour_build_ups').snapshots(), builder: (context, snapshot) {
                if(snapshot.hasError) return Text('Cannot load analyses: ${snapshot.error}');
                if(!snapshot.hasData) return const LinearProgressIndicator();
                final docs=snapshot.data!.docs.toList()..sort((a,b)=>'${a.data()['name']}'.compareTo('${b.data()['name']}'));
                return Column(children: docs.map((doc) => ListTile(title: Text('${doc.data()['name']}'),
                  subtitle: Text('TZS ${_money.format(doc.data()['finalUnitRate'] ?? 0)}/${doc.data()['unit'] ?? ''}'),
                  onTap: () => _loadBuildUp(doc), trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () async { try { await doc.reference.delete(); if(_editingId==doc.id) setState(()=>_editingId=null); } catch(e){ _error(e); } }))).toList());
              }),
            ]),
          ])),
        ]));
      }));
  }
}

class _CrewLine {
  const _CrewLine({required this.wageId, required this.trade, required this.quantity, required this.dailyRate});
  final String wageId;
  final String trade;
  final double quantity;
  final double dailyRate;
  Map<String, dynamic> toMap() => {'wageId': wageId, 'trade': trade, 'quantity': quantity, 'dailyRate': dailyRate};
  factory _CrewLine.fromMap(Map<String,dynamic> data) => _CrewLine(wageId: '${data['wageId'] ?? ''}', trade: '${data['trade'] ?? ''}', quantity: (data['quantity'] as num?)?.toDouble() ?? 0, dailyRate: (data['dailyRate'] as num?)?.toDouble() ?? 0);
}
