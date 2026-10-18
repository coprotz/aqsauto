import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/build_up_rates/services/rate_limit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = RateLimitService();

  group('RateLimitService', () {
    test('Free allows 3 rates', () {
      expect(
        service.canCreateRate(plan: AqsPlan.free, currentRateCount: 2).allowed,
        isTrue,
      );
      final result = service.canCreateRate(
        plan: AqsPlan.free,
        currentRateCount: 3,
      );
      expect(result.allowed, isFalse);
      expect(result.limit, 3);
    });

    test('Basic allows 10 rates', () {
      expect(
        service.canCreateRate(plan: AqsPlan.basic, currentRateCount: 9).allowed,
        isTrue,
      );
      expect(
        service
            .canCreateRate(plan: AqsPlan.basic, currentRateCount: 10)
            .allowed,
        isFalse,
      );
    });

    test('Pro allows 25 rates', () {
      expect(
        service.canCreateRate(plan: AqsPlan.pro, currentRateCount: 24).allowed,
        isTrue,
      );
      expect(
        service.canCreateRate(plan: AqsPlan.pro, currentRateCount: 25).allowed,
        isFalse,
      );
    });

    test('Business allows unlimited rates', () {
      final result = service.canCreateRate(
        plan: AqsPlan.business,
        currentRateCount: 1000000,
      );
      expect(result.allowed, isTrue);
      expect(result.limit, isNull);
    });
  });
}
