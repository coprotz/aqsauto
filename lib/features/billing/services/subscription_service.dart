import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AqsPlan { free, basic, pro, business }

enum AqsBillingCycle { none, monthly, yearly }

class AqsSubscription {
  const AqsSubscription({
    required this.plan,
    required this.status,
    required this.productCode,
    required this.billingCycle,
    required this.planName,
    required this.projectLimit,
    required this.userLimit,
    required this.allowedFreeTools,
    this.subscriptionId,
    this.amountPaid,
    this.currency = 'TZS',
    this.startedAt,
    this.expiresAt,
    this.paymentId,
    this.externalId,
  });

  final AqsPlan plan;

  final String status;
  final String productCode;
  final String planName;

  final AqsBillingCycle billingCycle;

  final int projectLimit;
  final int userLimit;

  final Set<String> allowedFreeTools;

  final String? subscriptionId;

  final double? amountPaid;
  final String currency;

  final DateTime? startedAt;
  final DateTime? expiresAt;

  final String? paymentId;
  final String? externalId;

  bool get isFree => plan == AqsPlan.free;

  bool get isBasic => plan == AqsPlan.basic;

  bool get isPro => plan == AqsPlan.pro;

  bool get isBusiness => plan == AqsPlan.business;

  bool get isMonthly => billingCycle == AqsBillingCycle.monthly;

  bool get isYearly => billingCycle == AqsBillingCycle.yearly;

  bool get isExpired {
    if (expiresAt == null) {
      return false;
    }

    return !expiresAt!.isAfter(DateTime.now());
  }

  bool get isActivePaid {
    if (isFree) {
      return false;
    }

    if (isExpired) {
      return false;
    }

    final normalized = status.trim().toLowerCase();

    return normalized == 'active' ||
        normalized == 'successful' ||
        normalized == 'completed';
  }

  bool get hasBasicAccess {
    return isActivePaid &&
        (plan == AqsPlan.basic ||
            plan == AqsPlan.pro ||
            plan == AqsPlan.business);
  }

  bool get hasProAccess {
    return isActivePaid && (plan == AqsPlan.pro || plan == AqsPlan.business);
  }

  bool get hasBusinessAccess {
    return isActivePaid && plan == AqsPlan.business;
  }

  String get displayName {
    switch (plan) {
      case AqsPlan.free:
        return 'Free';

      case AqsPlan.basic:
        return 'Basic';

      case AqsPlan.pro:
        return 'Pro';

      case AqsPlan.business:
        return 'Business';
    }
  }

  String get billingCycleLabel {
    switch (billingCycle) {
      case AqsBillingCycle.monthly:
        return 'Monthly';

      case AqsBillingCycle.yearly:
        return 'Yearly';

      case AqsBillingCycle.none:
        return '';
    }
  }

  bool canUseTool({required String measureType, String? label}) {
    if (isActivePaid) {
      return true;
    }

    final key = SubscriptionService.toolKey(measureType, label);

    return allowedFreeTools.contains(key);
  }

  static const free = AqsSubscription(
    plan: AqsPlan.free,
    status: 'free',
    productCode: '',
    billingCycle: AqsBillingCycle.none,
    planName: 'Free',
    projectLimit: 1,
    userLimit: 1,
    allowedFreeTools: {
      'area',
      'foundationwall',
      'walling:walling',
      'walling:wall 150 mm',
    },
  );
}

class SubscriptionService {
  const SubscriptionService._();

  static const instance = SubscriptionService._();

  static String toolKey(String measureType, String? label) {
    final type = measureType.trim().toLowerCase();

    final cleanLabel = (label ?? '').trim().toLowerCase();

    if (type == 'walling') {
      return '$type:$cleanLabel';
    }

    return type;
  }

  /// One-time subscription read.
  Future<AqsSubscription> currentSubscription({User? user}) async {
    final resolvedUser = user ?? FirebaseAuth.instance.currentUser;

    if (resolvedUser == null) {
      return AqsSubscription.free;
    }

    try {
      final subcollectionSubscription = await _currentSubcollectionSubscription(
        resolvedUser.uid,
      );

      if (subcollectionSubscription.isActivePaid) {
        return subcollectionSubscription;
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(resolvedUser.uid)
              .get();

      return _subscriptionFromData(doc.data());
    } catch (error) {
      return AqsSubscription.free;
    }
  }

  /// Live subscription stream.
  ///
  /// This should be used by:
  /// - dashboard
  /// - welcome banner
  /// - pricing page
  /// - account/profile page
  ///
  /// When QuickLipa activates a subscription,
  /// users/{uid}/subscriptions changes and the UI updates automatically.
  Stream<AqsSubscription> watchSubscription({User? user}) {
    final resolvedUser = user ?? FirebaseAuth.instance.currentUser;

    if (resolvedUser == null) {
      return Stream.value(AqsSubscription.free);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(resolvedUser.uid)
        .collection('subscriptions')
        .snapshots()
        .asyncMap((snapshot) async {
          final subcollectionSubscription = _bestSubscriptionFromDocs(
            snapshot.docs,
          );

          if (subcollectionSubscription.isActivePaid) {
            return subcollectionSubscription;
          }

          final userDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(resolvedUser.uid)
                  .get();

          return _subscriptionFromData(userDoc.data());
        });
  }

  Future<bool> canUseMeasurementTool({
    required String measureType,
    String? label,
    User? user,
  }) async {
    final subscription = await currentSubscription(user: user);

    return subscription.canUseTool(measureType: measureType, label: label);
  }

  Future<bool> canCreateProject({User? user}) async {
    final resolvedUser = user ?? FirebaseAuth.instance.currentUser;

    if (resolvedUser == null) {
      return false;
    }

    final subscription = await currentSubscription(user: resolvedUser);

    /*
     * Paid plans still have project limits.
     *
     * Free       = 1
     * Basic      = 2
     * Pro        = 25
     * Business   = 100
     */
    final snap =
        await FirebaseFirestore.instance
            .collection('projects')
            .where('ownerId', isEqualTo: resolvedUser.uid)
            .get();

    return snap.docs.length < subscription.projectLimit;
  }

  Future<bool> canInviteTeamMember({User? user}) async {
    final subscription = await currentSubscription(user: user);

    /*
     * Only Business currently supports
     * more than one user.
     */
    return subscription.isActivePaid && subscription.userLimit > 1;
  }

  Future<bool> hasBasicAccess({User? user}) async {
    final subscription = await currentSubscription(user: user);

    return subscription.hasBasicAccess;
  }

  Future<bool> hasProAccess({User? user}) async {
    final subscription = await currentSubscription(user: user);

    return subscription.hasProAccess;
  }

  Future<bool> hasBusinessAccess({User? user}) async {
    final subscription = await currentSubscription(user: user);

    return subscription.hasBusinessAccess;
  }

  static AqsSubscription _subscriptionFromData(Map<String, dynamic>? data) {
    if (data == null) {
      return AqsSubscription.free;
    }

    final status =
        _firstText(data, ['subscriptionStatus', 'status']).toLowerCase();

    final planId =
        _firstText(data, ['subscriptionPlanId', 'planId']).toLowerCase();

    final planName = _firstText(data, ['subscriptionPlanName', 'planName']);

    final productCode =
        _firstText(data, [
          'subscriptionProductCode',
          'productCode',
        ]).toUpperCase();

    final billingCycleText =
        _firstText(data, [
          'subscriptionBillingCycle',
          'billingCycle',
        ]).toLowerCase();

    final plan = _planFromString(planId.isNotEmpty ? planId : productCode);

    /*
     * No valid paid plan.
     */
    if (plan == AqsPlan.free) {
      return AqsSubscription.free;
    }

    final expiresAt = _readDate(
      data['subscriptionExpiresAt'] ?? data['expiresAt'],
    );

    /*
     * Treat inactive or expired subscription
     * as Free access.
     */
    if (!_statusIsActive(status)) {
      return AqsSubscription.free;
    }

    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      return AqsSubscription.free;
    }

    final billingCycle = _billingCycleFromString(
      billingCycleText.isNotEmpty ? billingCycleText : productCode,
    );

    return AqsSubscription(
      plan: plan,

      status: status,

      productCode: productCode,

      billingCycle: billingCycle,

      planName: planName.isNotEmpty ? planName : _planDisplayName(plan),

      projectLimit: _readInt(data['projectLimit']) ?? _projectLimit(plan),

      userLimit: _readInt(data['userLimit']) ?? _userLimit(plan),

      allowedFreeTools: AqsSubscription.free.allowedFreeTools,

      subscriptionId: _nullableText(data['subscriptionId']),

      amountPaid: _readDouble(
        data['subscriptionAmountPaid'] ?? data['amountPaid'],
      ),

      currency:
          _firstText(data, ['subscriptionCurrency', 'currency']).isNotEmpty
              ? _firstText(data, ['subscriptionCurrency', 'currency'])
              : 'TZS',

      startedAt: _readDate(data['subscriptionStartedAt'] ?? data['startedAt']),

      expiresAt: expiresAt,

      paymentId: _nullableText(
        data['subscriptionPaymentId'] ?? data['paymentId'],
      ),

      externalId: _nullableText(
        data['subscriptionExternalId'] ?? data['externalId'],
      ),
    );
  }

  static Future<AqsSubscription> _currentSubcollectionSubscription(
    String uid,
  ) async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('subscriptions')
            .get();

    return _bestSubscriptionFromDocs(snapshot.docs);
  }

  static AqsSubscription _bestSubscriptionFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final subscriptions =
        docs
            .map((doc) {
              final data = <String, dynamic>{...doc.data()};
              data['subscriptionId'] ??= doc.id;
              return _subscriptionFromData(data);
            })
            .where((subscription) => subscription.isActivePaid)
            .toList();

    if (subscriptions.isEmpty) {
      return AqsSubscription.free;
    }

    subscriptions.sort((a, b) {
      final aExpiry = a.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bExpiry = b.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bExpiry.compareTo(aExpiry);
    });

    return subscriptions.first;
  }

  static bool _statusIsActive(String status) {
    final normalized = status.trim().toLowerCase();

    return normalized == 'active' ||
        normalized == 'successful' ||
        normalized == 'completed';
  }

  static AqsPlan _planFromString(String value) {
    final v = value.trim().toLowerCase();

    if (v.contains('business')) {
      return AqsPlan.business;
    }

    if (v.contains('pro')) {
      return AqsPlan.pro;
    }

    if (v.contains('basic')) {
      return AqsPlan.basic;
    }

    return AqsPlan.free;
  }

  static AqsBillingCycle _billingCycleFromString(String value) {
    final v = value.trim().toLowerCase();

    if (v.contains('year')) {
      return AqsBillingCycle.yearly;
    }

    if (v.contains('month')) {
      return AqsBillingCycle.monthly;
    }

    return AqsBillingCycle.none;
  }

  static String _planDisplayName(AqsPlan plan) {
    switch (plan) {
      case AqsPlan.free:
        return 'Free';

      case AqsPlan.basic:
        return 'Basic';

      case AqsPlan.pro:
        return 'Pro';

      case AqsPlan.business:
        return 'Business';
    }
  }

  static int _projectLimit(AqsPlan plan) {
    switch (plan) {
      case AqsPlan.free:
        return 1;

      case AqsPlan.basic:
        return 2;

      case AqsPlan.pro:
        return 25;

      case AqsPlan.business:
        return 100;
    }
  }

  static int _userLimit(AqsPlan plan) {
    switch (plan) {
      case AqsPlan.free:
        return 1;

      case AqsPlan.basic:
        return 1;

      case AqsPlan.pro:
        return 1;

      case AqsPlan.business:
        return 5;
    }
  }

  static String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();

      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  static String? _nullableText(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  static double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  static int? _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
