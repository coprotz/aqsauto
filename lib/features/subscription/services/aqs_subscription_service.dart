import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/aqs_subscription.dart';

class AqsSubscriptionService {
  AqsSubscriptionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<AqsSubscription?> watch(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }

      final data = snapshot.data();

      if (data == null) {
        return null;
      }

      final subscriptionId = (data['subscriptionId'] ?? '').toString().trim();

      if (subscriptionId.isEmpty) {
        return null;
      }

      return AqsSubscription.fromMap(data);
    });
  }

  Future<AqsSubscription?> get(String userId) async {
    final snapshot = await _firestore.collection('users').doc(userId).get();

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    final subscriptionId = (data['subscriptionId'] ?? '').toString().trim();

    if (subscriptionId.isEmpty) {
      return null;
    }

    return AqsSubscription.fromMap(data);
  }
}
