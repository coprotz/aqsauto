// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';

// class BoqTab extends StatefulWidget {
//   final String projectId;
//   final String buildingId; // 👈 NEW

//   const BoqTab({super.key, required this.projectId, required this.buildingId});

//   @override
//   State<BoqTab> createState() => _BoqTabState();
// }

// class _BoqTabState extends State<BoqTab> {
//   late final CollectionReference<Map<String, dynamic>> _boqRef;
//   late final CollectionReference<Map<String, dynamic>> _measRef;

//   @override
//   void initState() {
//     super.initState();

//     // 🔹 BOQ items now under the building
//     _boqRef = FirebaseFirestore.instance
//         .collection('projects')
//         .doc(widget.projectId)
//         .collection('buildings')
//         .doc(widget.buildingId)
//         .collection('boqItems');

//     // 🔹 Measurements also under the same building
//     _measRef = FirebaseFirestore.instance
//         .collection('projects')
//         .doc(widget.projectId)
//         .collection('buildings')
//         .doc(widget.buildingId)
//         .collection('measurements');
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         // header + add button
//         Padding(
//           padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
//           child: Row(
//             children: [
//               Text('BOQ items', style: Theme.of(context).textTheme.titleMedium),
//               const Spacer(),
//               // FilledButton.icon(
//               //   onPressed: () => _showBoqItemDialog(),
//               //   icon: const Icon(Icons.add),
//               //   label: const Text('Add BOQ item'),
//               // ),
//             ],
//           ),
//         ),
//         const Divider(height: 1),

//         // BOQ list + totals
//         Expanded(
//           child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//             stream: _boqRef.orderBy('order', descending: false).snapshots(),
//             builder: (ctx, boqSnap) {
//               if (boqSnap.hasError) {
//                 return Center(
//                   child: Text('Error loading BOQ items:\n${boqSnap.error}'),
//                 );
//               }

//               if (!boqSnap.hasData) {
//                 return const Center(child: CircularProgressIndicator());
//               }

//               final boqDocs = boqSnap.data!.docs;

//               // If there are no BOQ items yet, show friendly message
//               if (boqDocs.isEmpty) {
//                 return Center(
//                   child: Text(
//                     'No BOQ items yet.\nUse "Add BOQ item" to create one.',
//                     textAlign: TextAlign.center,
//                   ),
//                 );
//               }

//               // Now load all measurements once and aggregate totals by boqCode
//               return Center(
//                 child: ConstrainedBox(
//                   constraints: const BoxConstraints(maxWidth: 1100),
//                   child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                     stream: _measRef.snapshots(),
//                     builder: (ctx, measSnap) {
//                       final totalsByBoq = <String, double>{};
//                       final countByBoq = <String, int>{};

//                       if (measSnap.hasData) {
//                         for (final d in measSnap.data!.docs) {
//                           final m = d.data();
//                           final boqCode = (m['boqCode'] ?? '') as String;
//                           if (boqCode.isEmpty) continue;

//                           final val = m['value'];
//                           if (val == null) continue;

//                           final q = (val as num).toDouble();
//                           totalsByBoq[boqCode] =
//                               (totalsByBoq[boqCode] ?? 0) + q;
//                           countByBoq[boqCode] = (countByBoq[boqCode] ?? 0) + 1;
//                         }
//                       }

//                       return ListView.separated(
//                         itemCount: boqDocs.length,
//                         separatorBuilder: (_, __) => const Divider(height: 1),
//                         itemBuilder: (ctx, index) {
//                           final doc = boqDocs[index];
//                           final data = doc.data();

//                           final code = (data['boqCode'] ?? '') as String;
//                           final desc = (data['description'] ?? '') as String;
//                           final unit = (data['unit'] ?? '') as String;
//                           final rateNum = data['rate'];
//                           final rate =
//                               rateNum != null
//                                   ? (rateNum as num).toDouble()
//                                   : null;

//                           final totalQty = totalsByBoq[code] ?? 0;
//                           final count = countByBoq[code] ?? 0;
//                           final amount =
//                               (rate != null) ? totalQty * rate : null;

//                           return Padding(
//                             padding: const EdgeInsets.all(8.0),
//                             child: ListTile(
//                               dense: false,
//                               title: Text(
//                                 '$code  -  $desc',
//                                 maxLines: 2,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                               subtitle: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     'Qty: ${totalQty.toStringAsFixed(3)} $unit'
//                                     '  (from $count measurements)',
//                                     style: const TextStyle(fontSize: 12),
//                                   ),
//                                   if (rate != null)
//                                     Text(
//                                       'Rate: ${rate.toStringAsFixed(2)} per $unit',
//                                       style: const TextStyle(fontSize: 12),
//                                     ),
//                                   if (amount != null)
//                                     Text(
//                                       'Amount: ${amount.toStringAsFixed(2)}',
//                                       style: const TextStyle(
//                                         fontSize: 12,
//                                         fontWeight: FontWeight.w600,
//                                       ),
//                                     ),
//                                 ],
//                               ),
//                               // trailing: IconButton(
//                               //   icon: const Icon(Icons.edit),
//                               //   onPressed:
//                               //       () => controller.showBoqItemDialog(
//                               //         existingId: doc.id,
//                               //         existingData: data,
//                               //       ),
//                               // ),
//                             ),
//                           );
//                         },
//                       );
//                     },
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),
//       ],
//     );
//   }
// }
