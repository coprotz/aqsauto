import 'package:aqs/features/build_up_rates/controllers/resource_library_controller.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/models/rate_units.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ResourceLibraryPage extends StatefulWidget {
  const ResourceLibraryPage({super.key});
  @override
  State<ResourceLibraryPage> createState() => _ResourceLibraryPageState();
}

class _ResourceLibraryPageState extends State<ResourceLibraryPage> {
  late final ResourceLibraryController controller;

  @override
  void initState() {
    super.initState();
    controller =
        Get.isRegistered<ResourceLibraryController>()
            ? Get.find()
            : Get.put(ResourceLibraryController());
    controller.load();
  }

  Future<void> edit([RateResource? resource]) async {
    final name = TextEditingController(text: resource?.name ?? '');
    var selectedUnit =
        resource?.unit ?? RateUnits.defaultFor(controller.selectedType.value);
    final rate = TextEditingController(text: '${resource?.currentRate ?? ''}');
    final notes = TextEditingController(text: resource?.notes ?? '');
    var type = resource?.category ?? controller.selectedType.value;
    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text(
                    resource == null ? 'Add Resource' : 'Edit Resource',
                  ),
                  content: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'Resource name',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<RateComponentType>(
                          initialValue: type,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items:
                              RateComponentType.values
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value.label),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) =>
                                  setDialogState(() => type = value ?? type),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                ),
                                items:
                                    RateUnits.including(selectedUnit)
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Text(value),
                                          ),
                                        )
                                        .toList(),
                                onChanged:
                                    (value) => setDialogState(
                                      () =>
                                          selectedUnit = value ?? selectedUnit,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: rate,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Current unit rate',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: notes,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await controller.save(
        RateResource(
          resourceId: resource?.resourceId ?? '',
          name: name.text.trim(),
          category: type,
          unit: selectedUnit,
          currentRate: double.tryParse(rate.text) ?? 0,
          currency: 'TZS',
          notes: notes.text.trim(),
        ),
      );
    }
    name.dispose();
    rate.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Resource Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Resource'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search resources',
                  ),
                  onChanged: (value) => controller.searchQuery.value = value,
                ),
                const SizedBox(height: 14),
                Obx(
                  () => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        RateComponentType.values
                            .map(
                              (type) => ChoiceChip(
                                label: Text(type.label),
                                selected: controller.selectedType.value == type,
                                onSelected:
                                    (_) => controller.selectedType.value = type,
                              ),
                            )
                            .toList(),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Obx(() {
                    if (controller.isLoading.value) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = controller.filtered;
                    if (rows.isEmpty) {
                      return const Center(
                        child: Text('No resources in this category yet.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final resource = rows[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              resource.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${resource.unit} • ${resource.currency} ${resource.currentRate.toStringAsFixed(2)}${resource.notes.isEmpty ? '' : ' • ${resource.notes}'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => edit(resource),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: () => controller.delete(resource),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFD92D20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
