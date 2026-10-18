import 'package:flutter/material.dart';

class MovableDialog extends StatefulWidget {
  const MovableDialog({
    super.key,
    required this.child,
    this.initialOffset = const Offset(0, 0),
  });

  final Widget child;
  final Offset initialOffset;

  @override
  State<MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<MovableDialog> {
  late Offset offset;

  @override
  void initState() {
    super.initState();
    offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => offset += d.delta),
            child: Transform.translate(
              offset: offset,
              child: Center(child: widget.child),
            ),
          ),
        ),
      ],
    );
  }
}
