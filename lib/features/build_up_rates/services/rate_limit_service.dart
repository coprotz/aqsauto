import 'package:aqs/features/billing/services/subscription_service.dart';

class RateLimitResult {
  const RateLimitResult({
    required this.allowed,
    required this.limit,
    required this.message,
  });
  final bool allowed;
  final int? limit;
  final String message;
}

class RateLimitService {
  const RateLimitService();

  RateLimitResult canCreateRate({
    required AqsPlan plan,
    required int currentRateCount,
  }) {
    final limit = switch (plan) {
      AqsPlan.free => 3,
      AqsPlan.basic => 10,
      AqsPlan.pro => 25,
      AqsPlan.business => null,
    };
    if (limit == null || currentRateCount < limit) {
      return RateLimitResult(allowed: true, limit: limit, message: '');
    }
    final name = switch (plan) {
      AqsPlan.free => 'Free',
      AqsPlan.basic => 'Basic',
      AqsPlan.pro => 'Pro',
      AqsPlan.business => 'Business',
    };
    return RateLimitResult(
      allowed: false,
      limit: limit,
      message:
          'You have reached the $name plan limit of $limit build-up rate${limit == 1 ? '' : 's'}. Upgrade your plan to create more rates.',
    );
  }
}
