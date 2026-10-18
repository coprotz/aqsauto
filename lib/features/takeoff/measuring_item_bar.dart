import 'package:aqs/core/state/firestore_state.dart';
// import 'package:aqs/features/takeoff/models/preset_choice.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MeasuringItemBar extends StatelessWidget {
  final String drawingId;
  final CollectionReference<Map<String, dynamic>> measurementsRef;
  final String? activeMeasureType;
  final void Function(String measureType) onMeasureTypeChanged;
  final VoidCallback onConfigurePressed;
  final void Function(TakeoffMode mode)? onModeRequested;

  const MeasuringItemBar({
    super.key,
    required this.drawingId,
    required this.measurementsRef,
    required this.activeMeasureType,
    required this.onMeasureTypeChanged,
    required this.onConfigurePressed,
    this.onModeRequested, // ✅ add
  });

  @override
  Widget build(BuildContext context) {
    final active = (activeMeasureType ?? '').trim();

    debugPrint('activeMeasureType=$active');
    print(activeMeasureType);
    return Expanded(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            measurementsRef
                .where('drawingId', isEqualTo: drawingId)
                .stateSnapshots(),
        builder: (ctx, snap) {
          if (snap.hasError) {
            debugPrint('MeasuringItemBar error: ${snap.error}');
          }

          // Collect distinct measureType values from this drawing
          final types = <String>{};

          if (snap.hasData) {
            for (final d in snap.data!.docs) {
              final m = d.data();
              final t = (m['measureType'] ?? '') as String;
              final trimmed = t.trim();
              if (trimmed.isEmpty) continue;
              types.add(trimmed);
            }
          }
          if (active.isNotEmpty) types.add(active);

          final typeList = types.toList()..sort();

          // final typeList = types.toList()..sort();

          // Resolve current selected value
          // ✅ Use controller selection as source-of-truth
          final String? currentValue = active.isEmpty ? null : active;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value:
                        (currentValue != null &&
                                typeList.contains(currentValue))
                            ? currentValue
                            : (currentValue),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Measuring type (this drawing)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    items:
                        typeList.map((t) {
                          return DropdownMenuItem<String>(
                            value: t,
                            child: Text(_labelForType(t)),
                          );
                        }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final v = value.trim();
                      if (v == active) return;

                      onMeasureTypeChanged(v);

                      // ✅ auto switch tool mode
                      final desiredMode = modeForMeasureType(v);
                      onModeRequested?.call(desiredMode);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Configure BOQ / unit for this type',
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: onConfigurePressed,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _labelForType(String t) {
    final lower = t.toLowerCase();

    // map well-known keys to nice labels
    if (lower == 'walling') return 'Walling';
    if (lower == 'compositefooting') return 'Composite – Footing';
    if (lower == 'compositeslab') return 'Composite – Slab';
    if (lower == 'compositebeam') return 'Composite – Beam';
    if (lower == 'columncomposite') return 'Composite – Column';
    if (lower == 'compositeretainingwall') return 'Composite – Retaining Wall';
    if (lower == 'rebarslab') return 'Rebar – Slab';
    if (lower == 'rebarfooting') return 'Rebar – Footing';
    if (lower == 'tiling') return 'Tiling';
    if (lower == 'pipe') return 'Pipe';
    if (lower == 'beam') return 'Beam';
    if (lower == 'slabedge') return 'Slab edge';
    if (lower == 'roofing') return 'Roofing';
    if (lower == 'window') return 'Window';
    if (lower == 'door') return 'Door';
    if (lower == 'slabrebar') return 'Rebar – Slab';
    if (lower == 'footingrebar') return 'Rebar – Footing';

    // fallback: simple Title Case of the raw value
    return t.isEmpty
        ? 'Other'
        : t
            .split(RegExp(r'[_\s]+'))
            .map(
              (w) =>
                  w.isEmpty
                      ? ''
                      : w[0].toUpperCase() + w.substring(1).toLowerCase(),
            )
            .join(' ');
  }
}
