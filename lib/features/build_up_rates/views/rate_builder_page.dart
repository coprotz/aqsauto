import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/build_up_rates/controllers/rate_builder_controller.dart';
import 'package:aqs/features/build_up_rates/models/rate_activity.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/widgets/rate_component_section.dart';
import 'package:aqs/features/build_up_rates/widgets/rate_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RateBuilderPage extends StatefulWidget {
  const RateBuilderPage({super.key, this.rateId});
  final String? rateId;
  @override
  State<RateBuilderPage> createState() => _RateBuilderPageState();
}

class _RateBuilderPageState extends State<RateBuilderPage> {
  late final RateBuilderController controller;
  @override
  void initState() {
    super.initState();
    controller = RateBuilderController(rateId: widget.rateId);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _saveRate() async {
    final id = await controller.save();
    if (id == null) {
      Get.snackbar(
        'Rate not saved',
        controller.error.value.isEmpty
            ? 'Please check the rate details and try again.'
            : controller.error.value,
        backgroundColor: const Color(0xFFFEF3F2),
        colorText: const Color(0xFFB42318),
        snackPosition: SnackPosition.TOP,
      );
      return;
    }
    Get.offNamed(AppRoutes.buildUpRateDetailsPath(id));
    Get.snackbar(
      'Rate saved successfully',
      '${controller.activity.value} has been saved to your build-up rate library.',
      backgroundColor: AqsColors.successSoft,
      colorText: const Color(0xFF027A48),
      icon: const Icon(Icons.check_circle_outline, color: AqsColors.success),
      snackPosition: SnackPosition.TOP,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      title: Text(
        MediaQuery.sizeOf(context).width < 600
            ? widget.rateId == null
                ? 'New Rate'
                : 'Edit Rate'
            : widget.rateId == null
            ? 'Build New Rate'
            : 'Edit Build-Up Rate',
      ),
      actions: [
        Obx(
          () => Padding(
            padding: EdgeInsets.only(
              right: MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
            ),
            child: FilledButton.icon(
              onPressed: controller.isSaving.value ? null : _saveRate,
              icon:
                  controller.isSaving.value
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.save_outlined),
              label: Text(
                MediaQuery.sizeOf(context).width < 600 ? 'Save' : 'Save Rate',
              ),
            ),
          ),
        ),
      ],
    ),
    body: Obx(() {
      if (controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      return Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop = constraints.maxWidth >= 980;
                    final builder = Column(
                      children: [
                        _RateIdentity(controller: controller),
                        const SizedBox(height: 16),
                        Obx(
                          () => Column(
                            children: [
                              if (controller.activity.value.trim().isEmpty &&
                                  !controller.breakdownAvailable.value)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 42,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: AqsColors.border),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Column(
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AqsColors.primarySoft,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(14),
                                          child: Icon(
                                            Icons.account_tree_outlined,
                                            size: 30,
                                            color: AqsColors.primary,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 14),
                                      Text(
                                        'Select an activity to view its breakdown',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AqsColors.ink,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(height: 7),
                                      Text(
                                        'Choose the category and activity above. The required materials, labour, plant and other resources will appear here automatically.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AqsColors.muted,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (controller.breakdownNotice.value.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFAEB),
                                    border: Border.all(
                                      color: const Color(0xFFFEC84B),
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.construction_outlined,
                                        color: Color(0xFFB54708),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          controller.breakdownNotice.value,
                                          style: const TextStyle(
                                            color: Color(0xFF7A2E0E),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              for (final type in RateComponentType.values)
                                if (controller.breakdownAvailable.value)
                                  RateComponentSection(
                                    type: type,
                                    controller: controller,
                                    priceEntryOnly: true,
                                  ),
                              if (controller.error.value.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(14),
                                  color: const Color(0xFFFEF3F2),
                                  child: Text(
                                    controller.error.value,
                                    style: const TextStyle(
                                      color: Color(0xFFB42318),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                    return desktop
                        ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: builder),
                            const SizedBox(width: 20),
                            SizedBox(
                              width: 340,
                              child: RateSummaryCard(controller: controller),
                            ),
                          ],
                        )
                        : Column(
                          children: [
                            builder,
                            RateSummaryCard(controller: controller),
                          ],
                        );
                  },
                ),
              ),
            ),
          ),
          if (controller.isSaving.value)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x99000000),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Color(0x26000000), blurRadius: 24),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text(
                          'Saving rate…',
                          style: TextStyle(
                            color: AqsColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }),
  );
}

class _RateIdentity extends StatelessWidget {
  const _RateIdentity({required this.controller});
  final RateBuilderController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AqsColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rate Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final category = Obx(
              () => DropdownButtonFormField<RateCategory>(
                initialValue: controller.category.value,
                decoration: const InputDecoration(labelText: 'Category'),
                items:
                    RateCategory.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) controller.selectCategory(v);
                },
              ),
            );
            final activity = Obx(() {
              final options = RateActivities.forCategory(
                controller.category.value,
              );
              final selected =
                  options.contains(controller.activity.value)
                      ? controller.activity.value
                      : options.first;
              if (controller.category.value == RateCategory.custom) {
                return TextFormField(
                  key: const ValueKey('custom-activity'),
                  initialValue:
                      controller.activity.value ==
                              RateActivities.defaultFor(RateCategory.custom)
                          ? ''
                          : controller.activity.value,
                  decoration: const InputDecoration(
                    labelText: 'Custom Activity / Type *',
                    hintText: 'Enter the rate activity',
                  ),
                  onChanged: controller.selectActivity,
                );
              }
              return DropdownButtonFormField<String>(
                key: ValueKey(controller.category.value),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Activity / Type *',
                ),
                items:
                    options
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) controller.selectPresetActivity(value);
                },
              );
            });
            final unit = Obx(
              () => TextFormField(
                key: ValueKey('rate-unit-${controller.unit.value}'),
                initialValue: controller.unit.value,
                decoration: const InputDecoration(labelText: 'Unit *'),
                onChanged: (v) => controller.unit.value = v,
              ),
            );
            final currency = TextFormField(
              initialValue: controller.currency.value,
              decoration: const InputDecoration(labelText: 'Currency'),
              onChanged: (v) => controller.currency.value = v,
            );

            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  category,
                  const SizedBox(height: 12),
                  activity,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: unit),
                      const SizedBox(width: 12),
                      Expanded(child: currency),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 2, child: category),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: activity),
                const SizedBox(width: 12),
                Expanded(child: unit),
                const SizedBox(width: 12),
                Expanded(child: currency),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Obx(
          () =>
              controller.showDescription.value
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: controller.description.value,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'BOQ description (optional)',
                        ),
                        onChanged:
                            (value) => controller.description.value = value,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            controller.description.value = '';
                            controller.showDescription.value = false;
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Remove description'),
                        ),
                      ),
                    ],
                  )
                  : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => controller.showDescription.value = true,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add BOQ description'),
                    ),
                  ),
        ),
      ],
    ),
  );
}
