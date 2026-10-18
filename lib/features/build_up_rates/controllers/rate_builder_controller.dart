import 'package:aqs/features/build_up_rates/controllers/build_up_rates_controller.dart';
import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:aqs/features/build_up_rates/models/rate_activity.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/repositories/build_up_rate_repository.dart';
import 'package:aqs/features/build_up_rates/repositories/resource_repository.dart';
import 'package:aqs/features/build_up_rates/services/rate_calculation_service.dart';
import 'package:aqs/features/build_up_rates/services/rate_preset_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

class RateBuilderController extends GetxController {
  RateBuilderController({
    this.rateId,
    BuildUpRateRepository? repository,
    ResourceRepository? resourceRepository,
  }) : _repository = repository ?? BuildUpRateRepository(),
       _resourceRepository = resourceRepository ?? ResourceRepository();
  final String? rateId;
  final BuildUpRateRepository _repository;
  final ResourceRepository _resourceRepository;
  final name = ''.obs,
      description = ''.obs,
      unit = 'm²'.obs,
      currency = 'TZS'.obs;
  final category = RateCategory.custom.obs;
  final activity = ''.obs;
  final showDescription = false.obs;
  final breakdownAvailable = false.obs;
  final breakdownNotice = ''.obs;
  final components = <RateComponent>[].obs;
  final overheadsPercent = 10.0.obs, profitPercent = 15.0.obs;
  final isLoading = false.obs, isSaving = false.obs;
  final error = ''.obs;
  final _calculator = const RateCalculationService();
  final _presets = const RatePresetService();
  bool _presetUntouched = false;
  RateCalculation get calculation => _calculator.calculate(
    components,
    overheadsPercent: overheadsPercent.value,
    profitPercent: profitPercent.value,
  );
  List<RateComponent> componentsOf(RateComponentType type) =>
      components.where((item) => item.type == type).toList();

  @override
  void onInit() {
    super.onInit();
    if ((rateId ?? '').isNotEmpty) load();
  }

  Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || rateId == null) return;
    isLoading.value = true;
    final rate = await _repository.get(uid, rateId!);
    if (rate != null) {
      name.value = rate.activity.isEmpty ? rate.name : rate.activity;
      description.value = rate.description;
      showDescription.value = rate.description.isNotEmpty;
      category.value = rate.category;
      activity.value =
          rate.activity.isEmpty
              ? RateActivities.defaultFor(rate.category)
              : rate.activity;
      unit.value = rate.unit;
      currency.value = rate.currency;
      overheadsPercent.value = rate.overheadsPercent;
      profitPercent.value = rate.profitPercent;
      components.assignAll(rate.components);
      breakdownAvailable.value = _presets.build(rate.activity) != null;
    }
    isLoading.value = false;
  }

  void addComponent(RateComponentType type) => components.add(
    RateComponent(
      componentId: const Uuid().v4(),
      type: type,
      name: '',
      unit: type == RateComponentType.labour ? 'hr' : 'No.',
      quantity: 1,
      unitRate: 0,
      sortOrder: components.length,
    ),
  );
  void updateComponent(RateComponent value) {
    _presetUntouched = false;
    final index = components.indexWhere(
      (item) => item.componentId == value.componentId,
    );
    if (index >= 0) components[index] = value;
    _refreshDerivedComponents();
  }

  void removeComponent(String id) {
    _presetUntouched = false;
    components.removeWhere((item) => item.componentId == id);
  }

  Future<void> selectCategory(RateCategory value) async {
    category.value = value;
    activity.value =
        value == RateCategory.custom ? '' : RateActivities.defaultFor(value);
    name.value = activity.value;
    await _applyPreset(activity.value);
  }

  void selectActivity(String value) {
    activity.value = value;
    name.value = value;
  }

  Future<void> selectPresetActivity(String value) async {
    selectActivity(value);
    await _applyPreset(value);
  }

  Future<void> _applyPreset(String value) async {
    if (components.isNotEmpty && !_presetUntouched) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var resources = <RateResource>[];
    if (uid != null) {
      try {
        resources = await _resourceRepository.list(uid);
      } catch (_) {
        // Presets still work with zero prices for manual rate entry.
      }
    }
    final preset = _presets.build(value, resources: resources);
    if (preset == null) {
      if (_presetUntouched) components.clear();
      _presetUntouched = false;
      breakdownAvailable.value = false;
      breakdownNotice.value =
          value.isEmpty
              ? ''
              : 'The $value breakdown is still being constructed. It will be available after its QS resource analysis is approved.';
      return;
    }
    components.assignAll(preset.components);
    unit.value = preset.outputUnit;
    overheadsPercent.value = preset.overheads;
    profitPercent.value = preset.profit;
    _presetUntouched = true;
    breakdownAvailable.value = true;
    breakdownNotice.value = '';
  }

  void _refreshDerivedComponents() {
    for (var index = 0; index < components.length; index++) {
      final component = components[index];
      if (!component.description.startsWith('Calculated automatically:')) {
        continue;
      }
      final base =
          component.name == 'Material transport allowance'
              ? components
                  .where((item) => item.type == RateComponentType.material)
                  .fold<double>(0, (sum, item) => sum + item.amount)
              : component.name == 'Contractor overhead and profit'
              ? components
                  .take(index)
                  .fold<double>(0, (sum, item) => sum + item.amount)
              : components
                  .take(index)
                  .where(
                    (item) =>
                        !item.description.startsWith(
                          'Calculated automatically:',
                        ),
                  )
                  .fold<double>(0, (sum, item) => sum + item.amount);
      components[index] = component.copyWith(unitRate: base);
    }
  }

  String? validate() {
    if (activity.value.trim().isEmpty) {
      return 'Activity / Type is required.';
    }
    if (unit.value.trim().isEmpty) {
      return 'Unit is required.';
    }
    if (components.isEmpty) {
      return breakdownNotice.value.isNotEmpty
          ? breakdownNotice.value
          : 'This activity does not yet have an approved resource breakdown.';
    }
    if (overheadsPercent.value < 0 ||
        profitPercent.value < 0 ||
        !overheadsPercent.value.isFinite ||
        !profitPercent.value.isFinite) {
      return 'Overheads and profit must be valid positive percentages.';
    }
    for (final component in components) {
      if (component.description.startsWith('Calculated automatically:')) {
        continue;
      }
      if (component.name.trim().isEmpty) {
        return 'Every component needs a resource name.';
      }
      if (component.quantity < 0 ||
          component.unitRate < 0 ||
          component.wastePercent < 0 ||
          !component.amount.isFinite) {
        return 'Component values cannot be negative or invalid.';
      }
      if (component.unitRate <= 0) {
        return 'Enter the unit price for ${component.name}.';
      }
    }
    return null;
  }

  Future<String?> save() async {
    final validation = validate();
    if (validation != null) {
      error.value = validation;
      return null;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      error.value = 'Sign in to save rates.';
      return null;
    }
    isSaving.value = true;
    error.value = '';
    try {
      if ((rateId ?? '').isEmpty &&
          Get.isRegistered<BuildUpRatesController>()) {
        final permission =
            await Get.find<BuildUpRatesController>().creationPermission();
        if (!permission.allowed) {
          error.value = permission.message;
          return null;
        }
      }
      final calc = calculation;
      await _saveResourcePrices(uid);
      final rate = BuildUpRate(
        rateId: rateId ?? '',
        name: activity.value.trim(),
        description: showDescription.value ? description.value.trim() : '',
        activity: activity.value,
        category: category.value,
        unit: unit.value.trim(),
        currency: currency.value,
        finalRate: calc.finalRate,
        directCost: calc.directCost,
        overheadsPercent: overheadsPercent.value,
        overheadsAmount: calc.overheadsAmount,
        profitPercent: profitPercent.value,
        profitAmount: calc.profitAmount,
        wasteAmount: calc.wasteAmount,
        components: components,
        createdBy: uid,
      );
      final id = await _repository.save(uid, rate);
      if (Get.isRegistered<BuildUpRatesController>()) {
        await Get.find<BuildUpRatesController>().load(forceRefresh: true);
      }
      return id;
    } catch (e) {
      error.value = 'Could not save rate: $e';
      return null;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> _saveResourcePrices(String uid) async {
    final existing = await _resourceRepository.list(uid);
    String normalise(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    for (final component in components) {
      final match = existing.firstWhereOrNull(
        (resource) =>
            resource.category == component.type &&
            normalise(resource.name) == normalise(component.name),
      );
      await _resourceRepository.save(
        uid,
        RateResource(
          resourceId: match?.resourceId ?? '',
          name: component.name,
          category: component.type,
          unit: component.unit,
          currentRate: component.unitRate,
          currency: currency.value,
          supplier: match?.supplier ?? '',
          notes: match?.notes ?? component.description,
        ),
      );
    }
  }
}
