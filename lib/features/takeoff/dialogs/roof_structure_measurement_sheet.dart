import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/widgets/boq_picker_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

Future<bool> showRoofStructureMeasurementSheet({
  required BuildContext context,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required String drawingTitle,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => _RoofStructureMeasurementDialog(
              projectId: projectId,
              buildingId: buildingId,
              drawingId: drawingId,
              drawingTitle: drawingTitle,
              measurementsRef: measurementsRef,
            ),
      ) ??
      false;
}

class _RoofStructureMeasurementDialog extends StatefulWidget {
  const _RoofStructureMeasurementDialog({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.drawingTitle,
    required this.measurementsRef,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;
  final String drawingTitle;
  final CollectionReference<Map<String, dynamic>> measurementsRef;

  @override
  State<_RoofStructureMeasurementDialog> createState() =>
      _RoofStructureMeasurementDialogState();
}

class _RoofStructureMeasurementDialogState
    extends State<_RoofStructureMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sheetNameCtrl = TextEditingController(text: 'Truss T1');
  final _trussCountCtrl = TextEditingController(text: '9');
  final _factorCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController(
    text: '24.000 m span; CHS S275; 12 mm fillet welds.',
  );

  late final List<_RoofSheetRow> _rows = [
    _RoofSheetRow.weight(
      label: 'Upper chord',
      section: '168.3 × 8 CHS, S275',
      kgPerM: 31.6,
    ),
    _RoofSheetRow.weight(
      label: 'Lower chord',
      section: '168.3 × 8 CHS, S275',
      kgPerM: 31.6,
    ),
    _RoofSheetRow.weight(
      label: 'Main verticals and diagonal webs',
      section: '168.3 × 8 CHS, S275',
      kgPerM: 31.6,
    ),
    _RoofSheetRow.weight(
      label: 'Secondary diagonal webs',
      section: '76.1 × 3 CHS, S275',
      kgPerM: 5.41,
    ),
    _RoofSheetRow.count(
      label: 'Cleats at unique truss joints',
      section: 'Enter total cleats per truss after shared-joint adjustment',
      quantity: 0,
    ),
    _RoofSheetRow.count(
      label: 'Connection bolts at unique joints',
      section: 'Bolts complete with nuts and washers',
      quantity: 0,
    ),
    _RoofSheetRow.count(
      label: 'Gusset / connection plates',
      section: 'Enter total plates per truss at unique joints',
      quantity: 0,
    ),
    _RoofSheetRow.count(
      label: 'Base plates at supports',
      section: 'Normally one plate at each truss bearing',
      quantity: 2,
    ),
    _RoofSheetRow.count(
      label: 'Anchor / holding-down bolts',
      section: 'Enter bolts per support × number of supports',
      quantity: 8,
    ),
    _RoofSheetRow.length(
      label: 'Fillet welds',
      section: '12 mm fillet weld',
    ),
  ];

  bool _saving = false;
  String? _error;

  int get _trussCount => int.tryParse(_trussCountCtrl.text.trim()) ?? 0;
  double get _factor => double.tryParse(_factorCtrl.text.trim()) ?? 0;

  @override
  void dispose() {
    _sheetNameCtrl.dispose();
    _trussCountCtrl.dispose();
    _factorCtrl.dispose();
    _notesCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBoq(_RoofSheetRow row) async {
    final pick = await showDialog<BoqPick>(
      context: context,
      builder:
          (_) => BoqPickerDialog(
            projectId: widget.projectId,
            buildingId: widget.buildingId,
          ),
    );
    if (pick != null && mounted) {
      setState(() {
        row.boq = pick;
        _error = null;
      });
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(
        _RoofSheetRow.weight(
          label: 'New roof structure item',
          section: '',
          kgPerM: 0,
        ),
      );
    });
  }

  void _removeRow(_RoofSheetRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one measurement row.');
      return;
    }

    final missingBoq = _rows.where((row) => row.boq == null).toList();
    if (missingBoq.isNotEmpty) {
      setState(
        () =>
            _error =
                'Select a BOQ item for every row. Missing: '
                '${missingBoq.map((row) => row.labelCtrl.text.trim()).join(', ')}.',
      );
      return;
    }

    final invalid = _rows.where(
      (row) =>
          row.calculatedValue(
            trussCount: _trussCount,
            factor: _factor,
          ) <=
          0,
    );
    if (invalid.isNotEmpty) {
      setState(() => _error = 'Enter a quantity for every row before saving.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final groupId = widget.measurementsRef.doc().id;
      final now = FieldValue.serverTimestamp();

      for (var index = 0; index < _rows.length; index++) {
        final row = _rows[index];
        final boq = row.boq!;
        final value = row.calculatedValue(
          trussCount: _trussCount,
          factor: _factor,
        );

        batch.set(widget.measurementsRef.doc('$groupId-${index + 1}'), {
          'projectId': widget.projectId,
          'buildingId': widget.buildingId,
          'drawingId': widget.drawingId,
          'drawingTitle': widget.drawingTitle,
          'measureType': 'roofStructureSheet',
          'type': row.type,
          'roofStructureGroupId': groupId,
          'sheetName': _sheetNameCtrl.text.trim(),
          'label': row.labelCtrl.text.trim(),
          'section': row.sectionCtrl.text.trim(),
          'basis': row.basis.name,
          'quantityPerTruss': row.quantity,
          'trussCount': _trussCount,
          'multiplyingFactor': _factor,
          if (row.basis == _RoofMeasureBasis.weight)
            'kgPerM': row.kgPerM,
          'unit': row.unit,
          'value': value,
          'boqItemId': boq.id,
          'boqCode': boq.code,
          'boqDescription': boq.description,
          'notes': _notesCtrl.text.trim(),
          'createdAt': now,
          'updatedAt': now,
        });
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_sheetNameCtrl.text.trim()} measurement sheet saved.',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save roof measurement sheet: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 820),
        child: Column(
          children: [
            _DialogHeader(
              onClose: _saving ? null : () => Navigator.pop(context),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetDetails(
                        sheetNameCtrl: _sheetNameCtrl,
                        trussCountCtrl: _trussCountCtrl,
                        factorCtrl: _factorCtrl,
                        notesCtrl: _notesCtrl,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Measurement schedule',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'One truss session can produce member, unique-joint and support BOQ quantities. Avoid counting a shared joint twice.',
                                  style: TextStyle(color: AqsColors.muted),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _addRow,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add item'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < _rows.length; index++) ...[
                        _RoofRowCard(
                          index: index,
                          row: _rows[index],
                          trussCount: _trussCount,
                          factor: _factor,
                          enabled: !_saving,
                          onChanged: () => setState(() => _error = null),
                          onPickBoq: () => _pickBoq(_rows[index]),
                          onRemove: () => _removeRow(_rows[index]),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFECDCA),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _DialogActions(
              saving: _saving,
              onCancel: () => Navigator.pop(context),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }
}

enum _RoofMeasureBasis { weight, length, count }

class _RoofSheetRow {
  _RoofSheetRow({
    required String label,
    required String section,
    required this.basis,
    required double quantity,
    required double kgPerM,
  }) : labelCtrl = TextEditingController(text: label),
       sectionCtrl = TextEditingController(text: section),
       quantityCtrl = TextEditingController(
         text: quantity > 0 ? _numberText(quantity) : '',
       ),
       kgPerMCtrl = TextEditingController(
         text: kgPerM > 0 ? _numberText(kgPerM) : '',
       );

  factory _RoofSheetRow.weight({
    required String label,
    required String section,
    required double kgPerM,
  }) => _RoofSheetRow(
    label: label,
    section: section,
    basis: _RoofMeasureBasis.weight,
    quantity: 0,
    kgPerM: kgPerM,
  );

  factory _RoofSheetRow.length({
    required String label,
    required String section,
  }) => _RoofSheetRow(
    label: label,
    section: section,
    basis: _RoofMeasureBasis.length,
    quantity: 0,
    kgPerM: 0,
  );

  factory _RoofSheetRow.count({
    required String label,
    required String section,
    required double quantity,
  }) => _RoofSheetRow(
    label: label,
    section: section,
    basis: _RoofMeasureBasis.count,
    quantity: quantity,
    kgPerM: 0,
  );

  final TextEditingController labelCtrl;
  final TextEditingController sectionCtrl;
  final TextEditingController quantityCtrl;
  final TextEditingController kgPerMCtrl;
  _RoofMeasureBasis basis;
  BoqPick? boq;

  double get quantity => double.tryParse(quantityCtrl.text.trim()) ?? 0;
  double get kgPerM => double.tryParse(kgPerMCtrl.text.trim()) ?? 0;

  String get type => switch (basis) {
    _RoofMeasureBasis.weight => 'roofStructureSteel',
    _RoofMeasureBasis.length => 'roofStructureLength',
    _RoofMeasureBasis.count => 'roofStructureCount',
  };

  String get unit => switch (basis) {
    _RoofMeasureBasis.weight => 'kg',
    _RoofMeasureBasis.length => 'm',
    _RoofMeasureBasis.count => 'nr',
  };

  double calculatedValue({required int trussCount, required double factor}) {
    final multiplier = trussCount * factor;
    return switch (basis) {
      _RoofMeasureBasis.weight => quantity * kgPerM * multiplier,
      _RoofMeasureBasis.length => quantity * multiplier,
      _RoofMeasureBasis.count => quantity * multiplier,
    };
  }

  void dispose() {
    labelCtrl.dispose();
    sectionCtrl.dispose();
    quantityCtrl.dispose();
    kgPerMCtrl.dispose();
  }

  static String _numberText(double value) =>
      value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: const BoxDecoration(
        color: AqsColors.primaryDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Roof structure measurement sheet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Record calculated quantities and connect every item to the BOQ.',
                  style: TextStyle(color: Color(0xFFCBD9F5)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            color: Colors.white,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _SheetDetails extends StatelessWidget {
  const _SheetDetails({
    required this.sheetNameCtrl,
    required this.trussCountCtrl,
    required this.factorCtrl,
    required this.notesCtrl,
    required this.onChanged,
  });

  final TextEditingController sheetNameCtrl;
  final TextEditingController trussCountCtrl;
  final TextEditingController factorCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final fields = [
          TextFormField(
            controller: sheetNameCtrl,
            decoration: const InputDecoration(labelText: 'Sheet / truss name'),
            validator:
                (value) =>
                    (value ?? '').trim().isEmpty ? 'Name is required' : null,
          ),
          TextFormField(
            controller: trussCountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Number of trusses'),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final number = int.tryParse((value ?? '').trim()) ?? 0;
              return number <= 0 ? 'Enter a valid count' : null;
            },
          ),
          TextFormField(
            controller: factorCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Multiplying factor'),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final number = double.tryParse((value ?? '').trim()) ?? 0;
              return number <= 0 ? 'Enter a valid factor' : null;
            },
          ),
        ];

        return Column(
          children: [
            if (compact)
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index < fields.length - 1) const SizedBox(height: 12),
              ]
            else
              Row(
                children: [
                  Expanded(flex: 2, child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[2]),
                ],
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Drawing reference / notes',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoofRowCard extends StatelessWidget {
  const _RoofRowCard({
    required this.index,
    required this.row,
    required this.trussCount,
    required this.factor,
    required this.enabled,
    required this.onChanged,
    required this.onPickBoq,
    required this.onRemove,
  });

  final int index;
  final _RoofSheetRow row;
  final int trussCount;
  final double factor;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onPickBoq;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final value = row.calculatedValue(
      trussCount: trussCount,
      factor: factor,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.boq == null ? const Color(0xFFFDB022) : AqsColors.border,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final details = Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: row.labelCtrl,
                      enabled: enabled,
                      decoration: InputDecoration(
                        labelText: 'Item ${index + 1}',
                      ),
                      validator:
                          (value) =>
                              (value ?? '').trim().isEmpty
                                  ? 'Item is required'
                                  : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: row.sectionCtrl,
                      enabled: enabled,
                      decoration: const InputDecoration(
                        labelText: 'Section / specification',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_RoofMeasureBasis>(
                      value: row.basis,
                      decoration: const InputDecoration(
                        labelText: 'Calculation',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _RoofMeasureBasis.weight,
                          child: Text('Steel weight'),
                        ),
                        DropdownMenuItem(
                          value: _RoofMeasureBasis.length,
                          child: Text('Length'),
                        ),
                        DropdownMenuItem(
                          value: _RoofMeasureBasis.count,
                          child: Text('Count'),
                        ),
                      ],
                      onChanged:
                          enabled
                              ? (value) {
                                if (value == null) return;
                                row.basis = value;
                                onChanged();
                              }
                              : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: row.quantityCtrl,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            row.basis == _RoofMeasureBasis.count
                                ? 'Qty / truss'
                                : 'Length / truss (m)',
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (value) {
                        final number =
                            double.tryParse((value ?? '').trim()) ?? 0;
                        return number <= 0 ? 'Enter quantity' : null;
                      },
                    ),
                  ),
                  if (row.basis == _RoofMeasureBasis.weight) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: row.kgPerMCtrl,
                        enabled: enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'kg/m'),
                        onChanged: (_) => onChanged(),
                        validator: (value) {
                          final number =
                              double.tryParse((value ?? '').trim()) ?? 0;
                          return number <= 0 ? 'Enter kg/m' : null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );

          final boq = Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AqsColors.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  row.boq == null
                      ? 'BOQ item required'
                      : '${row.boq!.code} — ${row.boq!.description}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        row.boq == null
                            ? const Color(0xFFB54708)
                            : AqsColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: enabled ? onPickBoq : null,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(row.boq == null ? 'Select BOQ' : 'Change BOQ'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Total: ${value.toStringAsFixed(3)} ${row.unit}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AqsColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              children: [
                details,
                const SizedBox(height: 12),
                boq,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: details),
              const SizedBox(width: 14),
              Expanded(flex: 3, child: boq),
            ],
          );
        },
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AqsColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon:
                saving
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Saving…' : 'Save measurement sheet'),
          ),
        ],
      ),
    );
  }
}
