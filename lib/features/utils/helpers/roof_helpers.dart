import 'dart:math' as math;

import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

String roofEdgeTagLabel(RoofEdgeTag t) {
  switch (t) {
    // case RoofEdgeTag.none:
    //   return '—';
    case RoofEdgeTag.eave:
      return 'Eave (Gutter)';
    case RoofEdgeTag.ridge:
      return 'Ridge';
    case RoofEdgeTag.hip:
      return 'Hip';
    case RoofEdgeTag.valley:
      return 'Valley';
    case RoofEdgeTag.barge:
      return 'Barge / Verge';
    // case RoofEdgeTag.other:
    //   return 'Other';
  }
}

// RoofEdgeTag roofEdgeTagFrom(dynamic v) {
//   final s = (v ?? '').toString().toLowerCase().trim();
//   for (final t in RoofEdgeTag.values) {
//     if (t.name.toLowerCase() == s) return t;
//   }
//   return RoofEdgeTag.none;
// }

// double sumTag(List<RoofEdgeTag> tags, List<double> edgeLenM, RoofEdgeTag tag) {
//   double s = 0;
//   for (int i = 0; i < tags.length && i < edgeLenM.length; i++) {
//     if (tags[i] == tag) s += edgeLenM[i];
//   }
//   return s;
// }

RoofEdgeTag roofEdgeTagFrom(dynamic v) {
  final s = (v ?? '').toString().trim().toLowerCase();
  switch (s) {
    case 'eave':
      return RoofEdgeTag.eave;
    case 'ridge':
      return RoofEdgeTag.ridge;
    case 'hip':
      return RoofEdgeTag.hip;
    case 'valley':
      return RoofEdgeTag.valley;
    case 'barge':
    case 'verge':
      return RoofEdgeTag.barge;
    default:
      return RoofEdgeTag.eave;
  }
}

double sumTag(List<RoofEdgeTag> tags, List<double> lens, RoofEdgeTag t) {
  final n = math.min(tags.length, lens.length);
  double s = 0;
  for (int i = 0; i < n; i++) {
    if (tags[i] == t) s += lens[i];
  }
  return s;
}

class BoqMemory {
  static final _box = GetStorage();
  static const _key = 'boq_memory_v1';

  /// key example: "roofing|boqCovering" or "ceilingFinish|branderings50x50"
  static String k(String scope, String itemKey) => '$scope|$itemKey';

  static Map<String, dynamic> _readAll() {
    final raw = _box.read(_key);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static Future<void> _writeAll(Map<String, dynamic> m) async {
    await _box.write(_key, m);
  }

  static Map<String, dynamic>? pickToMap(BoqPick? p) {
    if (p == null) return null;
    return {'id': p.id, 'code': p.code, 'description': p.description};
  }

  static BoqPick? pickFromMap(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final id = (m['id'] ?? '').toString();
    final code = (m['code'] ?? '').toString();
    final desc = (m['description'] ?? '').toString();
    if (id.isEmpty && code.isEmpty && desc.isEmpty) return null;
    return BoqPick(id: id, code: code, description: desc);
  }

  /// Remember ONE pick
  static Future<void> rememberPick({
    required String scope,
    required String itemKey,
    required BoqPick? pick,
  }) async {
    final all = _readAll();
    all[k(scope, itemKey)] = pickToMap(pick);
    await _writeAll(all);
  }

  /// Remember MANY picks at once (use after successful save)
  static Future<void> rememberMany({
    required String scope,
    required Map<String, BoqPick?> picks,
  }) async {
    final all = _readAll();
    picks.forEach((itemKey, pick) {
      all[k(scope, itemKey)] = pickToMap(pick);
    });
    await _writeAll(all);
  }

  /// Read remembered pick
  static BoqPick? recallPick({required String scope, required String itemKey}) {
    final all = _readAll();
    return pickFromMap(all[k(scope, itemKey)]);
  }
}

Future<T?> runWithSaveAlerts<T>({
  required Future<T> Function() action,
  String savingTitle = 'Saving',
  String savingMsg = 'Please wait...',
  String successTitle = 'Saved',
  String successMsg = 'Saved successfully.',
}) async {
  // show blocking progress
  Get.dialog(
    AlertDialog(
      title: Text(savingTitle),
      content: Row(
        children: const [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator()),
          SizedBox(width: 12),
          Expanded(child: Text('Please wait...')),
        ],
      ),
    ),
    barrierDismissible: false,
  );

  try {
    final res = await action();
    if (Get.isDialogOpen == true) Get.back(); // close progress

    // ✅ success alert (dialog or snackbar)
    await Get.dialog(
      AlertDialog(
        title: Text(successTitle),
        content: Text(successMsg),
        actions: [
          FilledButton(onPressed: () => Get.back(), child: const Text('OK')),
        ],
      ),
      barrierDismissible: true,
    );

    return res;
  } catch (e, st) {
    if (Get.isDialogOpen == true) Get.back(); // close progress

    // ❌ error alert
    await Get.dialog(
      AlertDialog(
        title: const Text('Save failed'),
        content: SingleChildScrollView(child: Text('$e\n\n$st')),
        actions: [
          FilledButton(onPressed: () => Get.back(), child: const Text('OK')),
        ],
      ),
      barrierDismissible: true,
    );
    return null;
  }
}

Future<void> alert(String title, String msg) async {
  await Get.dialog(
    AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(msg)),
      actions: [FilledButton(onPressed: Get.back, child: const Text('OK'))],
    ),
    barrierDismissible: true,
  );
}

class DraftPath {
  final List<Offset> pts;
  final bool closed;
  const DraftPath({required this.pts, required this.closed});

  DraftPath copyWith({List<Offset>? pts, bool? closed}) =>
      DraftPath(pts: pts ?? this.pts, closed: closed ?? this.closed);
}
