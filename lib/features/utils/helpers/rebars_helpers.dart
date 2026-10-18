// ✅ remembers BOQ for a "rebar signature"
import 'package:aqs/features/utils/helpers/helpers.dart';

String rebarKey({
  required int diaMm,
  required double spacingMm,
  required String direction,
  required String position,
}) {
  // normalize spacing (avoid 149.999 vs 150)
  final sp = spacingMm.round(); // mm
  final dir = (direction == 'alongB') ? 'alongB' : 'alongL';
  final pos = (position == 'top' || position == 'center') ? position : 'bottom';
  return '${diaMm}Y@${sp}|$dir|$pos';
}

// Load remembered map from lastSlabDefaults
final Map<String, Map<String, String>> rebarBoqByKey =
    (() {
      final raw = lastSlabDefaults['rebarBoqByKey'];
      if (raw is Map) {
        final out = <String, Map<String, String>>{};
        raw.forEach((k, v) {
          if (k == null) return;
          if (v is Map) {
            out['$k'] = {
              'code': (v['code'] ?? '').toString(),
              'desc': (v['desc'] ?? '').toString(),
            };
          }
        });
        return out;
      }
      return <String, Map<String, String>>{};
    })();

// ✅ cache picked BOQs per line id so UI never loses them
final Map<String, Map<String, String>> rebarBoqCache = {}; // id -> {code, desc}
