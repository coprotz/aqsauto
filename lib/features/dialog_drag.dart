// import 'package:flutter/material.dart';

// class DraggableDialog extends StatefulWidget {
//   final Widget child;
//   final double maxWidth;

//   const DraggableDialog({super.key, required this.child, this.maxWidth = 560});

//   @override
//   State<DraggableDialog> createState() => _DraggableDialogState();
// }

// class _DraggableDialogState extends State<DraggableDialog> {
//   Offset offset = Offset.zero;

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (_, constraints) {
//         return Stack(
//           children: [
//             // Center + translate
//             Positioned.fill(
//               child: Center(
//                 child: Transform.translate(
//                   offset: offset,
//                   child: ConstrainedBox(
//                     constraints: BoxConstraints(maxWidth: widget.maxWidth),
//                     child: widget.child,
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   // Helper you can use as a drag handle
//   Widget dragHandle({required Widget child}) {
//     return GestureDetector(
//       behavior: HitTestBehavior.opaque,
//       onPanUpdate: (d) => setState(() => offset += d.delta),
//       child: child,
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<T?> showDraggableDialog2<T>({
  required Widget Function(
    BuildContext ctx,
    StateSetter setState,
    Offset offset,
    void Function(Offset newOffset) setOffset,
  )
  builder,
  double width = 640,
  double height = 780,
  bool barrierDismissible = false,
}) {
  Offset offset = Offset.zero;

  return Get.dialog<T>(
    StatefulBuilder(
      builder: (ctx, setState) {
        void setOffset(Offset newOffset) => setState(() => offset = newOffset);

        return Material(
          color: Colors.transparent,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              final left0 = (w - width) / 2;
              final top0 = (h - height) / 2;

              double left = left0 + offset.dx;
              double top = top0 + offset.dy;

              left = left.clamp(
                8.0,
                (w - width - 8.0).clamp(8.0, double.infinity),
              );
              top = top.clamp(
                8.0,
                (h - height - 8.0).clamp(8.0, double.infinity),
              );

              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap:
                          barrierDismissible
                              ? () => Get.back(result: null)
                              : null,
                      child: Container(color: Colors.black.withOpacity(0.10)),
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: Material(
                      elevation: 16,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: builder(ctx, setState, offset, setOffset),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
    barrierDismissible: false,
  );
}
