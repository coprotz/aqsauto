import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:flutter/material.dart';

class TableHeader extends StatelessWidget {
  const TableHeader();

  @override
  Widget build(BuildContext context) {
    final t = TextStyle(
      color: AqsColors.muted,
      fontWeight: FontWeight.w800,
      fontSize: 12,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: AqsColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Project', style: t)),
          Expanded(flex: 3, child: Text('Client', style: t)),
          Expanded(flex: 3, child: Text('Stage', style: t)),
          Expanded(flex: 2, child: Text('Currency', style: t)),
          Expanded(flex: 2, child: Text('Buildings', style: t)),
          Expanded(flex: 2, child: Text('Drawings', style: t)),
          Expanded(flex: 2, child: Text('Measures', style: t)),
          Expanded(flex: 2, child: Text('BOQ Items', style: t)),
          Expanded(flex: 2, child: Text('Created', style: t)),
          const SizedBox(width: 40), // actions menu
        ],
      ),
    );
  }
}
