import 'package:aqs/app_routes.dart';
import 'package:aqs/features/pricing/views/pricing_plans_page.dart';
import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BoqTemplatePickDialog extends StatelessWidget {
  final BoqTemplateController controller;

  const BoqTemplatePickDialog({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller; // ✅ resolve once (don’t call getter many times)

    return FutureBuilder<AqsTemplateAllowance>(
      future: ctrl.currentAqsTemplateAllowance(),
      builder: (context, allowanceSnap) {
        final allowance = allowanceSnap.data;
        return AlertDialog(
          title: const Text('Select BOQ template'),
          content: SizedBox(
            width: 560,
            height: 480,
            child: DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TabBar(
                    tabs: [Tab(text: 'Default'), Tab(text: 'My Templates')],
                  ),
                  const SizedBox(height: 10),
                  if (allowance == null)
                    const LinearProgressIndicator()
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFAEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEDF89)),
                      ),
                      child: Text(
                        '${allowance.planName} plan: ${allowance.used} of ${allowance.limit} AQS templates used. Personal templates are free and unlimited.',
                        style: const TextStyle(
                          color: Color(0xFF175CD3),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TemplatePickList(
                          stream: ctrl.defaultTemplatesStream(),
                          emptyText: 'No default templates found.',
                          locked: false,
                          controller: ctrl,
                          allowance: allowance,
                        ),
                        _TemplatePickList(
                          stream: ctrl.myTemplatesStream(),
                          emptyText: 'No personal templates found.',
                          locked: false,
                          controller: ctrl,
                          allowCreate: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }
}

class _TemplatePickList extends StatelessWidget {
  const _TemplatePickList({
    required this.stream,
    required this.emptyText,
    required this.locked,
    required this.controller,
    this.allowCreate = false,
    this.allowance,
  });

  final Stream<List<BoqTemplate>> stream;
  final String emptyText;
  final bool locked;
  final BoqTemplateController controller;
  final bool allowCreate;
  final AqsTemplateAllowance? allowance;

  void _openPlans() {
    Get.back();
    Get.to(() => const PricingPlansPage());
  }

  void _pickTemplate(BoqTemplate template) {
    Get.back(
      result: TplPickResult(
        templateId: template.id,
        templateName: template.name,
        templateScope: template.templateScope,
      ),
    );
  }

  Future<void> _createMyTemplate() async {
    final nameCtrl = TextEditingController();
    final name = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Create my template'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'e.g. My residential BOQ',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Get.back(result: nameCtrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          FilledButton.icon(
            onPressed: () => Get.back(result: nameCtrl.text.trim()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('CREATE'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    final cleanName = (name ?? '').trim();
    if (cleanName.isEmpty) return;

    try {
      final templateId = await controller.createTemplate(cleanName);
      Get.back();
      Get.toNamed(
        AppRoutes.boqTemplateItemsManage,
        arguments: {'templateId': templateId, 'templateName': cleanName},
      );
    } catch (e) {
      Get.snackbar(
        'Template',
        'Failed to create template: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _deleteMyTemplate(BoqTemplate template) async {
    if (template.isDefaultTemplate) return;

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          'This will permanently delete "${template.name}" and all BOQ items saved inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton.icon(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await controller.deleteTemplate(template.id);
      Get.snackbar(
        'Template',
        'Template deleted',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Template',
        'Failed to delete template: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BoqTemplate>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final templates = snap.data!;
        final createButton =
            allowCreate
                ? Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: locked ? null : _createMyTemplate,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add my template'),
                  ),
                )
                : const SizedBox.shrink();

        if (templates.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              createButton,
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emptyText, textAlign: TextAlign.center),
                      if (allowCreate) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: locked ? null : _createMyTemplate,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add my template'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            createButton,
            if (allowCreate) const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = templates[i];
                  final requiresUpgrade =
                      t.isDefaultTemplate &&
                      allowance != null &&
                      !allowance!.canUse(t.id);
                  final icon =
                      requiresUpgrade
                          ? Icons.lock_outline_rounded
                          : (t.isDefaultTemplate
                              ? Icons.verified_outlined
                              : Icons.person_outline_rounded);
                  return ListTile(
                    leading: Icon(icon),
                    title: Text(t.name),
                    subtitle: Text(
                      t.isDefaultTemplate
                          ? 'Default SaaS template'
                          : 'My private template',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (allowCreate && !t.isDefaultTemplate) ...[
                          IconButton(
                            tooltip: 'Delete template',
                            onPressed: () => _deleteMyTemplate(t),
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton.icon(
                          onPressed:
                              requiresUpgrade
                                  ? _openPlans
                                  : () => _pickTemplate(t),
                          icon: Icon(
                            requiresUpgrade
                                ? Icons.workspace_premium_outlined
                                : Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(requiresUpgrade ? 'Upgrade' : 'Add'),
                        ),
                      ],
                    ),
                    onTap:
                        requiresUpgrade ? _openPlans : () => _pickTemplate(t),
                    onLongPress:
                        allowCreate && !t.isDefaultTemplate
                            ? () => _deleteMyTemplate(t)
                            : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
