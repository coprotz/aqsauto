import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:aqs/features/build_up_rates/repositories/build_up_rate_repository.dart';
import 'package:aqs/features/build_up_rates/services/rate_limit_service.dart';
import 'package:aqs/features/build_up_rates/widgets/rate_limit_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class BuildUpRatesController extends GetxController {
  BuildUpRatesController({BuildUpRateRepository? repository})
    : _repository = repository ?? BuildUpRateRepository();
  final BuildUpRateRepository _repository;
  final rates = <BuildUpRate>[].obs;
  final isLoading = false.obs;
  final error = ''.obs;
  final searchQuery = ''.obs;
  final selectedCategory = 'All'.obs;
  bool _loaded = false;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;
  List<BuildUpRate> get filteredRates {
    final query = searchQuery.value.trim().toLowerCase();
    return rates.where((rate) {
      final categoryMatch =
          selectedCategory.value == 'All' ||
          rate.category.label == selectedCategory.value;
      final searchMatch =
          query.isEmpty ||
          rate.name.toLowerCase().contains(query) ||
          rate.description.toLowerCase().contains(query);
      return categoryMatch && searchMatch;
    }).toList();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return;
    final userId = uid;
    if (userId == null) {
      error.value = 'Sign in to view and save build-up rates.';
      return;
    }
    isLoading.value = true;
    error.value = '';
    try {
      rates.assignAll(await _repository.list(userId));
      _loaded = true;
    } catch (e) {
      error.value = 'Could not load build-up rates: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<RateLimitResult> creationPermission() async {
    final subscription =
        await SubscriptionService.instance.currentSubscription();
    return const RateLimitService().canCreateRate(
      plan: subscription.plan,
      currentRateCount: rates.length,
    );
  }

  Future<void> deleteRate(BuildUpRate rate) async {
    final userId = uid;
    if (userId == null) return;
    await _repository.delete(userId, rate.rateId);
    rates.removeWhere((item) => item.rateId == rate.rateId);
  }

  Future<String?> duplicate(BuildUpRate summary) async {
    final userId = uid;
    if (userId == null) return null;
    final permission = await creationPermission();
    if (!permission.allowed) {
      await showRateLimitDialog(permission);
      return null;
    }
    final source = await _repository.get(userId, summary.rateId);
    if (source == null) return null;
    final copy = BuildUpRate(
      rateId: '',
      name: '${source.name} - Copy',
      description: source.description,
      activity: source.activity,
      category: source.category,
      unit: source.unit,
      currency: source.currency,
      finalRate: source.finalRate,
      directCost: source.directCost,
      overheadsPercent: source.overheadsPercent,
      overheadsAmount: source.overheadsAmount,
      profitPercent: source.profitPercent,
      profitAmount: source.profitAmount,
      wasteAmount: source.wasteAmount,
      components: source.components,
      createdBy: userId,
    );
    final id = await _repository.save(userId, copy);
    await load(forceRefresh: true);
    return id;
  }
}
