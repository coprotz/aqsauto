import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AqsPaymentResult {
  const AqsPaymentResult({
    required this.success,
    required this.attemptId,
    required this.applicationReference,
    required this.paymentId,
    required this.externalId,
    required this.status,
    required this.stage,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.providerReference,
  });

  final bool success;
  final String attemptId;
  final String applicationReference;
  final String paymentId;
  final String externalId;
  final String status;
  final String stage;
  final double? amount;
  final String currency;
  final String provider;
  final String? providerReference;

  bool get isSuccessful {
    final normalizedStatus = status.toLowerCase();
    final normalizedStage = stage.toLowerCase();

    return normalizedStatus == 'successful' ||
        normalizedStatus == 'completed' ||
        normalizedStage == 'completed';
  }

  factory AqsPaymentResult.fromMap(Map<String, dynamic> map) {
    return AqsPaymentResult(
      success: map['success'] == true,
      attemptId: (map['attemptId'] ?? '').toString(),
      applicationReference: (map['applicationReference'] ?? '').toString(),
      paymentId: (map['paymentId'] ?? '').toString(),
      externalId: (map['externalId'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      stage: (map['stage'] ?? '').toString(),
      amount: map['amount'] is num ? (map['amount'] as num).toDouble() : null,
      currency: (map['currency'] ?? 'TZS').toString(),
      provider: (map['provider'] ?? '').toString(),
      providerReference:
          map['providerReference'] == null
              ? null
              : map['providerReference'].toString(),
    );
  }
}

class AqsPaymentService {
  AqsPaymentService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<AqsPaymentResult> initiatePayment({
    required String productCode,
    required String provider,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('You must be signed in to make a payment.');
    }

    final callable = _functions.httpsCallable('initiateAqsPayment');

    final response = await callable.call({
      'productCode': productCode,
      'provider': provider,
      'customer': {
        'name': customerName ?? user.displayName ?? '',
        'email': customerEmail ?? user.email ?? '',
        'phone': customerPhone ?? user.phoneNumber ?? '',
      },
    });

    final raw = response.data;

    if (raw is! Map) {
      throw Exception('Unexpected payment response from server.');
    }

    return AqsPaymentResult.fromMap(Map<String, dynamic>.from(raw));
  }
}
