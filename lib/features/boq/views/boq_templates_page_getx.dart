import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/dialogs/boq_template_target_dialog.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BoqTemplatesPageGetX extends StatefulWidget {
  const BoqTemplatesPageGetX({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<BoqTemplatesPageGetX> createState() => _BoqTemplatesPageGetXState();
}

class _BoqTemplatesPageGetXState extends State<BoqTemplatesPageGetX> {
  late final BoqTemplateController c;
  late final Future<bool> _adminFuture;

  @override
  void initState() {
    super.initState();
    c =
        Get.isRegistered<BoqTemplateController>()
            ? Get.find<BoqTemplateController>()
            : Get.put(BoqTemplateController());
    _adminFuture = c.isCurrentUserAdmin();
  }

  Future<void> _createTemplate({required bool isDefault}) async {
    final nameCtrl = TextEditingController();

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(
          isDefault ? 'Create default template' : 'Create my template',
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'Template name',
            hintText:
                isDefault
                    ? 'e.g. Standard Building Works'
                    : 'e.g. My Building Works Template',
            border: const OutlineInputBorder(),
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
    );

    if (ok != true) {
      nameCtrl.dispose();
      return;
    }

    try {
      final id = await c.createTemplate(nameCtrl.text, isDefault: isDefault);
      Get.snackbar(
        'Template',
        isDefault ? 'Default template created' : 'Personal template created',
        snackPosition: SnackPosition.BOTTOM,
      );

      Get.toNamed(
        AppRoutes.boqTemplateItemsManage,
        arguments: {'templateId': id, 'templateName': nameCtrl.text.trim()},
      );
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _renameTemplate(BoqTemplate t) async {
    final ctrl = TextEditingController(text: t.name);

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Rename template'),
        content: TextField(
          controller: ctrl,
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

    if (ok != true) {
      ctrl.dispose();
      return;
    }

    try {
      await c.renameTemplate(t.id, ctrl.text);
      Get.snackbar('Template', 'Renamed', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _deleteTemplate(BoqTemplate t) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete template?'),
        content: Text('This will delete "${t.name}" and all its items.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await c.deleteTemplate(t.id);
      Get.snackbar('Template', 'Deleted', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _openTemplate(BoqTemplate t) {
    Get.toNamed(
      AppRoutes.boqTemplateItemsManage,
      arguments: {'templateId': t.id, 'templateName': t.name},
    );
  }

  Future<void> _useTemplate(BoqTemplate template) async {
    final target = await showDialog<BoqTemplateTarget>(
      context: context,
      builder:
          (_) => const BoqTemplateTargetDialog(
            title: 'Use this template',
            description:
                'Select a project and building, then choose the BOQ items to add.',
            confirmLabel: 'Continue',
          ),
    );

    if (target == null || !mounted) return;

    Get.toNamed(
      AppRoutes.boqTemplatePickItems,
      arguments: {
        'projectId': target.projectId,
        'buildingId': target.buildingId,
        'templateId': template.id,
        'templateName': template.name,
      },
    );
  }

  Widget _body(BuildContext context, bool isAdmin) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return DefaultTabController(
      length: 2,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 24,
              compact ? 12 : 24,
              compact ? 12 : 24,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TemplateTabs(),
                SizedBox(height: compact ? 12 : 18),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TemplateScopeView(
                        stream: c.defaultTemplatesStream(),
                        isDefault: true,
                        canCreate: isAdmin,
                        emptyText:
                            'No default templates have been uploaded yet.',
                        createLabel: 'New default',
                        lockedMessage:
                            'Only admins can upload, edit, or delete AQS templates. Every plan can use them within its template allowance.',
                        onCreate: () => _createTemplate(isDefault: true),
                        onOpen: _openTemplate,
                        onUse: _useTemplate,
                        onRename: _renameTemplate,
                        onDelete: _deleteTemplate,
                        canEditTemplate: (template) => isAdmin,
                      ),
                      _TemplateScopeView(
                        stream: c.myTemplatesStream(),
                        isDefault: false,
                        canCreate: true,
                        emptyText: 'No personal templates yet.',
                        createLabel: 'New template',
                        lockedMessage:
                            'Your templates are private to your user account and can be used without a paid plan.',
                        onCreate: () => _createTemplate(isDefault: false),
                        onOpen: _openTemplate,
                        onUse: _useTemplate,
                        onRename: _renameTemplate,
                        onDelete: _deleteTemplate,
                        canEditTemplate: (_) => true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminFuture,
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final isAdmin = snap.data == true;
        final body =
            loading
                ? const Center(child: CircularProgressIndicator())
                : _body(context, isAdmin);

        if (!widget.showAppBar) return body;

        return Scaffold(
          appBar: AppBar(title: const Text('BOQ Templates')),
          body: body,
        );
      },
    );
  }
}

class _TemplateScopeView extends StatelessWidget {
  const _TemplateScopeView({
    required this.stream,
    required this.isDefault,
    required this.canCreate,
    required this.emptyText,
    required this.createLabel,
    required this.lockedMessage,
    required this.onCreate,
    required this.onOpen,
    required this.onUse,
    required this.onRename,
    required this.onDelete,
    required this.canEditTemplate,
  });

  final Stream<List<BoqTemplate>> stream;
  final bool isDefault;
  final bool canCreate;
  final String emptyText;
  final String createLabel;
  final String lockedMessage;
  final VoidCallback onCreate;
  final ValueChanged<BoqTemplate> onOpen;
  final ValueChanged<BoqTemplate> onUse;
  final ValueChanged<BoqTemplate> onRename;
  final ValueChanged<BoqTemplate> onDelete;
  final bool Function(BoqTemplate template) canEditTemplate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TemplateScopeHeader(
          isDefault: isDefault,
          canCreate: canCreate,
          createLabel: createLabel,
          lockedMessage: lockedMessage,
          onCreate: onCreate,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<BoqTemplate>>(
            stream: stream,
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final templates = snap.data!;
              if (templates.isEmpty) {
                return _EmptyTemplatesMessage(message: emptyText);
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 28),
                itemCount: templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final t = templates[i];
                  final canEdit = canEditTemplate(t);
                  return _TemplateTile(
                    template: t,
                    canEdit: canEdit,
                    onOpen: () => onOpen(t),
                    onUse: () => onUse(t),
                    onRename: () => onRename(t),
                    onDelete: () => onDelete(t),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateTabs extends StatelessWidget {
  const _TemplateTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF101828).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: AqsColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC7D7FE)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AqsColors.primary,
        unselectedLabelColor: AqsColors.muted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        tabs: const [
          Tab(height: 48, text: 'Default'),
          Tab(height: 48, text: 'My Templates'),
        ],
      ),
    );
  }
}

class _TemplateScopeHeader extends StatelessWidget {
  const _TemplateScopeHeader({
    required this.isDefault,
    required this.canCreate,
    required this.createLabel,
    required this.lockedMessage,
    required this.onCreate,
  });

  final bool isDefault;
  final bool canCreate;
  final String createLabel;
  final String lockedMessage;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final information = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 42 : 46,
              height: compact ? 42 : 46,
              decoration: BoxDecoration(
                color:
                    isDefault ? AqsColors.primarySoft : AqsColors.successSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isDefault ? Icons.verified_outlined : Icons.person_outline,
                color: isDefault ? AqsColors.primary : AqsColors.success,
              ),
            ),
            SizedBox(width: compact ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDefault
                        ? 'Default template library'
                        : 'My template library',
                    style: TextStyle(
                      color: AqsColors.ink,
                      fontSize: compact ? 16 : 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lockedMessage,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final createButton = FilledButton.icon(
          onPressed: canCreate ? onCreate : null,
          icon: Icon(isDefault ? Icons.admin_panel_settings : Icons.add),
          label: Text(createLabel),
        );

        return Container(
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(color: AqsColors.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF101828).withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child:
              compact
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      information,
                      const SizedBox(height: 14),
                      SizedBox(width: double.infinity, child: createButton),
                    ],
                  )
                  : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: information),
                      const SizedBox(width: 12),
                      createButton,
                    ],
                  ),
        );
      },
    );
  }
}

class _EmptyTemplatesMessage extends StatelessWidget {
  const _EmptyTemplatesMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.library_books_outlined,
              color: AqsColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AqsColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.canEdit,
    required this.onOpen,
    required this.onUse,
    required this.onRename,
    required this.onDelete,
  });

  final BoqTemplate template;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onUse;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDefault = template.isDefaultTemplate;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AqsColors.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF101828).withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color:
                      isDefault ? AqsColors.primarySoft : AqsColors.successSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isDefault ? Icons.verified_outlined : Icons.person_outline,
                  color: isDefault ? AqsColors.primary : AqsColors.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name.isEmpty
                          ? 'Untitled template'
                          : template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isDefault
                          ? 'AQS template • Usage depends on your plan allowance'
                          : 'My private template',
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'Template actions',
                onSelected: (value) {
                  if (value == 'use') onUse();
                  if (value == 'open') onOpen();
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'use',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add_check_circle_outlined),
                            SizedBox(width: 12),
                            Text('Use this template'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(value: 'open', child: Text('Open')),
                      if (canEdit) ...[
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
