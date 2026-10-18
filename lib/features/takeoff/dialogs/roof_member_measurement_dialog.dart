import 'dart:math' as math;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:aqs/features/takeoff/widgets/boq_picker_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum RoofMemberSaveAction { cancel, saveAndFinish, saveAndContinue }

class RoofMemberMeasurementResult {
  const RoofMemberMeasurementResult({
    required this.action,
    this.boq,
    this.sessionDefaults,
  });

  final RoofMemberSaveAction action;
  final BoqPick? boq;
  final Map<String, dynamic>? sessionDefaults;
}

Future<RoofMemberMeasurementResult> showRoofMemberMeasurementDialog({
  required BuildContext context,
  required String projectId,
  required String buildingId,
  required String drawingId,
  required String drawingTitle,
  required CollectionReference<Map<String, dynamic>> measurementsRef,
  required Offset p1,
  required Offset p2,
  required double currentSegmentLengthM,
  required double chainLengthM,
  required Color color,
  required String chainId,
  required int segmentIndex,
  List<Map<String, dynamic>>? polylineSegments,
  BoqPick? initialBoq,
  BoqPick? lastBoq,
  Map<String, dynamic>? initialSessionDefaults,
}) async {
  return await showDialog<RoofMemberMeasurementResult>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => _RoofMemberDialog(
              projectId: projectId,
              buildingId: buildingId,
              drawingId: drawingId,
              drawingTitle: drawingTitle,
              measurementsRef: measurementsRef,
              p1: p1,
              p2: p2,
              measuredLengthM: currentSegmentLengthM,
              totalMeasuredLengthM: chainLengthM,
              color: color,
              chainId: chainId,
              segmentIndex: segmentIndex,
              polylineSegments: polylineSegments,
              initialBoq: initialBoq,
              lastBoq: lastBoq,
              initialSessionDefaults: initialSessionDefaults,
            ),
      ) ??
      const RoofMemberMeasurementResult(action: RoofMemberSaveAction.cancel);
}

class _RoofMemberDialog extends StatefulWidget {
  const _RoofMemberDialog({
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
    this.initialBoq,
    this.lastBoq,
    this.initialSessionDefaults,
    required this.totalMeasuredLengthM,
    this.polylineSegments,
  });

  final String projectId;
  final String buildingId;
  final String drawingId;
  final String drawingTitle;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final Offset p1;
  final Offset p2;
  final double measuredLengthM;
  final double totalMeasuredLengthM;
  final List<Map<String, dynamic>>? polylineSegments;
  final Color color;
  final String chainId;
  final int segmentIndex;
  final BoqPick? initialBoq;
  final BoqPick? lastBoq;
  final Map<String, dynamic>? initialSessionDefaults;

  @override
  State<_RoofMemberDialog> createState() => _RoofMemberDialogState();
}

class _RoofMemberDialogState extends State<_RoofMemberDialog> {
  static const double _steelDensityFactor = 0.00785; // kg/m per mm2

  final _formKey = GlobalKey<FormState>();
  final _markCtrl = TextEditingController();

  // CHS inputs: outside diameter + wall thickness.
  final _sizeCtrl = TextEditingController(text: '60.3');
  final _thicknessCtrl = TextEditingController(text: '3.2');

  // Z-purlin inputs: depth + flange + thickness.
  final _zDepthCtrl = TextEditingController(text: '152');
  final _zFlangeCtrl = TextEditingController(text: '75');
  final _zThicknessCtrl = TextEditingController(text: '3');

  // Sag member: assumed solid round steel rod diameter.
  final _sagDiameterCtrl = TextEditingController(text: '12');

  final _piecesCtrl = TextEditingController(text: '1');
  final _trussCountCtrl = TextEditingController(text: '9');
  final _factorCtrl = TextEditingController(text: '1');
  final _connectionsCtrl = TextEditingController(text: '2');
  final _cleatsPerConnectionCtrl = TextEditingController(text: '2');
  final _boltsPerConnectionCtrl = TextEditingController(text: '4');
  final _platesPerConnectionCtrl = TextEditingController(text: '1');
  final _sagPerConnectionCtrl = TextEditingController(text: '1');
  final _connectionSagLengthCtrl = TextEditingController(text: '1');
  final _connectionSagDiameterCtrl = TextEditingController(text: '12');
  final _notesCtrl = TextEditingController();

  _RoofMemberType _type = _RoofMemberType.topChord;
  BoqPick? _boq;
  BoqPick? _angleCleatBoq;
  BoqPick? _boltBoq;
  BoqPick? _gussetPlateBoq;
  BoqPick? _connectionSagBoq;
  bool _includeConnections = false;
  bool _includeAngleCleats = true;
  bool _includeBolts = true;
  bool _includeGussetPlates = true;
  bool _includeConnectionSagMembers = false;
  bool _saving = false;
  String? _error;

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  int get _pieces => int.tryParse(_piecesCtrl.text.trim()) ?? 0;
  int get _trussCount => int.tryParse(_trussCountCtrl.text.trim()) ?? 0;
  double get _factor => _number(_factorCtrl);

  // IMPORTANT: use the total length of the complete continuous chain,
  // not only the currently selected/last segment.
  double get _chainMeasuredLengthM => widget.totalMeasuredLengthM;

  double get _totalLength =>
      _chainMeasuredLengthM * _pieces * _trussCount * _factor;

  bool get _isZPurlin => _type == _RoofMemberType.zPurlin;
  bool get _isSagMember => _type == _RoofMemberType.sagMember;
  bool get _isChsMember => !_isZPurlin && !_isSagMember;

  /// CHS theoretical mass:
  /// area = pi/4 * (D^2 - (D - 2t)^2)
  /// kg/m = area(mm2) * 0.00785
  double get _chsKgPerM {
    final d = _number(_sizeCtrl);
    final t = _number(_thicknessCtrl);
    if (d <= 0 || t <= 0 || 2 * t >= d) return 0;
    final area = math.pi / 4 * (d * d - math.pow(d - 2 * t, 2));
    return area * _steelDensityFactor;
  }

  /// Simplified Z-section estimate using three inputs only:
  /// developed plate width ~= depth + 2 * flange
  /// area ~= developed width * thickness
  /// This ignores lips, corner radii and coating.
  double get _zPurlinKgPerM {
    final depth = _number(_zDepthCtrl);
    final flange = _number(_zFlangeCtrl);
    final t = _number(_zThicknessCtrl);
    if (depth <= 0 || flange <= 0 || t <= 0) return 0;
    final area = (depth + 2 * flange) * t;
    return area * _steelDensityFactor;
  }

  /// Sag member estimate assumes a SOLID round steel rod.
  /// kg/m = pi/4 * d^2 * 0.00785
  double get _sagKgPerM {
    final d = _number(_sagDiameterCtrl);
    if (d <= 0) return 0;
    final area = math.pi / 4 * d * d;
    return area * _steelDensityFactor;
  }

  double get _kgPerM {
    if (_isZPurlin) return _zPurlinKgPerM;
    if (_isSagMember) return _sagKgPerM;
    return _chsKgPerM;
  }

  double get _totalWeight => _totalLength * _kgPerM;

  double get _connectionMultiplier => _pieces * _trussCount * _factor;
  double get _totalConnections =>
      _number(_connectionsCtrl) * _connectionMultiplier;
  double get _totalAngleCleats =>
      _totalConnections * _number(_cleatsPerConnectionCtrl);
  double get _totalBolts =>
      _totalConnections * _number(_boltsPerConnectionCtrl);
  double get _totalGussetPlates =>
      _totalConnections * _number(_platesPerConnectionCtrl);
  double get _connectionSagLength =>
      _totalConnections *
      _number(_sagPerConnectionCtrl) *
      _number(_connectionSagLengthCtrl);
  double get _connectionSagKgPerM {
    final diameter = _number(_connectionSagDiameterCtrl);
    if (diameter <= 0) return 0;
    return math.pi / 4 * diameter * diameter * _steelDensityFactor;
  }

  double get _connectionSagWeight =>
      _connectionSagLength * _connectionSagKgPerM;

  String get _sectionDescription {
    if (_isZPurlin) {
      return '${_zDepthCtrl.text.trim()} x ${_zFlangeCtrl.text.trim()} x ${_zThicknessCtrl.text.trim()} mm Z-purlin';
    }
    if (_isSagMember) {
      return 'Dia ${_sagDiameterCtrl.text.trim()} mm solid sag rod';
    }
    return '${_sizeCtrl.text.trim()} x ${_thicknessCtrl.text.trim()} mm CHS';
  }

  @override
  void initState() {
    super.initState();
    _boq = widget.initialBoq;

    final defaults = widget.initialSessionDefaults;
    if (defaults != null) {
      final savedType = defaults['memberType']?.toString();
      for (final type in _RoofMemberType.values) {
        if (type.name == savedType) {
          _type = type;
          break;
        }
      }

      _setController(_sizeCtrl, defaults['sizeMm']);
      _setController(_thicknessCtrl, defaults['thicknessMm']);
      _setController(_zDepthCtrl, defaults['zDepthMm']);
      _setController(_zFlangeCtrl, defaults['zFlangeMm']);
      _setController(_zThicknessCtrl, defaults['zThicknessMm']);
      _setController(_sagDiameterCtrl, defaults['sagDiameterMm']);
      _setController(_piecesCtrl, defaults['pieces']);
      _setController(_trussCountCtrl, defaults['trussCount']);
      _setController(_factorCtrl, defaults['factor']);
      _setController(_connectionsCtrl, defaults['connectionsPerMember']);
      _setController(
        _cleatsPerConnectionCtrl,
        defaults['angleCleatsPerConnection'],
      );
      _setController(_boltsPerConnectionCtrl, defaults['boltsPerConnection']);
      _setController(
        _platesPerConnectionCtrl,
        defaults['gussetPlatesPerConnection'],
      );
      _setController(
        _sagPerConnectionCtrl,
        defaults['sagMembersPerConnection'],
      );
      _setController(_connectionSagLengthCtrl, defaults['sagMemberLengthM']);
      _setController(
        _connectionSagDiameterCtrl,
        defaults['connectionSagDiameterMm'],
      );
      _includeConnections = defaults['includeConnections'] == true;
      _includeAngleCleats = defaults['includeAngleCleats'] != false;
      _includeBolts = defaults['includeBolts'] != false;
      _includeGussetPlates = defaults['includeGussetPlates'] != false;
      _includeConnectionSagMembers =
          defaults['includeConnectionSagMembers'] == true;
      _angleCleatBoq = BoqPick.fromMap(defaults['angleCleatBoq']);
      _boltBoq = BoqPick.fromMap(defaults['boltBoq']);
      _gussetPlateBoq = BoqPick.fromMap(defaults['gussetPlateBoq']);
      _connectionSagBoq = BoqPick.fromMap(defaults['connectionSagBoq']);
    }
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
    _thicknessCtrl.dispose();
    _zDepthCtrl.dispose();
    _zFlangeCtrl.dispose();
    _zThicknessCtrl.dispose();
    _sagDiameterCtrl.dispose();
    _piecesCtrl.dispose();
    _trussCountCtrl.dispose();
    _factorCtrl.dispose();
    _connectionsCtrl.dispose();
    _cleatsPerConnectionCtrl.dispose();
    _boltsPerConnectionCtrl.dispose();
    _platesPerConnectionCtrl.dispose();
    _sagPerConnectionCtrl.dispose();
    _connectionSagLengthCtrl.dispose();
    _connectionSagDiameterCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBoq() async {
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

  Future<void> _pickConnectionBoq(ValueSetter<BoqPick> onPicked) async {
    final pick = await showDialog<BoqPick>(
      context: context,
      builder:
          (_) => BoqPickerDialog(
            projectId: widget.projectId,
            buildingId: widget.buildingId,
          ),
    );
    if (pick != null && mounted) setState(() => onPicked(pick));
  }

  void _useLastBoq() {
    final lastBoq = widget.lastBoq;
    if (lastBoq == null) return;
    setState(() {
      _boq = lastBoq;
      _error = null;
    });
  }

  Map<String, dynamic> _sessionDefaults() => {
    'memberType': _type.name,
    'sizeMm': _sizeCtrl.text.trim(),
    'thicknessMm': _thicknessCtrl.text.trim(),
    'zDepthMm': _zDepthCtrl.text.trim(),
    'zFlangeMm': _zFlangeCtrl.text.trim(),
    'zThicknessMm': _zThicknessCtrl.text.trim(),
    'sagDiameterMm': _sagDiameterCtrl.text.trim(),
    'pieces': _piecesCtrl.text.trim(),
    'trussCount': _trussCountCtrl.text.trim(),
    'factor': _factorCtrl.text.trim(),
    'includeConnections': _includeConnections,
    'includeAngleCleats': _includeAngleCleats,
    'includeBolts': _includeBolts,
    'includeGussetPlates': _includeGussetPlates,
    'connectionsPerMember': _connectionsCtrl.text.trim(),
    'angleCleatsPerConnection': _cleatsPerConnectionCtrl.text.trim(),
    'boltsPerConnection': _boltsPerConnectionCtrl.text.trim(),
    'gussetPlatesPerConnection': _platesPerConnectionCtrl.text.trim(),
    'includeConnectionSagMembers': _includeConnectionSagMembers,
    'sagMembersPerConnection': _sagPerConnectionCtrl.text.trim(),
    'sagMemberLengthM': _connectionSagLengthCtrl.text.trim(),
    'connectionSagDiameterMm': _connectionSagDiameterCtrl.text.trim(),
    'angleCleatBoq': _angleCleatBoq?.toMap(),
    'boltBoq': _boltBoq?.toMap(),
    'gussetPlateBoq': _gussetPlateBoq?.toMap(),
    'connectionSagBoq': _connectionSagBoq?.toMap(),
  };

  String? _positive(String? value) =>
      (double.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;

  String? _positiveInt(String? value) =>
      (int.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;

  String? _chsThicknessValidator(String? value) {
    final t = double.tryParse((value ?? '').trim()) ?? 0;
    final d = _number(_sizeCtrl);
    if (t <= 0) return 'Required';
    if (d > 0 && 2 * t >= d) return 'Thickness is too large';
    return null;
  }

  Future<void> _save(RoofMemberSaveAction action) async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_boq == null) {
      setState(() => _error = 'Select the BOQ item for this member.');
      return;
    }
    if (_kgPerM <= 0) {
      setState(() => _error = 'Enter valid member dimensions.');
      return;
    }
    if (_includeConnections &&
        ((_includeAngleCleats && _angleCleatBoq == null) ||
            (_includeBolts && _boltBoq == null) ||
            (_includeGussetPlates && _gussetPlateBoq == null))) {
      setState(() {
        _error = 'Select a BOQ item for each included connection fitting.';
      });
      return;
    }
    if (_includeConnections &&
        (_totalConnections <= 0 ||
            (_includeAngleCleats && _totalAngleCleats <= 0) ||
            (_includeBolts && _totalBolts <= 0) ||
            (_includeGussetPlates && _totalGussetPlates <= 0))) {
      setState(() => _error = 'Enter valid connection quantities.');
      return;
    }
    if (_includeConnectionSagMembers &&
        (_connectionSagBoq == null || _connectionSagWeight <= 0)) {
      setState(() {
        _error = 'Enter valid sag-member details and select its BOQ item.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final ref = widget.measurementsRef.doc();
      batch.set(ref, {
        'projectId': widget.projectId,
        'buildingId': widget.buildingId,
        'drawingId': widget.drawingId,
        'drawingTitle': widget.drawingTitle,
        'roofGroupId': widget.chainId,
        'measureType': 'roofStructureMember',
        'type': _type.name,
        'memberType': _type.name,
        'memberTypeLabel': _type.label,
        'memberMark': _markCtrl.text.trim(),
        'label':
            _markCtrl.text.trim().isEmpty
                ? _type.label
                : '${_type.label} - ${_markCtrl.text.trim()}',
        'section': _sectionDescription,
        'sizeMm': _isChsMember ? _number(_sizeCtrl) : null,
        'thicknessMm': _isChsMember ? _number(_thicknessCtrl) : null,
        'zDepthMm': _isZPurlin ? _number(_zDepthCtrl) : null,
        'zFlangeMm': _isZPurlin ? _number(_zFlangeCtrl) : null,
        'zThicknessMm': _isZPurlin ? _number(_zThicknessCtrl) : null,
        'sagDiameterMm': _isSagMember ? _number(_sagDiameterCtrl) : null,
        // Overall continuous-chain length used for quantity/weight.
        'lengthM': _chainMeasuredLengthM,
        'measuredLengthM': _chainMeasuredLengthM,
        // Keep the current segment length separately for traceability.
        'segmentLengthM': widget.measuredLengthM,
        'piecesPerTruss': _pieces,
        'trussCount': _trussCount,
        'multiplyingFactor': _factor,
        'totalLengthM': _totalLength,
        'kgPerM': _kgPerM,
        'unit': 'kg',
        'value': _totalWeight,
        'hasConnectionComponents': _includeConnections,
        'connectionCount': _includeConnections ? _totalConnections : 0,
        'includedConnectionComponents': {
          'angleCleats': _includeConnections && _includeAngleCleats,
          'bolts': _includeConnections && _includeBolts,
          'gussetPlates': _includeConnections && _includeGussetPlates,
          'sagMembers': _includeConnections && _includeConnectionSagMembers,
        },
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
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      void addConnectionComponent({
        required String componentType,
        required String label,
        required double value,
        required String unit,
        required BoqPick boq,
        Map<String, dynamic>? calculation,
      }) {
        final componentRef = widget.measurementsRef.doc();
        batch.set(componentRef, {
          'projectId': widget.projectId,
          'buildingId': widget.buildingId,
          'drawingId': widget.drawingId,
          'drawingTitle': widget.drawingTitle,
          'roofGroupId': widget.chainId,
          'parentMeasurementId': ref.id,
          'measureType': 'roofConnectionComponent',
          'type': componentType,
          'componentType': componentType,
          'label': label,
          'value': value,
          'unit': unit,
          'connectionCount': _totalConnections,
          'calculation': calculation,
          'boqItemId': boq.id,
          'boqCode': boq.code,
          'boqDescription': boq.description,
          'color': widget.color.value,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (_includeConnections) {
        if (_includeAngleCleats) {
          addConnectionComponent(
            componentType: 'angleCleat',
            label: 'Angle cleats',
            value: _totalAngleCleats,
            unit: 'Nos',
            boq: _angleCleatBoq!,
            calculation: {
              'connections': _totalConnections,
              'perConnection': _number(_cleatsPerConnectionCtrl),
            },
          );
        }
        if (_includeBolts) {
          addConnectionComponent(
            componentType: 'connectionBolt',
            label: 'Connection bolts',
            value: _totalBolts,
            unit: 'Nos',
            boq: _boltBoq!,
            calculation: {
              'connections': _totalConnections,
              'perConnection': _number(_boltsPerConnectionCtrl),
            },
          );
        }
        if (_includeGussetPlates) {
          addConnectionComponent(
            componentType: 'gussetPlate',
            label: 'Gusset plates',
            value: _totalGussetPlates,
            unit: 'Nos',
            boq: _gussetPlateBoq!,
            calculation: {
              'connections': _totalConnections,
              'perConnection': _number(_platesPerConnectionCtrl),
            },
          );
        }
        if (_includeConnectionSagMembers) {
          addConnectionComponent(
            componentType: 'sagMember',
            label: 'Sag members',
            value: _connectionSagWeight,
            unit: 'kg',
            boq: _connectionSagBoq!,
            calculation: {
              'connections': _totalConnections,
              'perConnection': _number(_sagPerConnectionCtrl),
              'lengthEachM': _number(_connectionSagLengthCtrl),
              'diameterMm': _number(_connectionSagDiameterCtrl),
              'totalLengthM': _connectionSagLength,
              'kgPerM': _connectionSagKgPerM,
            },
          );
        }
      }

      await batch.commit();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(
          RoofMemberMeasurementResult(
            action: action,
            boq: _boq,
            sessionDefaults: _sessionDefaults(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save member: $e';
        });
      }
    }
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: 'mm',
      ),
      validator: validator ?? _positive,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dimensionInputs() {
    if (_isZPurlin) {
      return Row(
        children: [
          Expanded(
            child: _numberField(
              controller: _zDepthCtrl,
              label: 'Depth',
              hint: '152',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _numberField(
              controller: _zFlangeCtrl,
              label: 'Flange',
              hint: '75',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _numberField(
              controller: _zThicknessCtrl,
              label: 'Thickness',
              hint: '3',
            ),
          ),
        ],
      );
    }

    if (_isSagMember) {
      return _numberField(
        controller: _sagDiameterCtrl,
        label: 'Sag member diameter',
        hint: '12',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _numberField(
            controller: _sizeCtrl,
            label: 'CHS outside diameter / size',
            hint: '60.3',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _numberField(
            controller: _thicknessCtrl,
            label: 'Wall thickness',
            hint: '3.2',
            validator: _chsThicknessValidator,
          ),
        ),
      ],
    );
  }

  Widget _connectionNumberField({
    required TextEditingController controller,
    required String label,
    String? suffix,
    bool enabled = true,
  }) {
    return SizedBox(
      width: 210,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: _includeConnections && enabled ? _positive : null,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _connectionBoqTile({
    required String label,
    required String quantity,
    required BoqPick? boq,
    required ValueSetter<BoqPick> onPicked,
    required bool selected,
    required ValueChanged<bool> onSelected,
    bool showSelection = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              selected && boq == null
                  ? const Color(0xFFFDB022)
                  : AqsColors.border,
        ),
      ),
      child: Row(
        children: [
          if (showSelection) ...[
            Checkbox(
              value: selected,
              onChanged: _saving ? null : (value) => onSelected(value ?? false),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? AqsColors.ink : AqsColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(quantity, style: const TextStyle(color: AqsColors.muted)),
                if (selected && boq != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${boq.code} — ${boq.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed:
                _saving || !selected
                    ? null
                    : () => _pickConnectionBoq(onPicked),
            icon: const Icon(Icons.search_rounded),
            label: Text(
              !selected
                  ? 'Not included'
                  : boq == null
                  ? 'Select BOQ'
                  : 'Change',
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AqsColors.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _includeConnections,
            onChanged:
                _saving
                    ? null
                    : (value) => setState(() {
                      _includeConnections = value;
                      if (!value) _includeConnectionSagMembers = false;
                      _error = null;
                    }),
            title: const Text(
              'Add connections & fittings',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Select and calculate only the cleats, bolts, plates and optional sag members required.',
            ),
          ),
          if (_includeConnections) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _connectionNumberField(
                        controller: _connectionsCtrl,
                        label: 'Connections / member',
                      ),
                      _connectionNumberField(
                        controller: _cleatsPerConnectionCtrl,
                        label: 'Angle cleats / connection',
                        enabled: _includeAngleCleats,
                      ),
                      _connectionNumberField(
                        controller: _boltsPerConnectionCtrl,
                        label: 'Bolts / connection',
                        enabled: _includeBolts,
                      ),
                      _connectionNumberField(
                        controller: _platesPerConnectionCtrl,
                        label: 'Gusset plates / connection',
                        enabled: _includeGussetPlates,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_totalConnections.toStringAsFixed(0)} total connections across ${_connectionMultiplier.toStringAsFixed(0)} member occurrences',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _connectionBoqTile(
                    label: 'Angle cleats',
                    quantity: '${_totalAngleCleats.toStringAsFixed(0)} Nos',
                    boq: _angleCleatBoq,
                    onPicked: (pick) => _angleCleatBoq = pick,
                    selected: _includeAngleCleats,
                    onSelected:
                        (value) => setState(() {
                          _includeAngleCleats = value;
                          _error = null;
                        }),
                  ),
                  const SizedBox(height: 8),
                  _connectionBoqTile(
                    label: 'Connection bolts',
                    quantity: '${_totalBolts.toStringAsFixed(0)} Nos',
                    boq: _boltBoq,
                    onPicked: (pick) => _boltBoq = pick,
                    selected: _includeBolts,
                    onSelected:
                        (value) => setState(() {
                          _includeBolts = value;
                          _error = null;
                        }),
                  ),
                  const SizedBox(height: 8),
                  _connectionBoqTile(
                    label: 'Gusset plates',
                    quantity: '${_totalGussetPlates.toStringAsFixed(0)} Nos',
                    boq: _gussetPlateBoq,
                    onPicked: (pick) => _gussetPlateBoq = pick,
                    selected: _includeGussetPlates,
                    onSelected:
                        (value) => setState(() {
                          _includeGussetPlates = value;
                          _error = null;
                        }),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _includeConnectionSagMembers,
                    onChanged:
                        _saving
                            ? null
                            : (value) => setState(
                              () => _includeConnectionSagMembers = value,
                            ),
                    title: const Text(
                      'Include sag members',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_includeConnectionSagMembers) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _connectionNumberField(
                          controller: _sagPerConnectionCtrl,
                          label: 'Sag members / connection',
                        ),
                        _connectionNumberField(
                          controller: _connectionSagLengthCtrl,
                          label: 'Length each',
                          suffix: 'm',
                        ),
                        _connectionNumberField(
                          controller: _connectionSagDiameterCtrl,
                          label: 'Rod diameter',
                          suffix: 'mm',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _connectionBoqTile(
                      label: 'Sag members',
                      quantity:
                          '${_connectionSagLength.toStringAsFixed(2)} m • ${_connectionSagWeight.toStringAsFixed(2)} kg',
                      boq: _connectionSagBoq,
                      onPicked: (pick) => _connectionSagBoq = pick,
                      selected: true,
                      onSelected: (_) {},
                      showSelection: false,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.change_history_rounded, color: AqsColors.primary),
          SizedBox(width: 10),
          Text('Record roof member'),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LiveMeasurement(
                  measuredLengthM: _chainMeasuredLengthM,
                  totalLengthM: _totalLength,
                  totalWeightKg: _totalWeight,
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AqsColors.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AqsColors.border),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _RoofMemberType.values.map((type) {
                          return ChoiceChip(
                            label: Text(type.label),
                            selected: _type == type,
                            onSelected:
                                _saving
                                    ? null
                                    : (_) => setState(() {
                                      _type = type;
                                      _error = null;
                                    }),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                _dimensionInputs(),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AqsColors.border),
                  ),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Section: $_sectionDescription',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Weight/m: ${_kgPerM.toStringAsFixed(2)} kg/m',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Total: ${_totalWeight.toStringAsFixed(2)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (_isZPurlin) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Z-purlin kg/m is an estimate from depth + 2 x flange x thickness; lips and corner radii are not included.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (_isSagMember) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Sag member estimate assumes a solid round steel rod.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _markCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Member mark (optional)',
                          hintText: 'e.g. TC-01',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _piecesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Identical pieces / truss',
                        ),
                        validator: _positiveInt,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _trussCountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Number of trusses',
                        ),
                        validator: _positiveInt,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _factorCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Factor'),
                        validator: _positive,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _connectionsSection(),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AqsColors.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _boq == null
                              ? const Color(0xFFFDB022)
                              : AqsColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _boq == null
                            ? 'BOQ item is required'
                            : '${_boq!.code} — ${_boq!.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              _boq == null
                                  ? const Color(0xFFB54708)
                                  : AqsColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _pickBoq,
                            icon: const Icon(Icons.search_rounded),
                            label: Text(
                              _boq == null ? 'Select BOQ' : 'Change BOQ',
                            ),
                          ),
                          if (widget.lastBoq != null &&
                              widget.lastBoq!.id != _boq?.id)
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _useLastBoq,
                              icon: const Icon(Icons.content_paste_rounded),
                              label: Text(
                                'Use last BOQ (${widget.lastBoq!.code})',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB42318),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _saving
                  ? null
                  : () => Navigator.of(context, rootNavigator: true).pop(
                    RoofMemberMeasurementResult(
                      action: RoofMemberSaveAction.cancel,
                      boq: _boq,
                      sessionDefaults: _sessionDefaults(),
                    ),
                  ),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed:
              _saving || _boq == null
                  ? null
                  : () => _save(RoofMemberSaveAction.saveAndFinish),
          icon:
              _saving
                  ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

// class _RoofMemberDialogState extends State<_RoofMemberDialog> {
//   static const double _steelDensityFactor = 0.00785; // kg/m per mm2

//   final _formKey = GlobalKey<FormState>();
//   final _markCtrl = TextEditingController();

//   // CHS inputs: outside diameter + wall thickness.
//   final _sizeCtrl = TextEditingController(text: '60.3');
//   final _thicknessCtrl = TextEditingController(text: '3.2');

//   // Z-purlin inputs: depth + flange + thickness.
//   final _zDepthCtrl = TextEditingController(text: '152');
//   final _zFlangeCtrl = TextEditingController(text: '75');
//   final _zThicknessCtrl = TextEditingController(text: '3');

//   // Sag member: assumed solid round steel rod diameter.
//   final _sagDiameterCtrl = TextEditingController(text: '12');

//   final _piecesCtrl = TextEditingController(text: '1');
//   final _trussCountCtrl = TextEditingController(text: '9');
//   final _factorCtrl = TextEditingController(text: '1');
//   final _notesCtrl = TextEditingController();

//   _RoofMemberType _type = _RoofMemberType.topChord;
//   BoqPick? _boq;
//   bool _saving = false;
//   String? _error;

//   double _number(TextEditingController controller) =>
//       double.tryParse(controller.text.trim()) ?? 0;

//   int get _pieces => int.tryParse(_piecesCtrl.text.trim()) ?? 0;
//   int get _trussCount => int.tryParse(_trussCountCtrl.text.trim()) ?? 0;
//   double get _factor => _number(_factorCtrl);

//   // double get _totalLength =>
//   //     widget.measuredLengthM * _pieces * _trussCount * _factor;

//   bool get _isZPurlin => _type == _RoofMemberType.zPurlin;
//   bool get _isSagMember => _type == _RoofMemberType.sagMember;
//   bool get _isChsMember => !_isZPurlin && !_isSagMember;

//   double get _chainMeasuredLengthM => widget.totalMeasuredLengthM;

//   double get _totalLength =>
//       _chainMeasuredLengthM * _pieces * _trussCount * _factor;

//   /// CHS theoretical mass:
//   /// area = pi/4 * (D^2 - (D - 2t)^2)
//   /// kg/m = area(mm2) * 0.00785
//   double get _chsKgPerM {
//     final d = _number(_sizeCtrl);
//     final t = _number(_thicknessCtrl);
//     if (d <= 0 || t <= 0 || 2 * t >= d) return 0;
//     final area = math.pi / 4 * (d * d - math.pow(d - 2 * t, 2));
//     return area * _steelDensityFactor;
//   }

//   /// Simplified Z-section estimate using three inputs only:
//   /// developed plate width ~= depth + 2 * flange
//   /// area ~= developed width * thickness
//   /// This ignores lips, corner radii and coating.
//   double get _zPurlinKgPerM {
//     final depth = _number(_zDepthCtrl);
//     final flange = _number(_zFlangeCtrl);
//     final t = _number(_zThicknessCtrl);
//     if (depth <= 0 || flange <= 0 || t <= 0) return 0;
//     final area = (depth + 2 * flange) * t;
//     return area * _steelDensityFactor;
//   }

//   /// Sag member estimate assumes a SOLID round steel rod.
//   /// kg/m = pi/4 * d^2 * 0.00785
//   double get _sagKgPerM {
//     final d = _number(_sagDiameterCtrl);
//     if (d <= 0) return 0;
//     final area = math.pi / 4 * d * d;
//     return area * _steelDensityFactor;
//   }

//   double get _kgPerM {
//     if (_isZPurlin) return _zPurlinKgPerM;
//     if (_isSagMember) return _sagKgPerM;
//     return _chsKgPerM;
//   }

//   double get _totalWeight => _totalLength * _kgPerM;

//   String get _sectionDescription {
//     if (_isZPurlin) {
//       return '${_zDepthCtrl.text.trim()} x ${_zFlangeCtrl.text.trim()} x ${_zThicknessCtrl.text.trim()} mm Z-purlin';
//     }
//     if (_isSagMember) {
//       return 'Dia ${_sagDiameterCtrl.text.trim()} mm solid sag rod';
//     }
//     return '${_sizeCtrl.text.trim()} x ${_thicknessCtrl.text.trim()} mm CHS';
//   }

//   @override
//   void initState() {
//     super.initState();
//     _boq = widget.initialBoq;

//     final defaults = widget.initialSessionDefaults;
//     if (defaults != null) {
//       final savedType = defaults['memberType']?.toString();
//       for (final type in _RoofMemberType.values) {
//         if (type.name == savedType) {
//           _type = type;
//           break;
//         }
//       }

//       _setController(_sizeCtrl, defaults['sizeMm']);
//       _setController(_thicknessCtrl, defaults['thicknessMm']);
//       _setController(_zDepthCtrl, defaults['zDepthMm']);
//       _setController(_zFlangeCtrl, defaults['zFlangeMm']);
//       _setController(_zThicknessCtrl, defaults['zThicknessMm']);
//       _setController(_sagDiameterCtrl, defaults['sagDiameterMm']);
//       _setController(_piecesCtrl, defaults['pieces']);
//       _setController(_trussCountCtrl, defaults['trussCount']);
//       _setController(_factorCtrl, defaults['factor']);
//     }
//   }

//   void _setController(TextEditingController controller, dynamic value) {
//     if (value != null && value.toString().trim().isNotEmpty) {
//       controller.text = value.toString();
//     }
//   }

//   @override
//   void dispose() {
//     _markCtrl.dispose();
//     _sizeCtrl.dispose();
//     _thicknessCtrl.dispose();
//     _zDepthCtrl.dispose();
//     _zFlangeCtrl.dispose();
//     _zThicknessCtrl.dispose();
//     _sagDiameterCtrl.dispose();
//     _piecesCtrl.dispose();
//     _trussCountCtrl.dispose();
//     _factorCtrl.dispose();
//     _notesCtrl.dispose();
//     super.dispose();
//   }

//   Future<void> _pickBoq() async {
//     final pick = await showDialog<BoqPick>(
//       context: context,
//       builder:
//           (_) => BoqPickerDialog(
//             projectId: widget.projectId,
//             buildingId: widget.buildingId,
//           ),
//     );
//     if (pick != null && mounted) {
//       setState(() {
//         _boq = pick;
//         _error = null;
//       });
//     }
//   }

//   void _useLastBoq() {
//     final lastBoq = widget.lastBoq;
//     if (lastBoq == null) return;
//     setState(() {
//       _boq = lastBoq;
//       _error = null;
//     });
//   }

//   Map<String, dynamic> _sessionDefaults() => {
//     'memberType': _type.name,
//     'sizeMm': _sizeCtrl.text.trim(),
//     'thicknessMm': _thicknessCtrl.text.trim(),
//     'zDepthMm': _zDepthCtrl.text.trim(),
//     'zFlangeMm': _zFlangeCtrl.text.trim(),
//     'zThicknessMm': _zThicknessCtrl.text.trim(),
//     'sagDiameterMm': _sagDiameterCtrl.text.trim(),
//     'pieces': _piecesCtrl.text.trim(),
//     'trussCount': _trussCountCtrl.text.trim(),
//     'factor': _factorCtrl.text.trim(),
//   };

//   String? _positive(String? value) =>
//       (double.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;

//   String? _positiveInt(String? value) =>
//       (int.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;

//   String? _chsThicknessValidator(String? value) {
//     final t = double.tryParse((value ?? '').trim()) ?? 0;
//     final d = _number(_sizeCtrl);
//     if (t <= 0) return 'Required';
//     if (d > 0 && 2 * t >= d) return 'Thickness is too large';
//     return null;
//   }

//   Future<void> _save(RoofMemberSaveAction action) async {
//     if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
//     if (_boq == null) {
//       setState(() => _error = 'Select the BOQ item for this member.');
//       return;
//     }
//     if (_kgPerM <= 0) {
//       setState(() => _error = 'Enter valid member dimensions.');
//       return;
//     }

//     setState(() {
//       _saving = true;
//       _error = null;
//     });

//     try {
//       final ref = widget.measurementsRef.doc();
//       await ref.set({
//         'projectId': widget.projectId,
//         'buildingId': widget.buildingId,
//         'drawingId': widget.drawingId,
//         'drawingTitle': widget.drawingTitle,
//         'roofGroupId': widget.chainId,
//         'measureType': 'roofStructureMember',
//         'type': _type.name,
//         'memberType': _type.name,
//         'memberTypeLabel': _type.label,
//         'memberMark': _markCtrl.text.trim(),
//         'label':
//             _markCtrl.text.trim().isEmpty
//                 ? _type.label
//                 : '${_type.label} - ${_markCtrl.text.trim()}',
//         'section': _sectionDescription,
//         'sizeMm': _isChsMember ? _number(_sizeCtrl) : null,
//         'thicknessMm': _isChsMember ? _number(_thicknessCtrl) : null,
//         'zDepthMm': _isZPurlin ? _number(_zDepthCtrl) : null,
//         'zFlangeMm': _isZPurlin ? _number(_zFlangeCtrl) : null,
//         'zThicknessMm': _isZPurlin ? _number(_zThicknessCtrl) : null,
//         'sagDiameterMm': _isSagMember ? _number(_sagDiameterCtrl) : null,
//         'lengthM': widget.measuredLengthM,
//         'measuredLengthM': widget.measuredLengthM,
//         'piecesPerTruss': _pieces,
//         'trussCount': _trussCount,
//         'multiplyingFactor': _factor,
//         'totalLengthM': _totalLength,
//         'kgPerM': _kgPerM,
//         'unit': 'kg',
//         'value': _totalWeight,
//         'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
//         'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
//         'segment': {
//           'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
//           'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
//         },
//         'segmentIndex': widget.segmentIndex,
//         'boqItemId': _boq!.id,
//         'boqCode': _boq!.code,
//         'boqDescription': _boq!.description,
//         'notes': _notesCtrl.text.trim(),
//         'color': widget.color.value,
//         'createdAt': FieldValue.serverTimestamp(),
//         'updatedAt': FieldValue.serverTimestamp(),
//       });

//       if (mounted) {
//         Navigator.pop(
//           context,
//           RoofMemberMeasurementResult(
//             action: action,
//             boq: _boq,
//             sessionDefaults: _sessionDefaults(),
//           ),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _saving = false;
//           _error = 'Could not save member: $e';
//         });
//       }
//     }
//   }

//   Widget _numberField({
//     required TextEditingController controller,
//     required String label,
//     String? hint,
//     String? Function(String?)? validator,
//   }) {
//     return TextFormField(
//       controller: controller,
//       keyboardType: const TextInputType.numberWithOptions(decimal: true),
//       decoration: InputDecoration(
//         labelText: label,
//         hintText: hint,
//         suffixText: 'mm',
//       ),
//       validator: validator ?? _positive,
//       onChanged: (_) => setState(() {}),
//     );
//   }

//   Widget _dimensionInputs() {
//     if (_isZPurlin) {
//       return Row(
//         children: [
//           Expanded(
//             child: _numberField(
//               controller: _zDepthCtrl,
//               label: 'Depth',
//               hint: '152',
//             ),
//           ),
//           const SizedBox(width: 10),
//           Expanded(
//             child: _numberField(
//               controller: _zFlangeCtrl,
//               label: 'Flange',
//               hint: '75',
//             ),
//           ),
//           const SizedBox(width: 10),
//           Expanded(
//             child: _numberField(
//               controller: _zThicknessCtrl,
//               label: 'Thickness',
//               hint: '3',
//             ),
//           ),
//         ],
//       );
//     }

//     if (_isSagMember) {
//       return _numberField(
//         controller: _sagDiameterCtrl,
//         label: 'Sag member diameter',
//         hint: '12',
//       );
//     }

//     return Row(
//       children: [
//         Expanded(
//           child: _numberField(
//             controller: _sizeCtrl,
//             label: 'CHS outside diameter / size',
//             hint: '60.3',
//           ),
//         ),
//         const SizedBox(width: 10),
//         Expanded(
//           child: _numberField(
//             controller: _thicknessCtrl,
//             label: 'Wall thickness',
//             hint: '3.2',
//             validator: _chsThicknessValidator,
//           ),
//         ),
//       ],
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: const Row(
//         children: [
//           Icon(Icons.change_history_rounded, color: AqsColors.primary),
//           SizedBox(width: 10),
//           Text('Record roof member'),
//         ],
//       ),
//       content: SizedBox(
//         width: 760,
//         child: Form(
//           key: _formKey,
//           child: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 _LiveMeasurement(
//                   measuredLengthM: widget.measuredLengthM,
//                   totalLengthM: _totalLength,
//                   totalWeightKg: _totalWeight,
//                 ),
//                 const SizedBox(height: 14),
//                 Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: AqsColors.canvas,
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(color: AqsColors.border),
//                   ),
//                   child: Wrap(
//                     spacing: 8,
//                     runSpacing: 8,
//                     children:
//                         _RoofMemberType.values.map((type) {
//                           return ChoiceChip(
//                             label: Text(type.label),
//                             selected: _type == type,
//                             onSelected:
//                                 _saving
//                                     ? null
//                                     : (_) => setState(() {
//                                       _type = type;
//                                       _error = null;
//                                     }),
//                           );
//                         }).toList(),
//                   ),
//                 ),
//                 const SizedBox(height: 14),
//                 _dimensionInputs(),
//                 const SizedBox(height: 12),
//                 Container(
//                   width: double.infinity,
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(color: AqsColors.border),
//                   ),
//                   child: Wrap(
//                     spacing: 24,
//                     runSpacing: 8,
//                     children: [
//                       Text(
//                         'Section: $_sectionDescription',
//                         style: const TextStyle(fontWeight: FontWeight.w600),
//                       ),
//                       Text(
//                         'Weight/m: ${_kgPerM.toStringAsFixed(2)} kg/m',
//                         style: const TextStyle(fontWeight: FontWeight.w700),
//                       ),
//                       Text(
//                         'Total: ${_totalWeight.toStringAsFixed(2)} kg',
//                         style: const TextStyle(fontWeight: FontWeight.w700),
//                       ),
//                     ],
//                   ),
//                 ),
//                 if (_isZPurlin) ...[
//                   const SizedBox(height: 6),
//                   const Text(
//                     'Z-purlin kg/m is an estimate from depth + 2 x flange x thickness; lips and corner radii are not included.',
//                     style: TextStyle(fontSize: 12),
//                   ),
//                 ],
//                 if (_isSagMember) ...[
//                   const SizedBox(height: 6),
//                   const Text(
//                     'Sag member estimate assumes a solid round steel rod.',
//                     style: TextStyle(fontSize: 12),
//                   ),
//                 ],
//                 const SizedBox(height: 14),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: TextFormField(
//                         controller: _markCtrl,
//                         decoration: const InputDecoration(
//                           labelText: 'Member mark (optional)',
//                           hintText: 'e.g. TC-01',
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _piecesCtrl,
//                         keyboardType: TextInputType.number,
//                         decoration: const InputDecoration(
//                           labelText: 'Identical pieces / truss',
//                         ),
//                         validator: _positiveInt,
//                         onChanged: (_) => setState(() {}),
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _trussCountCtrl,
//                         keyboardType: TextInputType.number,
//                         decoration: const InputDecoration(
//                           labelText: 'Number of trusses',
//                         ),
//                         validator: _positiveInt,
//                         onChanged: (_) => setState(() {}),
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _factorCtrl,
//                         keyboardType: const TextInputType.numberWithOptions(
//                           decimal: true,
//                         ),
//                         decoration: const InputDecoration(labelText: 'Factor'),
//                         validator: _positive,
//                         onChanged: (_) => setState(() {}),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 14),
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: AqsColors.canvas,
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(
//                       color:
//                           _boq == null
//                               ? const Color(0xFFFDB022)
//                               : AqsColors.border,
//                     ),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         _boq == null
//                             ? 'BOQ item is required'
//                             : '${_boq!.code} — ${_boq!.description}',
//                         maxLines: 2,
//                         overflow: TextOverflow.ellipsis,
//                         style: TextStyle(
//                           color:
//                               _boq == null
//                                   ? const Color(0xFFB54708)
//                                   : AqsColors.text,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                       const SizedBox(height: 10),
//                       Wrap(
//                         spacing: 8,
//                         runSpacing: 8,
//                         children: [
//                           OutlinedButton.icon(
//                             onPressed: _saving ? null : _pickBoq,
//                             icon: const Icon(Icons.search_rounded),
//                             label: Text(
//                               _boq == null ? 'Select BOQ' : 'Change BOQ',
//                             ),
//                           ),
//                           if (widget.lastBoq != null &&
//                               widget.lastBoq!.id != _boq?.id)
//                             FilledButton.tonalIcon(
//                               onPressed: _saving ? null : _useLastBoq,
//                               icon: const Icon(Icons.content_paste_rounded),
//                               label: Text(
//                                 'Use last BOQ (${widget.lastBoq!.code})',
//                               ),
//                             ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 TextFormField(
//                   controller: _notesCtrl,
//                   maxLines: 2,
//                   decoration: const InputDecoration(labelText: 'Notes'),
//                 ),
//                 if (_error != null) ...[
//                   const SizedBox(height: 10),
//                   Text(
//                     _error!,
//                     style: const TextStyle(
//                       color: Color(0xFFB42318),
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed:
//               _saving
//                   ? null
//                   : () => Navigator.pop(
//                     context,
//                     RoofMemberMeasurementResult(
//                       action: RoofMemberSaveAction.cancel,
//                       boq: _boq,
//                       sessionDefaults: _sessionDefaults(),
//                     ),
//                   ),
//           child: const Text('Cancel'),
//         ),
//         FilledButton.icon(
//           onPressed:
//               _saving || _boq == null
//                   ? null
//                   : () => _save(RoofMemberSaveAction.saveAndFinish),
//           icon:
//               _saving
//                   ? const SizedBox(
//                     width: 17,
//                     height: 17,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2,
//                       color: Colors.white,
//                     ),
//                   )
//                   : const Icon(Icons.save_outlined),
//           label: Text(_saving ? 'Saving...' : 'Save'),
//         ),
//       ],
//     );
//   }
// }

enum _RoofMemberType {
  topChord('Top chord'),
  bottomChord('Bottom chord'),
  kingPost('King post'),
  zPurlin('Z-purlin'),
  strut('Strut'),
  sagMember('Sag member');

  const _RoofMemberType(this.label);
  final String label;
}
// class _RoofMemberDialogState extends State<_RoofMemberDialog> {
//   final _formKey = GlobalKey<FormState>();
//   final _markCtrl = TextEditingController();
//   final _sectionCtrl = TextEditingController(text: '168.3 × 8 CHS, S275');
//   final _kgPerMCtrl = TextEditingController(text: '31.6');
//   final _piecesCtrl = TextEditingController(text: '1');
//   final _trussCountCtrl = TextEditingController(text: '9');
//   final _factorCtrl = TextEditingController(text: '1');
//   final _notesCtrl = TextEditingController();
//   final _cleatsQtyCtrl = TextEditingController(text: '2');
//   final _boltsQtyCtrl = TextEditingController(text: '4');
//   final _platesQtyCtrl = TextEditingController(text: '1');
//   final _supportCountCtrl = TextEditingController(text: '2');
//   final _basePlatesQtyCtrl = TextEditingController(text: '1');
//   final _anchorBoltsQtyCtrl = TextEditingController(text: '4');

//   _RoofMemberType _type = _RoofMemberType.topChord;
//   _JointLocation _jointLocation = _JointLocation.none;
//   BoqPick? _boq;
//   BoqPick? _cleatsBoq;
//   BoqPick? _boltsBoq;
//   BoqPick? _platesBoq;
//   BoqPick? _basePlatesBoq;
//   BoqPick? _anchorBoltsBoq;
//   bool _includeCleats = false;
//   bool _includeBolts = false;
//   bool _includePlates = false;
//   bool _includeSupports = false;
//   bool _saving = false;
//   String? _error;

//   double get _kgPerM => double.tryParse(_kgPerMCtrl.text.trim()) ?? 0;
//   int get _pieces => int.tryParse(_piecesCtrl.text.trim()) ?? 0;
//   int get _trussCount => int.tryParse(_trussCountCtrl.text.trim()) ?? 0;
//   double get _factor => double.tryParse(_factorCtrl.text.trim()) ?? 0;
//   double get _totalLength =>
//       widget.measuredLengthM * _pieces * _trussCount * _factor;
//   double get _totalWeight => _totalLength * _kgPerM;
//   bool get _allRequiredBoqsSelected {
//     if (_boq == null) return false;
//     if (_jointLocation != _JointLocation.none) {
//       if (_includeCleats && _cleatsBoq == null) return false;
//       if (_includeBolts && _boltsBoq == null) return false;
//       if (_includePlates && _platesBoq == null) return false;
//     }
//     if (_includeSupports &&
//         (_basePlatesBoq == null || _anchorBoltsBoq == null)) {
//       return false;
//     }
//     return true;
//   }

//   @override
//   void initState() {
//     super.initState();
//     _boq = widget.initialBoq;
//     final defaults = widget.initialSessionDefaults;
//     if (defaults != null) {
//       final savedJointLocation = defaults['jointLocation']?.toString();
//       _jointLocation = _JointLocation.none;
//       for (final location in _JointLocation.values) {
//         if (location.name == savedJointLocation) {
//           _jointLocation = location;
//           break;
//         }
//       }
//       _includeCleats = defaults['includeCleats'] == true;
//       _includeBolts = defaults['includeBolts'] == true;
//       _includePlates = defaults['includePlates'] == true;
//       _includeSupports = defaults['includeSupports'] == true;
//       _cleatsBoq = defaults['cleatsBoq'] as BoqPick?;
//       _boltsBoq = defaults['boltsBoq'] as BoqPick?;
//       _platesBoq = defaults['platesBoq'] as BoqPick?;
//       _basePlatesBoq = defaults['basePlatesBoq'] as BoqPick?;
//       _anchorBoltsBoq = defaults['anchorBoltsBoq'] as BoqPick?;
//       _setController(_cleatsQtyCtrl, defaults['cleatsQty']);
//       _setController(_boltsQtyCtrl, defaults['boltsQty']);
//       _setController(_platesQtyCtrl, defaults['platesQty']);
//       _setController(_supportCountCtrl, defaults['supportCount']);
//       _setController(_basePlatesQtyCtrl, defaults['basePlatesQty']);
//       _setController(_anchorBoltsQtyCtrl, defaults['anchorBoltsQty']);
//       _setController(_trussCountCtrl, defaults['trussCount']);
//       _setController(_factorCtrl, defaults['factor']);
//       _setController(_sectionCtrl, defaults['section']);
//       _setController(_kgPerMCtrl, defaults['kgPerM']);
//       _setController(_piecesCtrl, defaults['pieces']);
//       final savedMemberType = defaults['memberType']?.toString();
//       for (final type in _RoofMemberType.values) {
//         if (type.name == savedMemberType) {
//           _type = type;
//           break;
//         }
//       }
//     }
//   }

//   void _setController(TextEditingController controller, dynamic value) {
//     if (value != null && value.toString().trim().isNotEmpty) {
//       controller.text = value.toString();
//     }
//   }

//   @override
//   void dispose() {
//     _markCtrl.dispose();
//     _sectionCtrl.dispose();
//     _kgPerMCtrl.dispose();
//     _piecesCtrl.dispose();
//     _trussCountCtrl.dispose();
//     _factorCtrl.dispose();
//     _notesCtrl.dispose();
//     _cleatsQtyCtrl.dispose();
//     _boltsQtyCtrl.dispose();
//     _platesQtyCtrl.dispose();
//     _supportCountCtrl.dispose();
//     _basePlatesQtyCtrl.dispose();
//     _anchorBoltsQtyCtrl.dispose();
//     super.dispose();
//   }

//   void _selectType(_RoofMemberType type) {
//     setState(() {
//       _type = type;
//       switch (type) {
//         case _RoofMemberType.cleat:
//           _sectionCtrl.text = '150 × 75 × 5 mm thick angle; 150 mm long';
//           _kgPerMCtrl.text = '8.64';
//           break;
//         case _RoofMemberType.purlinRail:
//           _sectionCtrl.text = '150 × 50 × 20 × 3.0 mm thick Z section';
//           _kgPerMCtrl.text = '6.83';
//           break;
//         case _RoofMemberType.secondaryDiagonal:
//           _sectionCtrl.text = '76.1 × 3 CHS, S275';
//           _kgPerMCtrl.text = '5.41';
//           break;
//         case _RoofMemberType.other:
//           _sectionCtrl.clear();
//           _kgPerMCtrl.clear();
//           break;
//         default:
//           _sectionCtrl.text = '168.3 × 8 CHS, S275';
//           _kgPerMCtrl.text = '31.6';
//           break;
//       }
//       _error = null;
//     });
//   }

//   Future<void> _pickBoq() async {
//     final pick = await showDialog<BoqPick>(
//       context: context,
//       builder:
//           (_) => BoqPickerDialog(
//             projectId: widget.projectId,
//             buildingId: widget.buildingId,
//           ),
//     );
//     if (pick != null && mounted) {
//       setState(() {
//         _boq = pick;
//         _error = null;
//       });
//     }
//   }

//   void _useLastBoq() {
//     final lastBoq = widget.lastBoq;
//     if (lastBoq == null) return;
//     setState(() {
//       _boq = lastBoq;
//       _error = null;
//     });
//   }

//   Future<void> _pickAccessoryBoq(String kind) async {
//     final pick = await showDialog<BoqPick>(
//       context: context,
//       builder:
//           (_) => BoqPickerDialog(
//             projectId: widget.projectId,
//             buildingId: widget.buildingId,
//           ),
//     );
//     if (pick == null || !mounted) return;
//     setState(() {
//       switch (kind) {
//         case 'cleat':
//           _cleatsBoq = pick;
//           break;
//         case 'bolt':
//           _boltsBoq = pick;
//           break;
//         case 'plate':
//           _platesBoq = pick;
//           break;
//         case 'basePlate':
//           _basePlatesBoq = pick;
//           break;
//         case 'anchorBolt':
//           _anchorBoltsBoq = pick;
//           break;
//       }
//       _error = null;
//     });
//   }

//   Map<String, dynamic> _sessionDefaults() => {
//     'jointLocation': _jointLocation.name,
//     'includeCleats': _includeCleats,
//     'includeBolts': _includeBolts,
//     'includePlates': _includePlates,
//     'includeSupports': _includeSupports,
//     'cleatsBoq': _cleatsBoq,
//     'boltsBoq': _boltsBoq,
//     'platesBoq': _platesBoq,
//     'basePlatesBoq': _basePlatesBoq,
//     'anchorBoltsBoq': _anchorBoltsBoq,
//     'cleatsQty': _cleatsQtyCtrl.text.trim(),
//     'boltsQty': _boltsQtyCtrl.text.trim(),
//     'platesQty': _platesQtyCtrl.text.trim(),
//     'supportCount': _supportCountCtrl.text.trim(),
//     'basePlatesQty': _basePlatesQtyCtrl.text.trim(),
//     'anchorBoltsQty': _anchorBoltsQtyCtrl.text.trim(),
//     'trussCount': _trussCountCtrl.text.trim(),
//     'factor': _factorCtrl.text.trim(),
//     'memberType': _type.name,
//     'section': _sectionCtrl.text.trim(),
//     'kgPerM': _kgPerMCtrl.text.trim(),
//     'pieces': _piecesCtrl.text.trim(),
//   };

//   double _qty(TextEditingController controller) =>
//       double.tryParse(controller.text.trim()) ?? 0;

//   Future<void> _save(RoofMemberSaveAction action) async {
//     if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
//     if (_boq == null) {
//       setState(() => _error = 'Select the BOQ item for this member.');
//       return;
//     }
//     if (_jointLocation != _JointLocation.none) {
//       if (_includeCleats && (_cleatsBoq == null || _qty(_cleatsQtyCtrl) <= 0)) {
//         setState(() => _error = 'Select the cleats BOQ item and quantity.');
//         return;
//       }
//       if (_includeBolts && (_boltsBoq == null || _qty(_boltsQtyCtrl) <= 0)) {
//         setState(() => _error = 'Select the bolts BOQ item and quantity.');
//         return;
//       }
//       if (_includePlates && (_platesBoq == null || _qty(_platesQtyCtrl) <= 0)) {
//         setState(
//           () => _error = 'Select the gusset plates BOQ item and quantity.',
//         );
//         return;
//       }
//     }
//     if (_includeSupports &&
//         (_supportCountCtrl.text.trim().isEmpty ||
//             _qty(_supportCountCtrl) <= 0 ||
//             _basePlatesBoq == null ||
//             _anchorBoltsBoq == null ||
//             _qty(_basePlatesQtyCtrl) <= 0 ||
//             _qty(_anchorBoltsQtyCtrl) <= 0)) {
//       setState(
//         () =>
//             _error =
//                 'Complete the support count, base plate and anchor bolt BOQ items.',
//       );
//       return;
//     }

//     setState(() {
//       _saving = true;
//       _error = null;
//     });

//     try {
//       final batch = FirebaseFirestore.instance.batch();
//       final memberRef = widget.measurementsRef.doc();
//       final common = {
//         'projectId': widget.projectId,
//         'buildingId': widget.buildingId,
//         'drawingId': widget.drawingId,
//         'drawingTitle': widget.drawingTitle,
//         'roofGroupId': widget.chainId,
//         'trussCount': _trussCount,
//         'multiplyingFactor': _factor,
//         'color': widget.color.value,
//         'updatedAt': FieldValue.serverTimestamp(),
//       };

//       batch.set(memberRef, {
//         ...common,
//         'measureType': 'roofStructureMember',
//         'type': _type.name,
//         'memberType': _type.name,
//         'memberTypeLabel': _type.label,
//         'memberMark': _markCtrl.text.trim(),
//         'label':
//             _markCtrl.text.trim().isEmpty
//                 ? _type.label
//                 : '${_type.label} - ${_markCtrl.text.trim()}',
//         'section': _sectionCtrl.text.trim(),
//         'lengthM': widget.measuredLengthM,
//         'measuredLengthM': widget.measuredLengthM,
//         'piecesPerTruss': _pieces,
//         'totalLengthM': _totalLength,
//         'kgPerM': _kgPerM,
//         'unit': 'kg',
//         'value': _totalWeight,
//         'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
//         'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
//         'segment': {
//           'p1': {'x': widget.p1.dx, 'y': widget.p1.dy},
//           'p2': {'x': widget.p2.dx, 'y': widget.p2.dy},
//         },
//         'segmentIndex': widget.segmentIndex,
//         'boqItemId': _boq!.id,
//         'boqCode': _boq!.code,
//         'boqDescription': _boq!.description,
//         'notes': _notesCtrl.text.trim(),
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       final joints = <({int index, Offset point})>[];
//       if (_jointLocation == _JointLocation.start ||
//           _jointLocation == _JointLocation.both) {
//         joints.add((index: widget.segmentIndex, point: widget.p1));
//       }
//       if (_jointLocation == _JointLocation.end ||
//           _jointLocation == _JointLocation.both) {
//         joints.add((index: widget.segmentIndex + 1, point: widget.p2));
//       }

//       void saveJointAccessory({
//         required String kind,
//         required String label,
//         required double quantityPerJoint,
//         required BoqPick boq,
//       }) {
//         for (final joint in joints) {
//           final ref = widget.measurementsRef.doc(
//             '${widget.chainId}-joint-${joint.index}-$kind',
//           );
//           batch.set(ref, {
//             ...common,
//             'measureType': 'roofStructureAccessory',
//             'type': kind,
//             'label': label,
//             'jointIndex': joint.index,
//             'jointPoint': {'x': joint.point.dx, 'y': joint.point.dy},
//             'quantityPerJoint': quantityPerJoint,
//             'jointCountPerTruss': 1,
//             'unit': 'Nos',
//             'value': quantityPerJoint * _trussCount * _factor,
//             'boqItemId': boq.id,
//             'boqCode': boq.code,
//             'boqDescription': boq.description,
//             'sourceMemberId': memberRef.id,
//             'createdAt': FieldValue.serverTimestamp(),
//           }, SetOptions(merge: true));
//         }
//       }

//       if (_jointLocation != _JointLocation.none) {
//         if (_includeCleats) {
//           saveJointAccessory(
//             kind: 'cleat',
//             label: 'Cleats',
//             quantityPerJoint: _qty(_cleatsQtyCtrl),
//             boq: _cleatsBoq!,
//           );
//         }
//         if (_includeBolts) {
//           saveJointAccessory(
//             kind: 'bolt',
//             label: 'Connection bolts',
//             quantityPerJoint: _qty(_boltsQtyCtrl),
//             boq: _boltsBoq!,
//           );
//         }
//         if (_includePlates) {
//           saveJointAccessory(
//             kind: 'gussetPlate',
//             label: 'Gusset / connection plates',
//             quantityPerJoint: _qty(_platesQtyCtrl),
//             boq: _platesBoq!,
//           );
//         }
//       }

//       void saveSupportAccessory({
//         required String kind,
//         required String label,
//         required double quantityPerSupport,
//         required BoqPick boq,
//       }) {
//         final supportCount = _qty(_supportCountCtrl);
//         final ref = widget.measurementsRef.doc(
//           '${widget.chainId}-support-$kind',
//         );
//         batch.set(ref, {
//           ...common,
//           'measureType': 'roofStructureSupport',
//           'type': kind,
//           'label': label,
//           'supportCountPerTruss': supportCount,
//           'quantityPerSupport': quantityPerSupport,
//           'unit': 'Nos',
//           'value': supportCount * quantityPerSupport * _trussCount * _factor,
//           'boqItemId': boq.id,
//           'boqCode': boq.code,
//           'boqDescription': boq.description,
//           'sourceMemberId': memberRef.id,
//           'createdAt': FieldValue.serverTimestamp(),
//         }, SetOptions(merge: true));
//       }

//       if (_includeSupports) {
//         saveSupportAccessory(
//           kind: 'basePlate',
//           label: 'Base plates',
//           quantityPerSupport: _qty(_basePlatesQtyCtrl),
//           boq: _basePlatesBoq!,
//         );
//         saveSupportAccessory(
//           kind: 'anchorBolt',
//           label: 'Anchor / holding-down bolts',
//           quantityPerSupport: _qty(_anchorBoltsQtyCtrl),
//           boq: _anchorBoltsBoq!,
//         );
//       }

//       await batch.commit();
//       if (mounted) {
//         Navigator.pop(
//           context,
//           RoofMemberMeasurementResult(
//             action: action,
//             boq: _boq,
//             sessionDefaults: _sessionDefaults(),
//           ),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _saving = false;
//           _error = 'Could not save member: $e';
//         });
//       }
//     }
//   }

//   String? _positive(String? value) =>
//       (double.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;
//   String? _positiveInt(String? value) =>
//       (int.tryParse((value ?? '').trim()) ?? 0) <= 0 ? 'Required' : null;

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: const Row(
//         children: [
//           Icon(Icons.change_history_rounded, color: AqsColors.primary),
//           SizedBox(width: 10),
//           Text('Record roof member'),
//         ],
//       ),
//       content: SizedBox(
//         width: 780,
//         child: Form(
//           key: _formKey,
//           child: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 _LiveMeasurement(
//                   measuredLengthM: widget.measuredLengthM,
//                   totalLengthM: _totalLength,
//                   totalWeightKg: _totalWeight,
//                 ),
//                 const SizedBox(height: 18),
//                 DropdownButtonFormField<_RoofMemberType>(
//                   value: _type,
//                   decoration: const InputDecoration(
//                     labelText: 'Member classification',
//                   ),
//                   items:
//                       _RoofMemberType.values
//                           .map(
//                             (type) => DropdownMenuItem(
//                               value: type,
//                               child: Text(type.label),
//                             ),
//                           )
//                           .toList(),
//                   onChanged:
//                       _saving
//                           ? null
//                           : (value) {
//                             if (value != null) _selectType(value);
//                           },
//                 ),
//                 const SizedBox(height: 12),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: TextFormField(
//                         controller: _markCtrl,
//                         decoration: const InputDecoration(
//                           labelText: 'Member mark (optional)',
//                           hintText: 'e.g. TC-01 or D-06',
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _sectionCtrl,
//                         decoration: const InputDecoration(
//                           labelText: 'Section / size',
//                         ),
//                         validator:
//                             (value) =>
//                                 (value ?? '').trim().isEmpty
//                                     ? 'Enter member size'
//                                     : null,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 12),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: TextFormField(
//                         controller: _kgPerMCtrl,
//                         keyboardType: const TextInputType.numberWithOptions(
//                           decimal: true,
//                         ),
//                         decoration: const InputDecoration(labelText: 'kg/m'),
//                         onChanged: (_) => setState(() {}),
//                         validator: _positive,
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _piecesCtrl,
//                         keyboardType: TextInputType.number,
//                         decoration: const InputDecoration(
//                           labelText: 'Identical pieces / truss',
//                         ),
//                         onChanged: (_) => setState(() {}),
//                         validator: _positiveInt,
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _trussCountCtrl,
//                         keyboardType: TextInputType.number,
//                         decoration: const InputDecoration(
//                           labelText: 'Number of trusses',
//                         ),
//                         onChanged: (_) => setState(() {}),
//                         validator: _positiveInt,
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: TextFormField(
//                         controller: _factorCtrl,
//                         keyboardType: const TextInputType.numberWithOptions(
//                           decimal: true,
//                         ),
//                         decoration: const InputDecoration(labelText: 'Factor'),
//                         onChanged: (_) => setState(() {}),
//                         validator: _positive,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 14),
//                 _ConnectionAccessories(
//                   enabled: !_saving,
//                   jointLocation: _jointLocation,
//                   onJointLocationChanged:
//                       (value) => setState(() => _jointLocation = value),
//                   includeCleats: _includeCleats,
//                   includeBolts: _includeBolts,
//                   includePlates: _includePlates,
//                   cleatsQtyCtrl: _cleatsQtyCtrl,
//                   boltsQtyCtrl: _boltsQtyCtrl,
//                   platesQtyCtrl: _platesQtyCtrl,
//                   cleatsBoq: _cleatsBoq,
//                   boltsBoq: _boltsBoq,
//                   platesBoq: _platesBoq,
//                   onCleatsChanged:
//                       (value) => setState(() => _includeCleats = value),
//                   onBoltsChanged:
//                       (value) => setState(() => _includeBolts = value),
//                   onPlatesChanged:
//                       (value) => setState(() => _includePlates = value),
//                   onPickBoq: _pickAccessoryBoq,
//                 ),
//                 const SizedBox(height: 14),
//                 _SupportAccessories(
//                   enabled: !_saving,
//                   included: _includeSupports,
//                   onIncludedChanged:
//                       (value) => setState(() => _includeSupports = value),
//                   supportCountCtrl: _supportCountCtrl,
//                   basePlatesQtyCtrl: _basePlatesQtyCtrl,
//                   anchorBoltsQtyCtrl: _anchorBoltsQtyCtrl,
//                   basePlatesBoq: _basePlatesBoq,
//                   anchorBoltsBoq: _anchorBoltsBoq,
//                   onPickBoq: _pickAccessoryBoq,
//                 ),
//                 const SizedBox(height: 14),
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: AqsColors.canvas,
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(
//                       color:
//                           _boq == null
//                               ? const Color(0xFFFDB022)
//                               : AqsColors.border,
//                     ),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         _boq == null
//                             ? 'BOQ item is required'
//                             : '${_boq!.code} — ${_boq!.description}',
//                         maxLines: 2,
//                         overflow: TextOverflow.ellipsis,
//                         style: TextStyle(
//                           color:
//                               _boq == null
//                                   ? const Color(0xFFB54708)
//                                   : AqsColors.text,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                       const SizedBox(height: 10),
//                       Wrap(
//                         spacing: 8,
//                         runSpacing: 8,
//                         children: [
//                           OutlinedButton.icon(
//                             onPressed: _saving ? null : _pickBoq,
//                             icon: const Icon(Icons.search_rounded),
//                             label: Text(
//                               _boq == null ? 'Select BOQ' : 'Change BOQ',
//                             ),
//                           ),
//                           if (widget.lastBoq != null &&
//                               widget.lastBoq!.id != _boq?.id)
//                             FilledButton.tonalIcon(
//                               onPressed: _saving ? null : _useLastBoq,
//                               icon: const Icon(Icons.content_paste_rounded),
//                               label: Text(
//                                 'Use last BOQ (${widget.lastBoq!.code})',
//                               ),
//                             ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 TextFormField(
//                   controller: _notesCtrl,
//                   maxLines: 2,
//                   decoration: const InputDecoration(labelText: 'Notes'),
//                 ),
//                 if (_error != null) ...[
//                   const SizedBox(height: 10),
//                   Text(
//                     _error!,
//                     style: const TextStyle(
//                       color: Color(0xFFB42318),
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed:
//               _saving
//                   ? null
//                   : () => Navigator.pop(
//                     context,
//                     RoofMemberMeasurementResult(
//                       action: RoofMemberSaveAction.cancel,
//                       boq: _boq,
//                       sessionDefaults: _sessionDefaults(),
//                     ),
//                   ),
//           child: const Text('Cancel'),
//         ),
//         FilledButton.icon(
//           onPressed:
//               _saving || !_allRequiredBoqsSelected
//                   ? null
//                   : () => _save(RoofMemberSaveAction.saveAndFinish),
//           icon:
//               _saving
//                   ? const SizedBox(
//                     width: 17,
//                     height: 17,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2,
//                       color: Colors.white,
//                     ),
//                   )
//                   : const Icon(Icons.save_outlined),
//           label: Text(_saving ? 'Saving…' : 'Save'),
//         ),
//       ],
//     );
//   }
// }

enum _JointLocation {
  none('No joint accessories'),
  start('Start joint'),
  end('End joint'),
  both('Both joints');

  const _JointLocation(this.label);
  final String label;
}

class _ConnectionAccessories extends StatelessWidget {
  const _ConnectionAccessories({
    required this.enabled,
    required this.jointLocation,
    required this.onJointLocationChanged,
    required this.includeCleats,
    required this.includeBolts,
    required this.includePlates,
    required this.cleatsQtyCtrl,
    required this.boltsQtyCtrl,
    required this.platesQtyCtrl,
    required this.cleatsBoq,
    required this.boltsBoq,
    required this.platesBoq,
    required this.onCleatsChanged,
    required this.onBoltsChanged,
    required this.onPlatesChanged,
    required this.onPickBoq,
  });

  final bool enabled;
  final _JointLocation jointLocation;
  final ValueChanged<_JointLocation> onJointLocationChanged;
  final bool includeCleats;
  final bool includeBolts;
  final bool includePlates;
  final TextEditingController cleatsQtyCtrl;
  final TextEditingController boltsQtyCtrl;
  final TextEditingController platesQtyCtrl;
  final BoqPick? cleatsBoq;
  final BoqPick? boltsBoq;
  final BoqPick? platesBoq;
  final ValueChanged<bool> onCleatsChanged;
  final ValueChanged<bool> onBoltsChanged;
  final ValueChanged<bool> onPlatesChanged;
  final ValueChanged<String> onPickBoq;

  @override
  Widget build(BuildContext context) {
    final active = jointLocation != _JointLocation.none;
    return _AccessoryPanel(
      title: 'Joint accessories',
      subtitle:
          'Attach cleats, bolts and plates to this segment’s joints. Shared joints are counted once.',
      child: Column(
        children: [
          DropdownButtonFormField<_JointLocation>(
            value: jointLocation,
            decoration: const InputDecoration(
              labelText: 'Apply accessories at',
            ),
            items:
                _JointLocation.values
                    .map(
                      (location) => DropdownMenuItem(
                        value: location,
                        child: Text(location.label),
                      ),
                    )
                    .toList(),
            onChanged:
                enabled
                    ? (value) {
                      if (value != null) onJointLocationChanged(value);
                    }
                    : null,
          ),
          if (active) ...[
            const SizedBox(height: 10),
            _AccessoryRow(
              enabled: enabled,
              selected: includeCleats,
              label: 'Cleats',
              quantityLabel: 'Cleats / joint',
              quantityCtrl: cleatsQtyCtrl,
              boq: cleatsBoq,
              onSelected: onCleatsChanged,
              onPickBoq: () => onPickBoq('cleat'),
            ),
            _AccessoryRow(
              enabled: enabled,
              selected: includeBolts,
              label: 'Connection bolts',
              quantityLabel: 'Bolts / joint',
              quantityCtrl: boltsQtyCtrl,
              boq: boltsBoq,
              onSelected: onBoltsChanged,
              onPickBoq: () => onPickBoq('bolt'),
            ),
            _AccessoryRow(
              enabled: enabled,
              selected: includePlates,
              label: 'Gusset / connection plates',
              quantityLabel: 'Plates / joint',
              quantityCtrl: platesQtyCtrl,
              boq: platesBoq,
              onSelected: onPlatesChanged,
              onPickBoq: () => onPickBoq('plate'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportAccessories extends StatelessWidget {
  const _SupportAccessories({
    required this.enabled,
    required this.included,
    required this.onIncludedChanged,
    required this.supportCountCtrl,
    required this.basePlatesQtyCtrl,
    required this.anchorBoltsQtyCtrl,
    required this.basePlatesBoq,
    required this.anchorBoltsBoq,
    required this.onPickBoq,
  });

  final bool enabled;
  final bool included;
  final ValueChanged<bool> onIncludedChanged;
  final TextEditingController supportCountCtrl;
  final TextEditingController basePlatesQtyCtrl;
  final TextEditingController anchorBoltsQtyCtrl;
  final BoqPick? basePlatesBoq;
  final BoqPick? anchorBoltsBoq;
  final ValueChanged<String> onPickBoq;

  @override
  Widget build(BuildContext context) {
    return _AccessoryPanel(
      title: 'Support connections',
      subtitle:
          'Record these once for the truss session, normally at the two bearing points.',
      trailing: Switch(
        value: included,
        onChanged: enabled ? onIncludedChanged : null,
      ),
      child:
          included
              ? Column(
                children: [
                  TextFormField(
                    controller: supportCountCtrl,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Supports per truss',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _BoqQuantityRow(
                    enabled: enabled,
                    label: 'Base plates',
                    quantityLabel: 'Plates / support',
                    quantityCtrl: basePlatesQtyCtrl,
                    boq: basePlatesBoq,
                    onPickBoq: () => onPickBoq('basePlate'),
                  ),
                  _BoqQuantityRow(
                    enabled: enabled,
                    label: 'Anchor / holding-down bolts',
                    quantityLabel: 'Bolts / support',
                    quantityCtrl: anchorBoltsQtyCtrl,
                    boq: anchorBoltsBoq,
                    onPickBoq: () => onPickBoq('anchorBolt'),
                  ),
                ],
              )
              : const SizedBox.shrink(),
    );
  }
}

class _AccessoryPanel extends StatelessWidget {
  const _AccessoryPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AccessoryRow extends StatelessWidget {
  const _AccessoryRow({
    required this.enabled,
    required this.selected,
    required this.label,
    required this.quantityLabel,
    required this.quantityCtrl,
    required this.boq,
    required this.onSelected,
    required this.onPickBoq,
  });

  final bool enabled;
  final bool selected;
  final String label;
  final String quantityLabel;
  final TextEditingController quantityCtrl;
  final BoqPick? boq;
  final ValueChanged<bool> onSelected;
  final VoidCallback onPickBoq;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: selected,
          onChanged: enabled ? (value) => onSelected(value ?? false) : null,
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (selected)
          _BoqQuantityRow(
            enabled: enabled,
            label: label,
            quantityLabel: quantityLabel,
            quantityCtrl: quantityCtrl,
            boq: boq,
            onPickBoq: onPickBoq,
          ),
      ],
    );
  }
}

class _BoqQuantityRow extends StatelessWidget {
  const _BoqQuantityRow({
    required this.enabled,
    required this.label,
    required this.quantityLabel,
    required this.quantityCtrl,
    required this.boq,
    required this.onPickBoq,
  });

  final bool enabled;
  final String label;
  final String quantityLabel;
  final TextEditingController quantityCtrl;
  final BoqPick? boq;
  final VoidCallback onPickBoq;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: quantityCtrl,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: quantityLabel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              boq == null
                  ? '$label BOQ item not selected'
                  : '${boq!.code} — ${boq!.description}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: boq == null ? const Color(0xFFB54708) : AqsColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: enabled ? onPickBoq : null,
            child: Text(boq == null ? 'Select BOQ' : 'Change'),
          ),
        ],
      ),
    );
  }
}

class _LiveMeasurement extends StatelessWidget {
  const _LiveMeasurement({
    required this.measuredLengthM,
    required this.totalLengthM,
    required this.totalWeightKg,
  });

  final double measuredLengthM;
  final double totalLengthM;
  final double totalWeightKg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AqsColors.primaryDark, Color(0xFF17448A)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 260,
            child: Row(
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    label: 'Length measured on drawing',
                    value: measuredLengthM,
                    unit: 'm',
                    prominent: true,
                  ),
                ),
              ],
            ),
          ),
          _Metric(label: 'Total length', value: totalLengthM, unit: 'm'),
          _Metric(label: 'Calculated weight', value: totalWeightKg, unit: 'kg'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    this.prominent = false,
  });

  final String label;
  final double value;
  final String unit;
  final bool prominent;

  String get _formattedValue {
    if (!value.isFinite) return '—';
    if (value == 0) return '0.000';
    if (value.abs() < 0.001) return value.toStringAsFixed(6);
    return value.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFBFD2FA), fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            '$_formattedValue $unit',
            style: TextStyle(
              color: Colors.white,
              fontSize: prominent ? 24 : 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// enum _RoofMemberType {
//   topChord('Top chord'),
//   bottomChord('Bottom chord'),
//   vertical('Vertical member'),
//   mainDiagonal('Main diagonal member'),
//   secondaryDiagonal('Secondary diagonal member'),
//   cleat('Cleats'),
//   purlinRail('Purlins and rails'),
//   other('Other member');

//   const _RoofMemberType(this.label);
//   final String label;
// }
