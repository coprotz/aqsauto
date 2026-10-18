import 'dart:async';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/dialogs/roof_member_measurement_dialog.dart';
import 'package:aqs/features/takeoff/widgets/boq_picker_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TimberRoofMemberMeasurementResult {
  const TimberRoofMemberMeasurementResult({
    required this.action,
    this.boq,
    this.sessionDefaults,
    this.memberType,
    this.memberData,
  });

  final RoofMemberSaveAction action;
  final BoqPick? boq;
  final Map<String, dynamic>? sessionDefaults;
  final String? memberType;
  /// Unsaved timber member payload. The controller keeps this in the current
  /// truss draft until the user presses Save truss.
  final Map<String, dynamic>? memberData;
}

Future<TimberRoofMemberMeasurementResult> showTimberRoofMemberMeasurementDialog({
  required BuildContext context,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required String drawingTitle,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Offset p1,
  required Offset p2,
  required double measuredLengthM,
  required Color color,
  required String chainId,
  required int segmentIndex,
  List<Map<String, dynamic>>? polylineSegments,
  BoqPick? initialBoq,
  BoqPick? lastBoq,
  Map<String, BoqPick>? lastBoqByMember,
  List<BoqPick>? recentBoqs,
  Map<String, dynamic>? initialSessionDefaults,
}) async {
  return await showDialog<TimberRoofMemberMeasurementResult>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => _TimberRoofMemberDialog(
              projectId: projectId,
              buildingId: buildingId,
              drawingId: drawingId,
              drawingTitle: drawingTitle,
              measurementsRef: measurementsRef,
              p1: p1,
              p2: p2,
              measuredLengthM: measuredLengthM,
              color: color,
              chainId: chainId,
              segmentIndex: segmentIndex,
              polylineSegments: polylineSegments,
              initialBoq: initialBoq,
              lastBoq: lastBoq,
              lastBoqByMember: lastBoqByMember,
              recentBoqs: recentBoqs,
              initialSessionDefaults: initialSessionDefaults,
            ),
      ) ??
      const TimberRoofMemberMeasurementResult(action: RoofMemberSaveAction.cancel);
}

enum _TimberMemberType {
  tieBeam('Tie beam', 'tieBeam', 'm'),
  kingPost('King post', 'kingPost', 'm'),
  rafter('Rafter', 'rafter', 'm'),
  wallPlate('Wall plate', 'wallPlate', 'm'),
  strut('Strut', 'strut', 'm'),
  purlin('Purlin', 'purlin', 'm'),
  bolt('Bolts / fixings', 'bolt', 'Nos'),
  other('Other timber member', 'other', 'm');

  const _TimberMemberType(this.label, this.key, this.unit);

  final String label;
  final String key;
  final String unit;
}

class _TimberRoofMemberDialog extends StatefulWidget {
  const _TimberRoofMemberDialog({
    required this.projectId,
    required this.buildingId,
    required this.drawingId,
    required this.drawingTitle,
    required this.measurementsRef,
    required this.p1,
    required this.p2,
    required this.measuredLengthM,
    required this.color,
    required this.chainId,
    required this.segmentIndex,
    this.polylineSegments,
    this.initialBoq,
    this.lastBoq,
    this.lastBoqByMember,
    this.recentBoqs,
    this.initialSessionDefaults,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;
  final String drawingTitle;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final Offset p1;
  final Offset p2;
  final double measuredLengthM;
  final Color color;
  final String chainId;
  final int segmentIndex;
  final List<Map<String, dynamic>>? polylineSegments;
  final BoqPick? initialBoq;
  final BoqPick? lastBoq;
  final Map<String, BoqPick>? lastBoqByMember;
  final List<BoqPick>? recentBoqs;
  final Map<String, dynamic>? initialSessionDefaults;

  @override
  State<_TimberRoofMemberDialog> createState() => _TimberRoofMemberDialogState();
}

class _TimberRoofMemberDialogState extends State<_TimberRoofMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _markCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController(text: '150 × 50 mm');
  final _piecesCtrl = TextEditingController(text: '1');
  final _factorCtrl = TextEditingController(text: '1');
  final _qtyCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();

  _TimberMemberType _type = _TimberMemberType.rafter;
  BoqPick? _boq;
  bool _saving = false;
  String? _error;

  double get _pieces => double.tryParse(_piecesCtrl.text.trim()) ?? 0;
  double get _factor => double.tryParse(_factorCtrl.text.trim()) ?? 0;
  double get _qty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;
  bool get _isCountItem => _type.unit == 'Nos';
  double get _totalLength => widget.measuredLengthM * _pieces * _factor;
  double get _savedValue => _isCountItem ? (_qty * _factor) : _totalLength;
  bool get _hasValidBoq =>
      _boq != null &&
      (_boq!.id.trim().isNotEmpty ||
          _boq!.code.trim().isNotEmpty ||
          _boq!.description.trim().isNotEmpty);
  bool get _hasValidInputs =>
      _factor > 0 &&
      (_isCountItem
          ? _qty > 0
          : _pieces > 0 && _sizeCtrl.text.trim().isNotEmpty);
  bool get _canSave => !_saving && _hasValidBoq && _hasValidInputs;

  @override
  void initState() {
    super.initState();
    _boq = widget.initialBoq;
    final defaults = widget.initialSessionDefaults;
    if (defaults != null) {
      final memberType = defaults['timberMemberType']?.toString();
      for (final type in _TimberMemberType.values) {
        if (type.key == memberType || type.name == memberType) {
          _type = type;
          break;
        }
      }
      _setController(_sizeCtrl, defaults['size']);
      _setController(_piecesCtrl, defaults['pieces']);
      _setController(_factorCtrl, defaults['factor']);
      _setController(_qtyCtrl, defaults['quantity']);
      _setController(_markCtrl, defaults['memberMark']);
      _setController(_notesCtrl, defaults['notes']);
    }

    // Prefer the last BOQ used for this exact timber member. This avoids
    // carrying (for example) a Strut BOQ into the next Rafter take-off.
    _boq = widget.lastBoqByMember?[_type.key] ?? _boq;
  }

  void _setController(TextEditingController controller, dynamic value) {
    if (value != null && value.toString().trim().isNotEmpty) {
      controller.text = value.toString();
    }
  }

  @override
  void dispose() {
    _markCtrl.dispose();
    _sizeCtrl.dispose();
    _piecesCtrl.dispose();
    _factorCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBoq() async {
    if (_saving) return;
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
        _boq = pick;
        _error = null;
      });
    }
  }

  void _useLastBoq() {
    final lastBoq = widget.lastBoq;
    if (_saving || lastBoq == null) return;
    setState(() {
      _boq = lastBoq;
      _error = null;
    });
  }

  void _selectMember(_TimberMemberType type) {
    if (_saving) return;
    setState(() {
      _type = type;
      // Fast take-off: selecting a member automatically recalls the BOQ
      // previously used for the same member during this take-off session.
      final remembered = widget.lastBoqByMember?[type.key];
      if (remembered != null) {
        _boq = remembered;
      }
      _error = null;
    });
  }

  List<BoqPick> get _recentBoqs {
    final out = <BoqPick>[];
    final seen = <String>{};
    for (final pick in widget.recentBoqs ?? const <BoqPick>[]) {
      final key = pick.id.trim().isNotEmpty
          ? 'id:${pick.id.trim()}'
          : 'code:${pick.code.trim()}|${pick.description.trim()}';
      if (seen.add(key)) out.add(pick);
    }
    return out;
  }

  void _useRecentBoq(BoqPick pick) {
    if (_saving) return;
    setState(() {
      _boq = pick;
      _error = null;
    });
  }

  Map<String, dynamic> _sessionDefaults() => {
    'timberMemberType': _type.key,
    'size': _sizeCtrl.text.trim(),
    'pieces': _piecesCtrl.text.trim(),
    'factor': _factorCtrl.text.trim(),
    'quantity': _qtyCtrl.text.trim(),
    'memberMark': _markCtrl.text.trim(),
    'notes': _notesCtrl.text.trim(),
  };

  Future<void> _save() async {
    if (!_canSave || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final label =
          _markCtrl.text.trim().isEmpty
              ? _type.label
              : '${_type.label} - ${_markCtrl.text.trim()}';

      // IMPORTANT: do not write this member to Firestore here.
      // It becomes part of the in-memory truss draft and is committed with
      // the other members when the user presses `Save truss`.
      final memberData = <String, dynamic>{
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': widget.drawingId,
        'drawingTitle': widget.drawingTitle,
        'roofGroupId': widget.chainId,
        'chainId': widget.chainId,
        'measureType': 'compositeRoofing',
        'activeMeasureType': 'compositeRoofing',
        'type': 'timberRoofStructureMember',
        'memberType': _type.key,
        'timberMemberType': _type.key,
        'memberTypeLabel': _type.label,
        'label': label,
        'memberMark': _markCtrl.text.trim(),
        'size': _sizeCtrl.text.trim(),
        'unit': _type.unit,
        'value': _savedValue,
        'lengthM': widget.measuredLengthM,
        'measuredLengthM': widget.measuredLengthM,
        'totalLengthM': _isCountItem ? null : _totalLength,
        'pieces': _pieces,
        'quantity': _isCountItem ? _qty : null,
        'multiplyingFactor': _factor,
        'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
        'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
        'segment': {
          'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
          'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
        },
        if (widget.polylineSegments != null &&
            widget.polylineSegments!.isNotEmpty)
          'polylineSegments': widget.polylineSegments,
        'segmentIndex': widget.segmentIndex,
        'boqItemId': _boq!.id,
        'boqCode': _boq!.code,
        'boqDescription': _boq!.description,
        'notes': _notesCtrl.text.trim(),
        'color': widget.color.value,
      };

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(
        TimberRoofMemberMeasurementResult(
          action: RoofMemberSaveAction.saveAndFinish,
          boq: _boq,
          sessionDefaults: _sessionDefaults(),
          memberType: _type.key,
          memberData: memberData,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not add member: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measuredLengthLabel =
        '${widget.measuredLengthM.toStringAsFixed(3)} m measured';
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AqsColors.primaryDark.withOpacity(0.20),
                      blurRadius: 36,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(28, 26, 24, 24),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AqsColors.primaryDark, AqsColors.primary],
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.22),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.carpenter_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Timber roof structure',
                                        style: theme.textTheme.headlineSmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _headerPill(
                                            Icons.straighten_rounded,
                                            measuredLengthLabel,
                                          ),
                                          _headerPill(
                                            Icons.category_rounded,
                                            _type.label,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed:
                                      _saving
                                          ? null
                                          : () => Navigator.of(
                                            context,
                                            rootNavigator: true,
                                          ).pop(
                                            const TimberRoofMemberMeasurementResult(
                                              action: RoofMemberSaveAction.cancel,
                                            ),
                                          ),
                                  icon: const Icon(Icons.close_rounded),
                                  color: Colors.white,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select member',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AqsColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children:
                                      _TimberMemberType.values.map((type) {
                                        final selected = _type == type;
                                        return ChoiceChip(
                                          avatar:
                                              selected
                                                  ? const Icon(
                                                    Icons.check_rounded,
                                                    size: 18,
                                                    color: Colors.white,
                                                  )
                                                  : null,
                                          label: Text(type.label),
                                          selected: selected,
                                          showCheckmark: false,
                                          selectedColor: AqsColors.primary,
                                          backgroundColor: Colors.white,
                                          side: BorderSide(
                                            color:
                                                selected
                                                    ? AqsColors.primary
                                                    : const Color(0xFFD0D5DD),
                                          ),
                                          labelStyle: TextStyle(
                                            color:
                                                selected ? Colors.white : AqsColors.text,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          onSelected:
                                              _saving
                                                  ? null
                                                  : (_) => _selectMember(type),
                                        );
                                      }).toList(),
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _field(
                                        controller: _markCtrl,
                                        label: 'Mark / label (optional)',
                                        prefixIcon: Icons.sell_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _field(
                                        controller: _sizeCtrl,
                                        label: 'Size / section',
                                        prefixIcon: Icons.view_week_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child:
                                          _isCountItem
                                              ? _numberField(
                                                controller: _qtyCtrl,
                                                label: 'Quantity (Nos)',
                                                prefixIcon: Icons.tag_rounded,
                                              )
                                              : _numberField(
                                                controller: _piecesCtrl,
                                                label: 'Pieces for this span',
                                                prefixIcon:
                                                    Icons.format_list_numbered_rounded,
                                              ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _numberField(
                                        controller: _factorCtrl,
                                        label: 'Building / repetition factor',
                                        prefixIcon: Icons.copy_all_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _summaryCard(theme),
                                const SizedBox(height: 18),
                                _boqCard(theme),
                                const SizedBox(height: 12),
                                _field(
                                  controller: _notesCtrl,
                                  label: 'Notes (optional)',
                                  prefixIcon: Icons.notes_rounded,
                                  maxLines: 2,
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F3),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFFECDD6)),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFFC01048),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          _saving
                                              ? null
                                              : () => Navigator.of(
                                                context,
                                                rootNavigator: true,
                                              ).pop(
                                                const TimberRoofMemberMeasurementResult(
                                                  action: RoofMemberSaveAction.cancel,
                                                ),
                                              ),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 10),
                                    FilledButton(
                                      onPressed: _canSave ? _save : null,
                                      child: const Text('Add member'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_saving) _savingOverlay(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    IconData? prefixIcon,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final n = double.tryParse((value ?? '').trim()) ?? 0;
        if (n <= 0) return 'Enter a value greater than 0';
        return null;
      },
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _summaryCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF4FF), Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E5FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AqsColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isCountItem ? Icons.tag_rounded : Icons.straighten_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCountItem ? 'Quantity to save' : 'Length to save',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isCountItem
                      ? '${_savedValue.toStringAsFixed(2)} Nos'
                      : '${_savedValue.toStringAsFixed(3)} m',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AqsColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isCountItem
                      ? '${_qty.toStringAsFixed(2)} × ${_factor.toStringAsFixed(2)}'
                      : '${widget.measuredLengthM.toStringAsFixed(3)} m × '
                          '${_pieces.toStringAsFixed(2)} × '
                          '${_factor.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boqCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: AqsColors.primaryDark.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected BOQ item',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _boq == null
                      ? 'No BOQ selected'
                      : '${_boq!.code} — ${_boq!.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _boq == null ? AqsColors.subtle : AqsColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickBoq,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Pick'),
          ),
          const SizedBox(width: 8),
          if (_recentBoqs.isNotEmpty)
            PopupMenuButton<BoqPick>(
              enabled: !_saving,
              tooltip: 'Recently used BOQs',
              onSelected: _useRecentBoq,
              itemBuilder: (context) => [
                for (final pick in _recentBoqs)
                  PopupMenuItem<BoqPick>(
                    value: pick,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        '${pick.code} — ${pick.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              child: IgnorePointer(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Recent BOQs'),
                ),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed:
                  (_saving || widget.lastBoq == null) ? null : _useLastBoq,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Last BOQ'),
            ),
        ],
      ),
    );
  }

  Widget _savingOverlay(ThemeData theme) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: ColoredBox(
          color: Colors.black.withOpacity(0.42),
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 22,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Adding member to truss…',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AqsColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
