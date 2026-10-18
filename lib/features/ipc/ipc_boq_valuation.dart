import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';

/// Mirrors Reports: overrides first, then ID-linked measurements, then unique codes.
Map<String, double> ipcBoqQuantities(
  Map<String, Map<String, dynamic>> rows,
  List<Map<String, dynamic>> measurements,
) {
  String text(dynamic v) => (v ?? '').toString().trim();
  String key(dynamic v) => text(v).replaceAll(RegExp(r'\s+'), '').toLowerCase();
  double number(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  final ids = <String, double>{}, codes = <String, double>{};
  for (final m in measurements) {
    final id = text(m['boqItemId']);
    if (id.isNotEmpty) {
      ids[id] = (ids[id] ?? 0) + number(m['value']);
      continue;
    }
    for (final code in {
      text(m['resolvedBoqCode']),
      text(m['boqCode']),
      text(m['boqCodeNorm']),
    }) {
      if (key(code).isNotEmpty)
        codes[key(code)] = (codes[key(code)] ?? 0) + number(m['value']);
    }
  }
  final aliases = <String, List<String>>{};
  final counts = <String, int>{};
  for (final entry in rows.entries) {
    final row = entry.value;
    final type = text(row['rowType']).toLowerCase();
    if (type.isNotEmpty && type != 'item') continue;
    aliases[entry.key] =
        {
          text(row['resolvedBoqCode']),
          text(row['displayCode']),
          text(row['boqCode']),
          hierarchicalBoqCodeFromRows(row, rows.values.toList()),
        }.where((v) => v.isNotEmpty).toList();
    for (final alias in aliases[entry.key]!.map(key).toSet()) {
      counts[alias] = (counts[alias] ?? 0) + 1;
    }
  }
  return {
    for (final entry in aliases.entries)
      entry.key: () {
        final override = rows[entry.key]!['qtyOverride'];
        final explicit =
            override is num
                ? override.toDouble()
                : double.tryParse('$override');
        if (explicit != null) return explicit;
        if (ids.containsKey(entry.key)) return ids[entry.key]!;
        for (final alias in entry.value) {
          if (counts[key(alias)] == 1 && codes.containsKey(key(alias)))
            return codes[key(alias)]!;
        }
        return 0.0;
      }(),
  };
}

Future<double> snapshotMeasuredBoq(
  DocumentReference<Map<String, dynamic>> building,
  DocumentReference<Map<String, dynamic>> target,
) async {
  var source = await building.collection('boq').get();
  if (source.docs.isEmpty) source = await building.collection('boqItems').get();
  final rows = {for (final doc in source.docs) doc.id: doc.data()};
  final quantities = ipcBoqQuantities(
    rows,
    (await building.collection('measurements').get()).docs
        .map((doc) => doc.data())
        .toList(),
  );
  double total = 0;
  final entries = rows.entries.toList();
  final existing = await target.collection('items').get();
  for (var offset = 0; offset < entries.length; offset += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final entry in entries.skip(offset).take(400)) {
      final qty = quantities[entry.key];
      final rate = double.tryParse('${entry.value['rate']}') ?? 0;
      if (qty != null) total += qty * rate;
      batch.set(target.collection('items').doc(entry.key), {
        ...entry.value,
        if (qty != null) ...{
          'quantity': qty,
          'qtyOverride': qty,
          'amount': qty * rate,
        },
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
  // A refreshed snapshot must not retain items removed from the source BOQ.
  // Only snapshot rows are removed; the project's source BOQ is untouched.
  final obsolete =
      existing.docs.where((doc) => !rows.containsKey(doc.id)).toList();
  for (var offset = 0; offset < obsolete.length; offset += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in obsolete.skip(offset).take(400)) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
  await target.set({
    'contractValue': total,
    'sourcePath': building.path,
    'valuationMethod': 'reports-measured-v1',
    'valuationUpdatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  return total;
}
