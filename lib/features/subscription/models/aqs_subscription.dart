import 'package:cloud_firestore/cloud_firestore.dart';

class AqsSubscription {
  const AqsSubscription({
    required this.subscriptionId,
    required this.status,
    required this.planId,
    required this.planName,
    required this.productCode,
    required this.billingCycle,
    required this.amountPaid,
    required this.currency,
    required this.startedAt,
    required this.expiresAt,
    required this.paymentId,
    required this.externalId,
  });

  final String subscriptionId;
  final String status;
  final String planId;
  final String planName;
  final String productCode;
  final String billingCycle;

  final double? amountPaid;
  final String currency;

  final DateTime? startedAt;
  final DateTime? expiresAt;

  final String paymentId;
  final String externalId;

  bool get isActive {
    if (status.toLowerCase() != 'active') {
      return false;
    }

    if (expiresAt == null) {
      return true;
    }

    return expiresAt!.isAfter(DateTime.now());
  }

  bool get isBasic => isActive && planId.toLowerCase() == 'basic';

  bool get isPro => isActive && planId.toLowerCase() == 'pro';

  bool get isBusiness => isActive && planId.toLowerCase() == 'business';

  bool get hasPaidPlan => isBasic || isPro || isBusiness;

  factory AqsSubscription.fromMap(Map<String, dynamic> map) {
    return AqsSubscription(
      subscriptionId: (map['subscriptionId'] ?? '').toString(),

      status: (map['subscriptionStatus'] ?? '').toString(),

      planId: (map['subscriptionPlanId'] ?? '').toString(),

      planName: (map['subscriptionPlanName'] ?? '').toString(),

      productCode: (map['subscriptionProductCode'] ?? '').toString(),

      billingCycle: (map['subscriptionBillingCycle'] ?? '').toString(),

      amountPaid:
          map['subscriptionAmountPaid'] is num
              ? (map['subscriptionAmountPaid'] as num).toDouble()
              : null,

      currency: (map['subscriptionCurrency'] ?? 'TZS').toString(),

      startedAt: _readDate(map['subscriptionStartedAt']),

      expiresAt: _readDate(map['subscriptionExpiresAt']),

      paymentId: (map['subscriptionPaymentId'] ?? '').toString(),

      externalId: (map['subscriptionExternalId'] ?? '').toString(),
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}
