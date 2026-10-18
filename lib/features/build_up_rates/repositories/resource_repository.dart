import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResourceRepository {
  ResourceRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> _resources(String uid) =>
      _db.collection('users').doc(uid).collection('rate_resources');

  Future<List<RateResource>> list(String uid) async =>
      (await _resources(uid).orderBy('name').get()).docs
          .map((doc) => RateResource.fromMap(doc.data(), doc.id))
          .toList();
  Future<void> save(String uid, RateResource resource) async {
    final ref =
        resource.resourceId.isEmpty
            ? _resources(uid).doc()
            : _resources(uid).doc(resource.resourceId);
    await ref.set({
      ...resource.toMap(),
      'resourceId': ref.id,
      if (resource.resourceId.isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String uid, String resourceId) =>
      _resources(uid).doc(resourceId).delete();
}
