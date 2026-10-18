import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/models/linked_boq_target.dart';
import 'package:get/get.dart';

class LinkedQtyController extends GetxController {
  final targets = <LinkedBoqTarget>[].obs;

  // Persist between segments if you want (like your lastFoundationDefaults)
  Map<String, dynamic> lastLinkedDefaults = {};

  void clear() => targets.clear();

  void addTarget(BoqPick pick) {
    // avoid duplicates by boqItemId (or code if id empty)
    final key = pick.id.isNotEmpty ? pick.id : pick.code;
    final exists = targets.any((t) {
      final k = t.boq.id.isNotEmpty ? t.boq.id : t.boq.code;
      return k == key;
    });
    if (exists) return;

    targets.add(LinkedBoqTarget(boq: pick));
  }

  void removeAt(int i) {
    if (i < 0 || i >= targets.length) return;
    targets.removeAt(i);
  }

  void setFactor(int i, double v) {
    if (i < 0 || i >= targets.length) return;
    targets[i] = targets[i].copyWith(factor: v);
  }

  void setOffset(int i, double v) {
    if (i < 0 || i >= targets.length) return;
    targets[i] = targets[i].copyWith(offset: v);
  }

  // ---- Persist/restore (optional but recommended for "fast measurement") ----
  Map<String, dynamic> _targetToMap(LinkedBoqTarget t) => {
    'boq': t.boq.toMap(),
    'factor': t.factor,
    'offset': t.offset,
  };

  LinkedBoqTarget? _targetFromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final b = BoqPick.fromMap(m['boq']);
    if (b == null) return null;
    final factor =
        (m['factor'] is num)
            ? (m['factor'] as num).toDouble()
            : double.tryParse('${m['factor']}') ?? 1.0;
    final offset =
        (m['offset'] is num)
            ? (m['offset'] as num).toDouble()
            : double.tryParse('${m['offset']}') ?? 0.0;
    return LinkedBoqTarget(boq: b, factor: factor, offset: offset);
  }

  void restoreFromDefaults(
    Map<String, dynamic> defaults, {
    String key = 'linkedTargets',
  }) {
    final raw = defaults[key];
    if (raw is! List) return;
    final list = <LinkedBoqTarget>[];
    for (final it in raw) {
      final t = _targetFromMap(it);
      if (t != null) list.add(t);
    }
    targets.assignAll(list);
  }

  void saveToDefaults(
    Map<String, dynamic> defaults, {
    String key = 'linkedTargets',
  }) {
    defaults[key] = targets.map(_targetToMap).toList();
  }
}
