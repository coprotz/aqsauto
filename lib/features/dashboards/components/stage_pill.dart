import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class StagePill extends StatelessWidget {
  final ProjectStage stage;
  const StagePill({required this.stage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: stage.background(cs),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
          color: stage.foreground(cs),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}
