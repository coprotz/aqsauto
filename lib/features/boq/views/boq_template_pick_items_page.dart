import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/boq_template_controller.dart';
import '../controllers/boq_template_pick_controller.dart';
// import '../models/boq_template_item_model.dart';

class BoqTemplatePickItemsPageGetX extends StatefulWidget {
  const BoqTemplatePickItemsPageGetX({super.key});

  @override
  State<BoqTemplatePickItemsPageGetX> createState() =>
      _BoqTemplatePickItemsPageGetXState();
}

class _BoqTemplatePickItemsPageGetXState
    extends State<BoqTemplatePickItemsPageGetX> {
  late final BoqTemplatePickController pick;
  late final BoqTemplateController tpl;

  // ✅ observables
  final RxSet<String> selectedIds = <String>{}.obs;
  final RxBool selectAll = false.obs;
  final RxBool saving = false.obs;

  @override
  void initState() {
    super.initState();
    pick = Get.find<BoqTemplatePickController>();
    tpl = Get.find<BoqTemplateController>(); // ensure registered in binding
  }

  @override
  void dispose() {
    // Rx types don't need dispose, but fine to close controllers if any
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TEMPLATE: ${pick.templateName.toUpperCase()}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                // ✅ ONLY this Text is reactive
                Expanded(
                  child: Obx(() {
                    final s = pick.structureName.value; // <-- reads RxString
                    return Text(
                      s.isEmpty ? 'Loading structure...' : 'Target: $s',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ),

                // ✅ ONLY this Text is reactive
                Obx(() => Text('Selected: ${selectedIds.length}')),
              ],
            ),
          ),
        ),
      ),

      body: StreamBuilder<List<BoqTemplateItem>>(
        stream: tpl.itemsStream(pick.templateId),
        builder: (ctx, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snap.data!;
          if (all.isEmpty) {
            return const Center(child: Text('No items in this template.'));
          }

          final selectable =
              all.where((e) => e.rowType.toLowerCase() == 'item').toList();
          final allRows = all.map((item) => item.raw).toList();
          final isCivilTemplate =
              pick.templateName.toLowerCase().contains('civil') ||
              all.any(
                (item) =>
                    '${item.raw['boqWorkType']}'.trim().toLowerCase() ==
                        'civil' ||
                    '${item.raw['sectionType']}'.trim().toLowerCase() ==
                        'series',
              );
          String visibleCode(BoqTemplateItem item) {
            if (isCivilTemplate || item.rowType.toLowerCase() == 'item') {
              final resolved = hierarchicalBoqCodeFromRows(item.raw, allRows);
              if (resolved.isNotEmpty) return resolved;
            }
            return item.boqCode.trim();
          }

          return Column(
            children: [
              // top actions row
              Material(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Text('Select all'),
                      // ✅ Switch reads selectAll inside Obx
                      Obx(() {
                        return Switch(
                          value: selectAll.value,
                          onChanged: (v) {
                            selectAll.value = v;
                            selectedIds.clear();
                            if (v) {
                              selectedIds.addAll(selectable.map((e) => e.id));
                            }
                          },
                        );
                      }),
                      const Spacer(),
                      // ✅ Clear button reads selectedIds inside Obx
                      Obx(() {
                        return TextButton.icon(
                          onPressed:
                              selectedIds.isEmpty
                                  ? null
                                  : () {
                                    selectedIds.clear();
                                    selectAll.value = false;
                                  },
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // list
              Expanded(
                child: ListView.builder(
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final it = all[i];
                    final type = it.rowType.toLowerCase();
                    final isItem = type == 'item';

                    // ✅ each row checkbox reactive only for its value
                    if (!isItem) {
                      // ✅ headings: NO Obx (no reactive data needed)
                      final code = visibleCode(it);
                      final title =
                          code.isEmpty
                              ? it.description.toUpperCase()
                              : '$code  —  ${it.description.toUpperCase()}';
                      return ListTile(
                        dense: true,
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      );
                    }

                    // ✅ item rows: Obx because checkbox depends on selectedIds/selectAll
                    return Obx(() {
                      final checked = selectedIds.contains(it.id);

                      final title = '${visibleCode(it)}  —  ${it.description}';

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          if (v == true) {
                            selectedIds.add(it.id);
                          } else {
                            selectedIds.remove(it.id);
                          }

                          // keep selectAll in sync (read selectedIds inside Obx-safe callback)
                          selectAll.value =
                              selectable.isNotEmpty &&
                              selectedIds.length == selectable.length;
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: false,
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          it.unit.isEmpty ? '' : 'Unit: ${it.unit}',
                        ),
                      );
                    });
                  },
                ),
              ),

              // bottom add button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Obx(() {
                    final count = selectedIds.length;
                    final busy = saving.value;

                    return SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed:
                            (count == 0 || busy)
                                ? null
                                : () async {
                                  saving.value = true;
                                  try {
                                    final chosen =
                                        selectable
                                            .where(
                                              (e) => selectedIds.contains(e.id),
                                            )
                                            .toList();

                                    final added = await pick
                                        .addSelectedToProjectBoq(chosen);

                                    Get.back(); // back to BOQ page
                                    Get.snackbar(
                                      'BOQ',
                                      'Added $added items from template.',
                                      snackPosition: SnackPosition.BOTTOM,
                                    );
                                  } catch (e) {
                                    Get.snackbar(
                                      'Error',
                                      e.toString(),
                                      snackPosition: SnackPosition.BOTTOM,
                                    );
                                  } finally {
                                    saving.value = false;
                                  }
                                },
                        icon: const Icon(Icons.playlist_add),
                        label: Text(
                          busy ? 'ADDING...' : 'ADD SELECTED ($count)',
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
