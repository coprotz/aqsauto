import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Temporary, no-payment plan activation for the AQS testing period.
/// Replace this service with Stripe checkout when billing is enabled.
class TestingSubscriptionActivationService {
  TestingSubscriptionActivationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const enabled = true;
  static const subscriptionDocumentId = 'testing_access';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> activate(PricingPlan plan, {required bool yearly}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in before choosing a plan.');

    final planId = plan.id.trim().toLowerCase();
    if (planId == 'free') return;

    final limits = switch (planId) {
      'business' => (projects: 100, users: 5),
      'pro' => (projects: 25, users: 3),
      'basic' => (projects: 2, users: 1),
      _ => (projects: 1, users: 1),
    };
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'subscriptionId': 'testing_${user.uid}_$planId',
      'subscriptionStatus': 'active',
      'subscriptionPlanId': planId,
      'subscriptionPlanName': plan.name,
      'subscriptionProductCode': plan.productCodeFor(yearly: yearly),
      'subscriptionBillingCycle': yearly ? 'yearly' : 'monthly',
      'subscriptionAmountPaid': 0,
      'subscriptionCurrency': 'TZS',
      'subscriptionStartedAt': now,
      'subscriptionExpiresAt': Timestamp.fromDate(DateTime.utc(2099, 12, 31)),
      'subscriptionPaymentId': '',
      'subscriptionExternalId': 'aqs-testing-access',
      'projectLimit': limits.projects,
      'userLimit': limits.users,
      'testingAccess': true,
      'paymentRequired': false,
      'updatedAt': now,
    };

    final userRef = _firestore.collection('users').doc(user.uid);
    final batch = _firestore.batch();
    batch.set(userRef, data, SetOptions(merge: true));
    batch.set(
      userRef.collection('subscriptions').doc(subscriptionDocumentId),
      {...data, 'createdAt': now},
      SetOptions(merge: true),
    );
    await batch.commit();
  }
}
