import 'package:aqs/features/takeoff/models/wall_segment.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WallingDetailsDialog extends StatelessWidget {
  final WallGroup group;
  const WallingDetailsDialog({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Walling Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Label: ${group.label}'),
          Text('Height: ${group.heightM.toStringAsFixed(2)} m'),
          Text('Segments: ${group.segments.length}'),
          Text('Total Length: ${group.totalLengthM.toStringAsFixed(2)} m'),
          Text('Area: ${group.areaM2.toStringAsFixed(2)} m²'),
          const SizedBox(height: 8),
          Text('ID: ${group.id}', style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Close')),
      ],
    );
  }
}
