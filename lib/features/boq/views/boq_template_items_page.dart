import 'dart:typed_data';

import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/controllers/boq_template_controller.dart';
import 'package:aqs/features/boq/controllers/boq_template_pick_controller.dart';
import 'package:aqs/features/boq/dialogs/boq_template_target_dialog.dart';
import 'package:aqs/features/boq/models/boq_template.dart';
import 'package:aqs/features/utils/helpers/boq_helpers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BoqTemplateItemsPage extends StatefulWidget {
  final String templateId;
  final String templateName;

  BoqTemplateItemsPage({
    super.key,
    required this.templateId,
    required this.templateName,
  });

  @override
  State<BoqTemplateItemsPage> createState() => _BoqTemplateItemsPageState();
}

class _BoqTemplateItemsPageState extends State<BoqTemplateItemsPage> {
  late final BoqTemplateController c;
  late final Future<BoqTemplate?> _templateFuture;
  late final Future<bool> _canEditFuture;
  // final c = Get.find<BoqTemplateController>();

  final _vCtrl = ScrollController();
  final _hCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    c =
        Get.isRegistered<BoqTemplateController>()
            ? Get.find<BoqTemplateController>()
            : Get.put(BoqTemplateController());
    _templateFuture = c.getTemplate(widget.templateId);
    _canEditFuture = _loadCanEdit();
  }

  Future<bool> _loadCanEdit() async {
    final template = await c.getTemplate(widget.templateId);
    if (template == null) return false;
    return c.canEditTemplate(template);
  }

  Future<bool> _ensureCanEdit() async {
    final canEdit = await _canEditFuture;
    if (!canEdit) {
      Get.snackbar(
        'Template',
        'You can preview this template, but you cannot edit it.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return canEdit;
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _importExcel() async {
    final canEdit = await _ensureCanEdit();
    if (!canEdit) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true, // IMPORTANT for web
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      Get.snackbar('Import', 'Could not read file bytes');
      return;
    }

    final clearExisting = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Import BOQ template'),
        content: const Text(
          'Replace the current template rows, or add this workbook below them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Add rows'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Replace existing'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (clearExisting == null) return;

    try {
      final n = await c.importExcelBytes(
        widget.templateId,
        bytes,
        clearExisting: clearExisting,
      );
      Get.snackbar(
        'Import',
        'Imported $n items',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Import', 'Failed: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addOrEdit({BoqTemplateItem? item}) async {
    final canEdit = await _ensureCanEdit();
    if (!canEdit) return;
    final isEdit = item != null;

    final codeC = TextEditingController(text: item?.boqCode ?? '');
    final descC = TextEditingController(text: item?.description ?? '');
    final unitC = TextEditingController(text: item?.unit ?? '');
    void disposeFields() {
      codeC.dispose();
      descC.dispose();
      unitC.dispose();
    }

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(isEdit ? 'Edit Template Item' : 'Add Template Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeC,
                decoration: const InputDecoration(
                  labelText: 'BOQ Code',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 3.7(i)(A)(i)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descC,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitC,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                  hintText: 'm, m2, m3, kg, item...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) {
      disposeFields();
      return;
    }

    final code = codeC.text.trim();
    final desc = descC.text.trim();
    final unit = unitC.text.trim();

    if (code.isEmpty || desc.isEmpty) {
      disposeFields();
      Get.snackbar('Save', 'BOQ code and description are required.');
      return;
    }

    try {
      if (isEdit) {
        await c.updateItem(
          widget.templateId,
          item.id,
          boqCode: code,
          description: desc,
          unit: unit,
        );
      } else {
        await c.addItem(
          widget.templateId,
          boqCode: code,
          description: desc,
          unit: unit,
        );
      }
    } finally {
      disposeFields();
    }
  }

  Future<void> _connectTemplate(BoqTemplate? template) async {
    if (template == null || _isConnecting) return;

    try {
      await c.assertCanUseTemplate(widget.templateId);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        'Cannot connect template',
        error.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (!mounted) return;
    final target = await showDialog<BoqTemplateTarget>(
      context: context,
      builder: (_) => const BoqTemplateTargetDialog(),
    );
    if (target == null || !mounted) return;

    setState(() => _isConnecting = true);
    try {
      final snapshot =
          await c.itemsRef(widget.templateId).orderBy('order').get();
      final items =
          snapshot.docs
              .map(BoqTemplateItem.fromDoc)
              .where((item) => item.rowType.toLowerCase() == 'item')
              .toList();
      if (items.isEmpty) {
        throw StateError('This template has no BOQ items to connect.');
      }

      final connector = BoqTemplatePickController(
        projectId: target.projectId,
        buildingId: target.buildingId,
        templateId: widget.templateId,
        templateName: widget.templateName,
      );
      final added = await connector.addSelectedToProjectBoq(items);

      if (!mounted) return;
      setState(() => _isConnecting = false);
      final openBoq = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('BOQ connected'),
              content: Text(
                '${widget.templateName} has been connected to '
                '${target.projectName} — ${target.buildingName}.\n\n'
                '$added BOQ items were added successfully.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('OK'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open project BOQ'),
                ),
              ],
            ),
      );

      if (openBoq == true) {
        Get.toNamed(
          AppRoutes.projectBuildingWorkspacePath(
            projectId: target.projectId,
            buildingId: target.buildingId,
            projectName: target.projectName,
            buildingName: target.buildingName,
            buildingCode: target.buildingCode,
            tab: 1,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      Get.snackbar(
        'Connection failed',
        error.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  // final _vCtrl = ScrollController();
  // final _hCtrl = ScrollController();
  static const double headerHeight = 44;
  String _s(dynamic v) => (v ?? '').toString().trim();

  String _rowType(dynamic v) {
    final t = _s(v).toLowerCase();
    if (t == 'bill' || t == 'subheading' || t == 'minor' || t == 'item') {
      return t;
    }
    return 'item';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        title: Text(
          widget.templateName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<List<Object?>>(
        future: Future.wait<Object?>([_templateFuture, _canEditFuture]),
        builder: (context, accessSnap) {
          if (!accessSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final template = accessSnap.data![0] as BoqTemplate?;
          final canEdit = accessSnap.data![1] as bool;

          return ColoredBox(
            color: AqsColors.canvas,
            child: Column(
              children: [
                _templateHeader(template: template, canEdit: canEdit),
                Expanded(
                  child: StreamBuilder<List<BoqTemplateItem>>(
                    stream: c.itemsStream(widget.templateId),
                    builder: (ctx, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final items = snap.data!;
                      final allRows = items.map((item) => item.raw).toList();
                      final isCivilTemplate =
                          (template?.name ?? '').toLowerCase().contains(
                            'civil',
                          ) ||
                          items.any(
                            (item) =>
                                _s(item.raw['boqWorkType']).toLowerCase() ==
                                    'civil' ||
                                _s(item.raw['sectionType']).toLowerCase() ==
                                    'series',
                          );
                      String visibleCode(BoqTemplateItem item) {
                        final type = _rowType(item.rowType);
                        if (type == 'item' ||
                            (isCivilTemplate && type == 'minor')) {
                          final resolved = hierarchicalBoqCodeFromRows(
                            item.raw,
                            allRows,
                          );
                          if (resolved.isNotEmpty) return resolved;
                        }
                        return _s(item.boqCode);
                      }

                      final query = _searchQuery.toLowerCase().trim();
                      final visibleItems =
                          query.isEmpty
                              ? items
                              : items.where((it) {
                                final haystack =
                                    '${visibleCode(it)} ${it.boqCode} ${it.description} ${it.unit} ${it.rowType}'
                                        .toLowerCase();
                                return haystack.contains(query);
                              }).toList();
                      final itemCount =
                          items
                              .where((it) => _rowType(it.rowType) == 'item')
                              .length;
                      final headingCount = items.length - itemCount;

                      return Column(
                        children: [
                          _templateStatsStrip(
                            rowCount: items.length,
                            itemCount: itemCount,
                            headingCount: headingCount,
                          ),
                          Expanded(
                            child:
                                visibleItems.isEmpty
                                    ? _emptyState(
                                      title:
                                          items.isEmpty
                                              ? 'No template items'
                                              : 'No matching template items',
                                      subtitle:
                                          items.isEmpty
                                              ? canEdit
                                                  ? 'Import an Excel BOQ or add items one by one.'
                                                  : 'This template has no saved items yet.'
                                              : 'Try a different BOQ code, description, heading, or unit.',
                                      actionLabel:
                                          items.isEmpty && canEdit
                                              ? 'Import Excel'
                                              : 'Clear search',
                                      onAction: () {
                                        if (items.isEmpty && canEdit) {
                                          _importExcel();
                                        } else {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        }
                                      },
                                    )
                                    : Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        MediaQuery.sizeOf(context).width < 680
                                            ? 12
                                            : 20,
                                        0,
                                        MediaQuery.sizeOf(context).width < 680
                                            ? 12
                                            : 20,
                                        20,
                                      ),
                                      child: Card(
                                        clipBehavior: Clip.antiAlias,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final availableW =
                                                constraints.maxWidth;
                                            const tableW = _TplCols.total;
                                            final minW =
                                                tableW < availableW
                                                    ? availableW
                                                    : tableW;

                                            return Scrollbar(
                                              controller: _hCtrl,
                                              thumbVisibility: true,
                                              notificationPredicate:
                                                  (n) =>
                                                      n.metrics.axis ==
                                                      Axis.horizontal,
                                              child: SingleChildScrollView(
                                                controller: _hCtrl,
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: SizedBox(
                                                  width: minW,
                                                  height: constraints.maxHeight,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: SizedBox(
                                                      width: tableW,
                                                      child: Column(
                                                        children: [
                                                          SizedBox(
                                                            height:
                                                                headerHeight,
                                                            child: _headerRow(
                                                              canEdit: canEdit,
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Scrollbar(
                                                              controller:
                                                                  _vCtrl,
                                                              thumbVisibility:
                                                                  true,
                                                              child: ListView.builder(
                                                                controller:
                                                                    _vCtrl,
                                                                itemCount:
                                                                    visibleItems
                                                                        .length,
                                                                itemBuilder: (
                                                                  ctx,
                                                                  i,
                                                                ) {
                                                                  final it =
                                                                      visibleItems[i];
                                                                  final code =
                                                                      visibleCode(
                                                                        it,
                                                                      );
                                                                  final desc = _s(
                                                                    it.description,
                                                                  );
                                                                  final unit =
                                                                      _s(
                                                                        it.unit,
                                                                      );
                                                                  final type =
                                                                      _rowType(
                                                                        it.rowType,
                                                                      );

                                                                  if (code.isEmpty &&
                                                                      desc.isEmpty) {
                                                                    return const SizedBox.shrink();
                                                                  }

                                                                  if (type ==
                                                                      'bill') {
                                                                    final billCode =
                                                                        isCivilTemplate
                                                                            ? _s(
                                                                              it.boqCode,
                                                                            )
                                                                            : '';
                                                                    var billDescription =
                                                                        desc;
                                                                    if (billCode
                                                                            .isNotEmpty &&
                                                                        billDescription
                                                                            .toUpperCase()
                                                                            .startsWith(
                                                                              billCode.toUpperCase(),
                                                                            )) {
                                                                      billDescription = billDescription
                                                                          .substring(
                                                                            billCode.length,
                                                                          )
                                                                          .replaceFirst(
                                                                            RegExp(
                                                                              r'^\s*[-:]\s*',
                                                                            ),
                                                                            '',
                                                                          );
                                                                    }
                                                                    return _billRow(
                                                                      billDescription,
                                                                      leftCode:
                                                                          billCode,
                                                                    );
                                                                  }
                                                                  if (type ==
                                                                      'subheading') {
                                                                    return _subheadingRow(
                                                                      code,
                                                                      desc,
                                                                    );
                                                                  }
                                                                  if (type ==
                                                                      'minor') {
                                                                    return _minorRow(
                                                                      code,
                                                                      desc,
                                                                    );
                                                                  }

                                                                  return _itemRow(
                                                                    code: code,
                                                                    desc: desc,
                                                                    unit: unit,
                                                                    rowType:
                                                                        'item',
                                                                    canEdit:
                                                                        canEdit,
                                                                    onEdit:
                                                                        canEdit
                                                                            ? () => _addOrEdit(
                                                                              item:
                                                                                  it,
                                                                            )
                                                                            : null,
                                                                    onDelete:
                                                                        canEdit
                                                                            ? () => c.deleteItem(
                                                                              widget.templateId,
                                                                              it.id,
                                                                            )
                                                                            : null,
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _templateHeader({
    required BoqTemplate? template,
    required bool canEdit,
  }) {
    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final mobile = pageConstraints.maxWidth < 680;
        return Container(
          margin: EdgeInsets.fromLTRB(
            mobile ? 12 : 20,
            mobile ? 12 : 20,
            mobile ? 12 : 20,
            mobile ? 10 : 14,
          ),
          padding: EdgeInsets.all(mobile ? 14 : 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AqsColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F101828),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
          final title = Row(
            children: [
              Container(
                width: mobile ? 44 : 48,
                height: mobile ? 44 : 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AqsColors.primaryDark, AqsColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOQ Template',
                      style: TextStyle(
                        color: AqsColors.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.templateName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

              final connectButton = FilledButton.icon(
                onPressed:
                    _isConnecting ? null : () => _connectTemplate(template),
                icon:
                    _isConnecting
                        ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.link_rounded, size: 19),
                label: Text(
                  _isConnecting ? 'Connecting…' : 'Connect to project',
                ),
              );
              final editActions = <Widget>[
                OutlinedButton.icon(
                  onPressed: _importExcel,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Import Excel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addOrEdit(),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Add item'),
                ),
              ];
              final actions =
                  mobile
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          connectButton,
                          if (canEdit) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: editActions[0]),
                                const SizedBox(width: 8),
                                Expanded(child: editActions[1]),
                              ],
                            ),
                          ],
                        ],
                      )
                      : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          connectButton,
                          if (canEdit) ...editActions,
                        ],
                      );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                title,
                const SizedBox(height: 16),
                mobile
                    ? actions
                    : Align(alignment: Alignment.centerLeft, child: actions),
              ] else
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    actions,
                  ],
                ),
              const SizedBox(height: 12),
              _TemplateExcelHint(
                isCivil: (template?.name ?? '').toLowerCase().contains('civil'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search BOQ code, description, heading or unit...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon:
                      _searchQuery.isEmpty
                          ? null
                          : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                ),
              ),
            ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _templateStatsStrip({
    required int rowCount,
    required int itemCount,
    required int headingCount,
  }) {
    final mobile = MediaQuery.sizeOf(context).width < 680;
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 20, 0, mobile ? 12 : 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final cards = [
            _statCard(
              icon: Icons.table_rows_rounded,
              label: 'Template rows',
              value: '$rowCount',
              color: AqsColors.primary,
              background: AqsColors.primarySoft,
            ),
            _statCard(
              icon: Icons.list_alt_rounded,
              label: 'BOQ items',
              value: '$itemCount',
              color: const Color(0xFF027A48),
              background: AqsColors.successSoft,
            ),
            _statCard(
              icon: Icons.segment_rounded,
              label: 'Headings',
              value: '$headingCount',
              color: const Color(0xFFB54708),
              background: const Color(0xFFFFFAEB),
            ),
          ];

          if (compact) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AqsColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _compactStat(
                      value: '$rowCount',
                      label: 'Rows',
                      color: AqsColors.primary,
                    ),
                  ),
                  const _MetricDivider(),
                  Expanded(
                    child: _compactStat(
                      value: '$itemCount',
                      label: 'Items',
                      color: const Color(0xFF027A48),
                    ),
                  ),
                  const _MetricDivider(),
                  Expanded(
                    child: _compactStat(
                      value: '$headingCount',
                      label: 'Headings',
                      color: const Color(0xFFB54708),
                    ),
                  ),
                ],
              ),
            );
          }

          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
              const SizedBox(width: 10),
              Expanded(child: cards[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _compactStat({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AqsColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AqsColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AqsColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AqsColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AqsColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AqsColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AqsColors.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(
                actionLabel.toLowerCase().contains('clear')
                    ? Icons.close_rounded
                    : Icons.upload_file_rounded,
              ),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  // static const double _headerH = 44;

  // double get _spanRest => _TplCols.wDesc + _TplCols.wUnit + _TplCols.wAct;

  Widget _billRow(String text, {String leftCode = ''}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF315A96))),
      ),
      width: _TplCols.total,
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _TplCols.wCode,
            fw: FontWeight.w900,
            center: true,
            wrap: true,
            textColor: Colors.white,
          ),
          _cell(
            text.toUpperCase(),
            width: _TplCols.spanRest,
            fw: FontWeight.w900,
            center: true,
            wrap: true,
            textColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _subheadingRow(String leftCode, String text) {
    return Container(
      decoration: const BoxDecoration(
        color: AqsColors.primarySoft,
        border: Border(bottom: BorderSide(color: Color(0xFFBFD2FA))),
      ),
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _TplCols.wCode,
            fw: FontWeight.w900,
            center: true,
            textColor: AqsColors.primaryDark,
          ),
          _cell(
            text.toUpperCase(),
            width: _TplCols.spanRest,
            fw: FontWeight.w900,
            wrap: true,
            textColor: AqsColors.primaryDark,
          ),
        ],
      ),
    );
  }

  Widget _minorRow(String leftCode, String text) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        children: [
          _cell(
            leftCode,
            width: _TplCols.wCode,
            fw: FontWeight.w800,
            center: true,
            textColor: AqsColors.text,
          ),
          _cell(
            text.toUpperCase(),
            width: _TplCols.spanRest,
            fw: FontWeight.w800,
            wrap: true,
            textColor: AqsColors.text,
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required double width,
    FontWeight fw = FontWeight.w400,
    bool right = false,
    bool center = false,
    double fontSize = 13,
    EdgeInsets pad = const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    Color? bg,
    Color? textColor,
    bool wrap = false,
  }) {
    TextAlign align = TextAlign.left;
    if (right) align = TextAlign.right;
    if (center) align = TextAlign.center;

    return Container(
      width: width,
      padding: pad,

      // ✅ ONLY bottom border here
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        color: bg,
      ),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: textColor ?? AqsColors.text,
          fontWeight: fw,
          fontSize: fontSize,
        ),
        softWrap: true,
        overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
        maxLines: wrap ? null : 2,
      ),
    );
  }

  Widget _headerRow({required bool canEdit}) {
    return SizedBox(
      width: _TplCols.total,
      child: Container(
        decoration: const BoxDecoration(
          color: AqsColors.primaryDark,
          border: Border(bottom: BorderSide(color: AqsColors.primaryDark)),
        ),
        child: Row(
          children: [
            _cell(
              'BOQ CODE',
              width: _TplCols.wCode,
              fw: FontWeight.w800,
              center: true,
              textColor: Colors.white,
            ),
            _cell(
              'DESCRIPTION',
              width: _TplCols.wDesc,
              fw: FontWeight.w800,
              textColor: Colors.white,
            ),
            _cell(
              'UNIT',
              width: _TplCols.wUnit,
              fw: FontWeight.w800,
              center: true,
              textColor: Colors.white,
            ),
            _cell(
              canEdit ? 'ACTIONS' : 'PREVIEW',
              width: _TplCols.wAct,
              fw: FontWeight.w800,
              center: true,
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  // Widget _vSep() => Container(
  //   width: _TplCols.sep,
  //   height: double.infinity,
  //   color: Colors.grey.shade300,
  // );

  // Widget _vSep() =>
  //     Container(width: 1, height: double.infinity, color: Colors.grey.shade300);

  Widget _itemRow({
    required String code,
    required String desc,
    required String unit,
    required String rowType,
    required bool canEdit,
    required VoidCallback? onEdit,
    required VoidCallback? onDelete,
  }) {
    final actionsEnabled = rowType == 'item' && canEdit;

    Color? bg;
    FontWeight fw = FontWeight.w400;
    double fontSize = 13;

    if (rowType == 'bill') {
      bg = Colors.grey.shade200;
      fw = FontWeight.w900;
      fontSize = 14;
    } else if (rowType == 'subheading' || rowType == 'minor') {
      bg = Colors.grey.shade50;
      fw = FontWeight.w800;
      fontSize = 14;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cell(
            code,
            width: _TplCols.wCode,
            fw: FontWeight.w800,
            bg: bg,
            center: true,
            fontSize: fontSize,
            textColor: AqsColors.primary,
          ),
          _cell(
            desc,
            width: _TplCols.wDesc,
            fw: fw,
            bg: bg,
            fontSize: fontSize,
            wrap: true,
          ),
          _cell(
            unit,
            width: _TplCols.wUnit,
            fw: FontWeight.w700,
            bg: bg,
            center: true,
            fontSize: fontSize,
            textColor: AqsColors.muted,
          ),
          _actionsCell(
            enabled: actionsEnabled,
            bg: bg,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _actionsCell({
    required bool enabled,
    required VoidCallback? onEdit,
    required VoidCallback? onDelete,
    Color? bg,
  }) {
    return Container(
      width: _TplCols.wAct,
      alignment: Alignment.center,
      color: bg,
      child:
          enabled
              ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AqsColors.primary,
                    ),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Color(0xFFD92D20),
                    ),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              )
              : const SizedBox.shrink(),
    );
  }

  // Widget onEditItem(BoqTemplateItem it) {}
}

class _TemplateExcelHint extends StatelessWidget {
  const _TemplateExcelHint({required this.isCivil});

  final bool isCivil;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1E0FF)),
      ),
      child: Text(
        isCivil
            ? 'Excel: BOQ Code, Description and Unit; Rate is optional. Use SERIES and Section rows for headings. AQS builds the full Civil Works item code.'
            : 'Excel: BOQ Code, Description and Unit; Rate is optional. Leave Unit blank for headings and provide a Unit for measurable BOQ items.',
        style: const TextStyle(
          color: AqsColors.primary,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 38,
      child: VerticalDivider(width: 12, color: AqsColors.border),
    );
  }
}

class _TplCols {
  static const double wCode = 90;
  static const double wDesc = 680;
  static const double wUnit = 120;
  static const double wAct = 120;

  static const double total = wCode + wDesc + wUnit + wAct;
  static const double spanRest = wDesc + wUnit + wAct;
}
