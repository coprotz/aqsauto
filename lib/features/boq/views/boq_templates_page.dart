import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// import 'boq_template_controller.dart';
// import 'boq_template_models.dart';
import 'boq_template_items_page.dart';

class BoqTemplatesPage extends StatelessWidget {
  BoqTemplatesPage({super.key});

  final c = Get.put(BoqTemplateController());

  Future<void> _createTemplate() async {
    final tc = TextEditingController();

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('NEW BOQ TEMPLATE'),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'e.g. BUILDING WORKS, CIVIL WORKS, ELECTRICAL WORKS',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('CREATE'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (ok != true) return;

    final name = tc.text.trim();
    if (name.isEmpty) {
      Get.snackbar(
        'TEMPLATE',
        'Template name is required',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      final id = await c.createTemplate(name);
      Get.to(() => BoqTemplateItemsPage(templateId: id, templateName: name));
    } catch (e) {
      Get.snackbar(
        'TEMPLATE',
        'Failed to create: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _renameTemplate(BoqTemplate t) async {
    final tc = TextEditingController(text: t.name);

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('RENAME TEMPLATE'),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newName = tc.text.trim();
    if (newName.isEmpty) return;

    await c.renameTemplate(t.id, newName);
  }

  Future<void> _deleteTemplate(BoqTemplate t) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('DELETE TEMPLATE?'),
        content: Text(
          'This will delete "${t.name}" and all its items.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await c.deleteTemplate(t.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              const Text('BOQ TEMPLATES'),
              IconButton(
                tooltip: 'Create template',
                onPressed: _createTemplate,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          StreamBuilder<List<BoqTemplate>>(
            stream: c.templatesStream(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('Error loading templates:\n${snap.error}'),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final templates = snap.data!;
              if (templates.isEmpty) {
                return const Center(
                  child: Text(
                    'NO TEMPLATES YET.\n\nTap "NEW TEMPLATE" to create one.',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = templates[i];
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(t.name.toUpperCase()),
                    subtitle: Text('ID: ${t.id}'),
                    onTap:
                        () => Get.to(
                          () => BoqTemplateItemsPage(
                            templateId: t.id,
                            templateName: t.name,
                          ),
                        ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'open') {
                          Get.to(
                            () => BoqTemplateItemsPage(
                              templateId: t.id,
                              templateName: t.name,
                            ),
                          );
                        } else if (v == 'rename') {
                          await _renameTemplate(t);
                        } else if (v == 'delete') {
                          await _deleteTemplate(t);
                        }
                      },
                      itemBuilder:
                          (_) => const [
                            PopupMenuItem(value: 'open', child: Text('OPEN')),
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('RENAME'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('DELETE'),
                            ),
                          ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
