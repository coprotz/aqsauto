// lib/features/takeoff/takeoff_toolbar.dart
import 'package:flutter/material.dart';
import '../utils/enum.dart';

class TakeoffToolbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final TakeoffMode mode;
  final Color currentColor;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onUndo;
  final VoidCallback onDeleteMode;
  final Future<void> Function() onMeasureLength;
  final Future<void> Function() onMeasureArea;
  final VoidCallback onCalibrate;
  final VoidCallback onView;
  final ValueChanged<Color> onColorChanged;

  const TakeoffToolbar({
    super.key,
    required this.title,
    required this.mode,
    required this.currentColor,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onUndo,
    required this.onDeleteMode,
    required this.onMeasureLength,
    required this.onMeasureArea,
    required this.onCalibrate,
    required this.onView,
    required this.onColorChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: 'Delete a line (tap on it)',
          icon: Icon(
            Icons.delete_sweep,
            color: mode == TakeoffMode.editSegment ? Colors.red : null,
          ),
          onPressed: onDeleteMode,
        ),
        IconButton(
          tooltip: 'Zoom out',
          icon: const Icon(Icons.zoom_out),
          onPressed: onZoomOut,
        ),
        IconButton(
          tooltip: 'Zoom in',
          icon: const Icon(Icons.zoom_in),
          onPressed: onZoomIn,
        ),
        IconButton(
          tooltip: 'Undo last',
          icon: const Icon(Icons.undo),
          onPressed: onUndo,
        ),
        PopupMenuButton<Color>(
          tooltip: 'Measurement color',
          icon: Icon(Icons.color_lens, color: currentColor),
          onSelected: onColorChanged,
          itemBuilder:
              (ctx) => [
                _colorItem(Colors.blue, 'Blue'),
                _colorItem(Colors.red, 'Red'),
                _colorItem(Colors.green, 'Green'),
                _colorItem(Colors.orange, 'Orange'),
                _colorItem(Colors.purple, 'Purple'),
              ],
        ),
        IconButton(
          tooltip: 'View',
          icon: Icon(
            Icons.pan_tool_outlined,
            color: mode == TakeoffMode.view ? Colors.blue : null,
          ),
          onPressed: onView,
        ),
        IconButton(
          tooltip: 'Calibrate',
          icon: Icon(
            Icons.straighten,
            color: mode == TakeoffMode.calibrate ? Colors.blue : null,
          ),
          onPressed: onCalibrate,
        ),
        IconButton(
          tooltip: 'Measure length',
          icon: Icon(
            Icons.timeline,
            color: mode == TakeoffMode.measureLength ? Colors.blue : null,
          ),
          onPressed: () => onMeasureLength(),
        ),
        IconButton(
          tooltip: 'Measure floor / rebar area',
          icon: Icon(
            Icons.crop_square,
            color: mode == TakeoffMode.measureArea ? Colors.blue : null,
          ),
          onPressed: () => onMeasureArea(),
        ),
      ],
    );
  }

  PopupMenuItem<Color> _colorItem(Color c, String label) {
    return PopupMenuItem(
      value: c,
      child: Row(
        children: [
          Icon(Icons.circle, color: c, size: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
