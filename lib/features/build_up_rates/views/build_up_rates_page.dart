import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/build_up_rates/controllers/build_up_rates_controller.dart';
import 'package:aqs/features/build_up_rates/controllers/resource_library_controller.dart';
import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/widgets/rate_limit_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BuildUpRatesPage extends StatefulWidget {
  const BuildUpRatesPage({super.key});
  @override
  State<BuildUpRatesPage> createState() => _BuildUpRatesPageState();
}

class _BuildUpRatesPageState extends State<BuildUpRatesPage> {
  late final BuildUpRatesController controller;
  late final ResourceLibraryController resourcesController;
  @override
  void initState() {
    super.initState();
    controller =
        Get.isRegistered<BuildUpRatesController>()
            ? Get.find()
            : Get.put(BuildUpRatesController());
    resourcesController =
        Get.isRegistered<ResourceLibraryController>()
            ? Get.find<ResourceLibraryController>()
            : Get.put(ResourceLibraryController());
    controller.load();
    resourcesController.load();
  }

  Future<void> createRate() async {
    if (FirebaseAuth.instance.currentUser == null) {
      Get.toNamed(AppRoutes.login);
      return;
    }
    final result = await controller.creationPermission();
    if (!result.allowed) {
      await showRateLimitDialog(result);
      return;
    }
    Get.toNamed(AppRoutes.buildUpRateNew);
  }

  Future<void> confirmDelete(BuildUpRate rate) async {
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete build-up rate?'),
            content: Text('Delete “${rate.name}” and all of its components?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD92D20),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (yes == true) await controller.deleteRate(rate);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      title: const AqsAppBarTitle(
        title: 'Build-Up Rates',
        subtitle: 'AQS AUTOBOQ',
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: TextButton.icon(
            onPressed: () => Get.offAllNamed(AppRoutes.dashboard),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Home'),
          ),
        ),
        TextButton.icon(
          onPressed: () => Get.toNamed(AppRoutes.labourRates),
          icon: const Icon(Icons.people_outline),
          label: const Text('Labour Rates'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: OutlinedButton.icon(
            onPressed: () => Get.toNamed(AppRoutes.buildUpRateResources),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Resource Library'),
          ),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => controller.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build-Up Rates',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: AqsColors.ink,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Build, save and reuse transparent rates for BOQ items.',
                          style: TextStyle(
                            color: AqsColors.muted,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: createRate,
                      icon: const Icon(Icons.add),
                      label: const Text('Build New Rate'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Obx(
                  () => Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search saved rates',
                          ),
                          onChanged: (v) => controller.searchQuery.value = v,
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: controller.selectedCategory.value,
                        items:
                            ['All', ...RateCategory.values.map((e) => e.label)]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) =>
                                controller.selectedCategory.value = v ?? 'All',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Obx(
                  () => _Kpis(
                    rates: controller.rates.toList(growable: false),
                    resources: resourcesController.resources.toList(
                      growable: false,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Obx(() {
                  if (controller.isLoading.value) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(50),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (controller.error.value.isNotEmpty) {
                    return Center(child: Text(controller.error.value));
                  }
                  final rates = controller.filteredRates;
                  if (rates.isEmpty) return _EmptyRates(onCreate: createRate);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 1000
                              ? 3
                              : constraints.maxWidth >= 650
                              ? 2
                              : 1;
                      final width =
                          (constraints.maxWidth - (16 * (columns - 1))) /
                          columns;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children:
                            rates
                                .map(
                                  (rate) => SizedBox(
                                    width: width,
                                    child: _RateCard(
                                      rate: rate,
                                      onOpen:
                                          () => Get.toNamed(
                                            AppRoutes.buildUpRateDetailsPath(
                                              rate.rateId,
                                            ),
                                          ),
                                      onDuplicate:
                                          () => controller.duplicate(rate),
                                      onDelete: () => confirmDelete(rate),
                                    ),
                                  ),
                                )
                                .toList(),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.rates, required this.resources});
  final List<BuildUpRate> rates;
  final List<RateResource> resources;
  @override
  Widget build(BuildContext context) {
    final values = [
      ('Saved Rates', rates.length, Icons.receipt_long_outlined),
      (
        'Materials',
        resources
            .where(
              (resource) => resource.category == RateComponentType.material,
            )
            .length,
        Icons.inventory_2_outlined,
      ),
      (
        'Labour Resources',
        resources
            .where((resource) => resource.category == RateComponentType.labour)
            .length,
        Icons.engineering_outlined,
      ),
      (
        'Plant Resources',
        resources
            .where((resource) => resource.category == RateComponentType.plant)
            .length,
        Icons.precision_manufacturing_outlined,
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          values
              .map(
                (v) => Container(
                  width: 210,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AqsColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(v.$3, color: AqsColors.primary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${v.$2}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            v.$1,
                            style: const TextStyle(color: AqsColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({
    required this.rate,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });
  final BuildUpRate rate;
  final VoidCallback onOpen, onDuplicate, onDelete;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AqsColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rate.name,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'duplicate') onDuplicate();
                if (v == 'delete') onDelete();
              },
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
            ),
          ],
        ),
        Text(
          '${rate.category.label}${rate.activity.isEmpty ? '' : ' • ${rate.activity}'} • ${rate.unit}',
          style: const TextStyle(color: AqsColors.muted),
        ),
        const SizedBox(height: 18),
        Text(
          '${rate.currency} ${NumberFormat('#,##0.00').format(rate.finalRate)} / ${rate.unit}',
          style: const TextStyle(
            color: AqsColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${rate.componentCount} components • ${rate.updatedAt == null ? 'Recently updated' : DateFormat('dd MMM yyyy').format(rate.updatedAt!)}',
          style: const TextStyle(color: AqsColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onOpen,
            child: const Text('Open Rate'),
          ),
        ),
      ],
    ),
  );
}

class _EmptyRates extends StatelessWidget {
  const _EmptyRates({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(50),
      child: Column(
        children: [
          const Icon(
            Icons.calculate_outlined,
            size: 48,
            color: AqsColors.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'No saved build-up rates yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Build your first transparent unit rate.',
            style: TextStyle(color: AqsColors.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Build New Rate'),
          ),
        ],
      ),
    ),
  );
}
