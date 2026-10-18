// import 'package:aqs/features/takeoff/models/slab_edge_pattern.dart';
// import 'package:flutter/material.dart';

// Widget buildPanelSelector(StateSetter setStateDialog) {
//   // mapping case -> pattern
//   SlabEdgePattern patternForCase(int idx) {
//     switch (idx) {
//       case 1: // top-left corner
//         return const SlabEdgePattern(north: true, west: true);
//       case 2: // top-edge middle
//         return const SlabEdgePattern(north: true);
//       case 3: // top-right corner
//         return const SlabEdgePattern(north: true, east: true);
//       case 4: // mid-left
//         return const SlabEdgePattern(west: true);
//       case 5: // centre – no edges
//         return SlabEdgePattern.none();
//       case 6: // mid-right
//         return const SlabEdgePattern(east: true);
//       case 7: // bottom-left
//         return const SlabEdgePattern(south: true, west: true);
//       case 8: // bottom-middle
//         return const SlabEdgePattern(south: true);
//       case 9: // bottom-right
//         return const SlabEdgePattern(south: true, east: true);
//       default:
//         return SlabEdgePattern.none();
//     }
//   }

//   Widget buildCell(int idx) {
//     SlabEdgePattern edgePattern = SlabEdgePattern.none();
//     // default to 0 edge – panel inside beams
//     int selectedCase = 5; // 1..9 like your sketch

//     final bool isSelected = selectedCase == idx;
//     return Expanded(
//       child: AspectRatio(
//         aspectRatio: 1,
//         child: InkWell(
//           onTap: () {
//             setStateDialog(() {
//               selectedCase = idx;
//               edgePattern = patternForCase(idx);
//             });
//           },
//           child: Container(
//             margin: const EdgeInsets.all(2),
//             decoration: BoxDecoration(
//               border: Border.all(color: Colors.grey.shade400),
//               color: isSelected ? Colors.amber.shade200 : Colors.white,
//             ),
//             child: Center(
//               child: Text(
//                 '$idx',
//                 style: TextStyle(
//                   fontSize: 11,
//                   fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   return Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       const Text(
//         'Edge formwork panel type (like your 1-9 sketch):',
//         style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
//       ),
//       const SizedBox(height: 4),
//       Column(
//         children: [
//           Row(children: [buildCell(1), buildCell(2), buildCell(3)]),
//           Row(children: [buildCell(4), buildCell(5), buildCell(6)]),
//           Row(children: [buildCell(7), buildCell(8), buildCell(9)]),
//         ],
//       ),
//       const SizedBox(height: 4),
//       const Text(
//         'Use 5 for internal panels (no slab edges), '
//         '1/3/7/9 for corners (2 edges), '
//         'and 2/4/6/8 for panels with 1 exposed edge.',
//         style: TextStyle(fontSize: 11, color: Colors.black54),
//       ),
//     ],
//   );
// }
