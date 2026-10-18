import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/build_up_rates/controllers/rate_builder_controller.dart';
import 'package:aqs/features/build_up_rates/controllers/resource_library_controller.dart';
import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/models/rate_units.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class RateComponentSection extends StatelessWidget {
  const RateComponentSection({
    super.key,
    required this.type,
    required this.controller,
    this.priceEntryOnly = false,
  });
  final RateComponentType type;
  final RateBuilderController controller;
  final bool priceEntryOnly;

  Future<void> _pickResource(BuildContext context) async {
    if (!Get.isRegistered<ResourceLibraryController>()) {
      Get.put(ResourceLibraryController());
    }
    final library = Get.find<ResourceLibraryController>();
    await library.load();
    final resources =
        library.resources.where((item) => item.category == type).toList();
    if (!context.mounted) return;
    if (resources.isEmpty) {
      Get.snackbar(
        'No saved resources',
        'Add ${type.label.toLowerCase()} in the Resource Library first.',
      );
      return;
    }
    final resource = await showDialog<RateResource>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: Text('Select ${type.label} Resource'),
            children:
                resources
                    .map(
                      (item) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, item),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.unit} • ${item.currency} ${item.currentRate.toStringAsFixed(2)}',
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
    );
    if (resource == null) return;
    controller.components.add(
      RateComponent(
        componentId: const Uuid().v4(),
        type: type,
        name: resource.name,
        unit: resource.unit,
        quantity: 1,
        unitRate: resource.currentRate,
        sortOrder: controller.components.length,
      ),
    );
  }

  Future<void> _createResourceAndUse(BuildContext context) async {
    if (!Get.isRegistered<ResourceLibraryController>()) {
      Get.put(ResourceLibraryController());
    }
    final library = Get.find<ResourceLibraryController>();
    final name = TextEditingController();
    var selectedUnit = RateUnits.defaultFor(type);
    final rate = TextEditingController();
    final notes = TextEditingController();

    final resource = await showDialog<RateResource>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: Text('Create ${type.label} Resource'),
                  content: SizedBox(
                    width: 460,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: name,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Resource name *',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit *',
                                ),
                                items:
                                    RateUnits.all
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: rate,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Unit rate *',
                                  prefixText: 'TZS ',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notes,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final resourceName = name.text.trim();
                        final unitRate = double.tryParse(rate.text.trim());
                        if (resourceName.isEmpty ||
                            unitRate == null ||
                            unitRate < 0) {
                          Get.snackbar(
                            'Check resource details',
                            'Enter a name, unit and valid unit rate.',
                          );
                          return;
                        }
                        Navigator.pop(
                          dialogContext,
                          RateResource(
                            resourceId: '',
                            name: resourceName,
                            category: type,
                            unit: selectedUnit,
                            currentRate: unitRate,
                            currency: controller.currency.value,
                            notes: notes.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Create & Use'),
                    ),
                  ],
                ),
          ),
    );

    name.dispose();
    rate.dispose();
    notes.dispose();
    if (resource == null) return;

    await library.save(resource);
    controller.components.add(
      RateComponent(
        componentId: const Uuid().v4(),
        type: type,
        name: resource.name,
        unit: resource.unit,
        quantity: 1,
        unitRate: resource.currentRate,
        sortOrder: controller.components.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showWaste =
        type == RateComponentType.material || type == RateComponentType.other;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!priceEntryOnly)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _pickResource(context),
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('From Library'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _createResourceAndUse(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create Resource'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Obx(() {
            final rows = controller.componentsOf(type).toList(growable: false);
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No components added.',
                    style: TextStyle(color: AqsColors.muted),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final row in rows)
                  _ComponentEditor(
                    key: ValueKey(row.componentId),
                    component: row,
                    showWaste: showWaste,
                    priceEntryOnly: priceEntryOnly,
                    onChanged: controller.updateComponent,
                    onDelete: () => controller.removeComponent(row.componentId),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor({
    super.key,
    required this.component,
    required this.showWaste,
    required this.priceEntryOnly,
    required this.onChanged,
    required this.onDelete,
  });
  final RateComponent component;
  final bool showWaste;
  final bool priceEntryOnly;
  final ValueChanged<RateComponent> onChanged;
  final VoidCallback onDelete;
  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> {
  late final TextEditingController name, qty, rate, waste;
  late String selectedUnit;
  @override
  void initState() {
    super.initState();
    final c = widget.component;
    name = TextEditingController(text: c.name);
    selectedUnit = c.unit;
    qty = TextEditingController(text: '${c.quantity}');
    rate = TextEditingController(text: '${c.unitRate}');
    waste = TextEditingController(text: '${c.wastePercent}');
  }

  @override
  void dispose() {
    name.dispose();
    qty.dispose();
    rate.dispose();
    waste.dispose();
    super.dispose();
  }

  void update() {
    final c = widget.component.copyWith(
      name: name.text,
      unit: selectedUnit,
      quantity: double.tryParse(qty.text) ?? 0,
      unitRate: double.tryParse(rate.text) ?? 0,
      wastePercent: double.tryParse(waste.text) ?? 0,
    );
    widget.onChanged(c);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AqsColors.border)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        if (widget.priceEntryOnly) {
          final amount =
              widget.component
                  .copyWith(unitRate: double.tryParse(rate.text) ?? 0)
                  .amount;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.component.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${NumberFormat('0.####').format(widget.component.quantity)} ${widget.component.unit}${widget.component.wastePercent > 0 ? ' + ${NumberFormat('0.##').format(widget.component.wastePercent)}% waste' : ''}',
                  style: const TextStyle(color: AqsColors.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rate,
                  onChanged: (_) => update(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit price',
                    prefixText: 'TZS ',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Amount: TZS ${NumberFormat('#,##0.00').format(amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.component.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NumberFormat('0.####').format(widget.component.quantity)} ${widget.component.unit}${widget.component.wastePercent > 0 ? ' + ${NumberFormat('0.##').format(widget.component.wastePercent)}% waste' : ''}',
                      style: const TextStyle(color: AqsColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: rate,
                  onChanged: (_) => update(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit price',
                    prefixText: 'TZS ',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Text(
                  NumberFormat('#,##0.00').format(amount),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        }
        final fields = [
          Expanded(
            flex: 3,
            child: TextField(
              controller: name,
              onChanged: (_) => update(),
              decoration: const InputDecoration(
                labelText: 'Resource',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFD0D5DD)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedUnit,
                  isExpanded: true,
                  hint: const Text('Unit'),
                  onChanged: (value) {
                    selectedUnit = value ?? selectedUnit;
                    update();
                  },
                  items:
                      RateUnits.including(selectedUnit)
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: qty,
              onChanged: (_) => update(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: rate,
              onChanged: (_) => update(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Unit Rate',
                isDense: true,
              ),
            ),
          ),
          if (widget.showWaste)
            Expanded(
              child: TextField(
                controller: waste,
                onChanged: (_) => update(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Waste %',
                  isDense: true,
                ),
              ),
            ),
        ];
        return Column(
          children: [
            if (narrow)
              ...fields.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [item]),
                ),
              )
            else
              Row(
                children:
                    fields
                        .expand((item) => [item, const SizedBox(width: 8)])
                        .toList()
                      ..removeLast(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Amount: ${NumberFormat('#,##0.00').format(widget.component.copyWith(quantity: double.tryParse(qty.text) ?? 0, unitRate: double.tryParse(rate.text) ?? 0, wastePercent: double.tryParse(waste.text) ?? 0).amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AqsColors.text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete component',
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFD92D20),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
