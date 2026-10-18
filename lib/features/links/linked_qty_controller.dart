// import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/links/links.dart';
import 'package:get/get.dart';
// import 'link_models.dart';

class LinkedAutoSyncController extends GetxController {
  final Rxn<QtySourceDoc> source = Rxn<QtySourceDoc>();
  final targets = <LinkedBoqTarget>[].obs;

  final RxString inlineError = ''.obs;
  void setError(String msg) => inlineError.value = msg.trim();
  void clearError() => inlineError.value = '';
  // void setSource(QtySourceDoc s) => source.value = s;

  // ✅ NEW: show errors inside dialog
  // final RxString inlineError = ''.obs;

  // void setError(String msg) => inlineError.value = msg.trim();
  // void clearError() => inlineError.value = '';

  void clearAll() {
    source.value = null;
    targets.clear();
    clearError();
  }

  void setSource(QtySourceDoc s) {
    source.value = s;
    clearError(); // ✅ clear error on success
  }

  void addTarget(BoqPick pick) {
    final key = pick.id.isNotEmpty ? pick.id : pick.code;
    final exists = targets.any((t) {
      final k = t.boq.id.isNotEmpty ? t.boq.id : t.boq.code;
      return k == key;
    });
    if (exists) return;
    targets.add(LinkedBoqTarget(boq: pick));
  }

  void removeTargetAt(int i) {
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
}
