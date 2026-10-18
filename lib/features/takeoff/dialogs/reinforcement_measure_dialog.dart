import 'package:aqs/features/takeoff/models/reinforcement_callout.dart';
import 'package:flutter/material.dart';

class ReinforcementMeasurementDialog extends StatefulWidget {
  const ReinforcementMeasurementDialog({
    super.key,
    required this.callout,
    required this.measuredLengthM,
  });

  final ReinforcementCallout callout;
  final double measuredLengthM;

  @override
  State<ReinforcementMeasurementDialog> createState() =>
      _ReinforcementMeasurementDialogState();
}

class _ReinforcementMeasurementDialogState
    extends State<ReinforcementMeasurementDialog> {
  double get _lengthEachM => widget.measuredLengthM;

  double get _totalLengthM => widget.callout.quantity * _lengthEachM;

  double get _kgPerM => widget.callout.kgPerM;

  double get _totalWeightKg => _totalLengthM * _kgPerM;

  @override
  Widget build(BuildContext context) {
    final bar = widget.callout;

    return AlertDialog(
      title: const Text('Record reinforcement'),
      content: SizedBox(
        width: 650,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bar.raw,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _info('Quantity', '${bar.quantity}'),
                _info('Diameter', bar.diameterLabel),
                _info('Bar mark', bar.barMark),
                _info('Spacing', '${bar.spacingMm.toStringAsFixed(0)} mm'),
                _info('Layer', bar.layer),
                _info('Weight/m', '${_kgPerM.toStringAsFixed(3)} kg/m'),
              ],
            ),

            const Divider(height: 32),

            _info('Length each', '${_lengthEachM.toStringAsFixed(3)} m'),

            const SizedBox(height: 12),

            _info('Total length', '${_totalLengthM.toStringAsFixed(3)} m'),

            const SizedBox(height: 12),

            Text(
              'Calculated weight: '
              '${_totalWeightKg.toStringAsFixed(2)} kg',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              ReinforcementMeasurementResult(
                callout: bar,
                lengthEachM: _lengthEachM,
                totalLengthM: _totalLengthM,
                kgPerM: _kgPerM,
                totalWeightKg: _totalWeightKg,
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _info(String label, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class ReinforcementMeasurementResult {
  const ReinforcementMeasurementResult({
    required this.callout,
    required this.lengthEachM,
    required this.totalLengthM,
    required this.kgPerM,
    required this.totalWeightKg,
  });

  final ReinforcementCallout callout;
  final double lengthEachM;
  final double totalLengthM;
  final double kgPerM;
  final double totalWeightKg;
}
