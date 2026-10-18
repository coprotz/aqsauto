import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BuildUpRateRepository {
  BuildUpRateRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _rates(String uid) =>
      _db.collection('users').doc(uid).collection('build_up_rates');

  Future<List<BuildUpRate>> list(String uid) async {
    final snapshot =
        await _rates(uid).orderBy('updatedAt', descending: true).get();
    return snapshot.docs
        .map((doc) => BuildUpRate.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<BuildUpRate?> get(String uid, String rateId) async {
    final ref = _rates(uid).doc(rateId);
    final results = await Future.wait([
      ref.get(),
      ref.collection('components').orderBy('sortOrder').get(),
    ]);
    final rateDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!rateDoc.exists || rateDoc.data() == null) return null;
    final componentDocs = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final components =
        componentDocs.docs
            .map((doc) => RateComponent.fromMap(doc.data(), doc.id))
            .toList();
    return BuildUpRate.fromMap(
      rateDoc.data()!,
      rateDoc.id,
      components: components,
    );
  }

  Future<String> save(String uid, BuildUpRate rate) async {
    final ref =
        rate.rateId.isEmpty ? _rates(uid).doc() : _rates(uid).doc(rate.rateId);
    final existing = await ref.collection('components').get();
    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    final data = {...rate.toMap(), 'rateId': ref.id};
    if (rate.rateId.isEmpty) data['createdAt'] = FieldValue.serverTimestamp();
    batch.set(ref, data, SetOptions(merge: true));
    for (var i = 0; i < rate.components.length; i++) {
      final component = rate.components[i];
      final componentRef = ref
          .collection('components')
          .doc(component.componentId.isEmpty ? null : component.componentId);
      batch.set(componentRef, {
        ...component.toMap(),
        'componentId': componentRef.id,
        'sortOrder': i,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return ref.id;
  }

  Future<void> delete(String uid, String rateId) async {
    final ref = _rates(uid).doc(rateId);
    final components = await ref.collection('components').get();
    final batch = _db.batch();
    for (final doc in components.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }
}
