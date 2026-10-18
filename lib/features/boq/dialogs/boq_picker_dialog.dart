import 'package:aqs/features/boq/models/boq_pick.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// class BoqPick {
//   final String id; // ✅ boq docId
//   final String code; // resolvedBoqCode
//   final String description;
//   String? unit;

//   BoqPick({
//     required this.id,
//     required this.code,
//     required this.description,
//     this.unit,
//   });
// }

// Future<BoqPick?> pickBoqItemDialog({
//   required String projectId,
//   required String buildingId,
// }) async {
//   final boqRef = FirebaseFirestore.instance
//       .collection('projects')
//       .doc(projectId)
//       .collection('buildings')
//       .doc(buildingId)
//       .collection('boq');

//   return Get.dialog<BoqPick>(
//     Dialog(
//       child: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
//         child: StatefulBuilder(
//           builder: (_, setState) {
//             String q = '';

//             return Padding(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       const Expanded(
//                         child: Text(
//                           'Pick BOQ Item',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.w700,
//                           ),
//                         ),
//                       ),
//                       IconButton(
//                         onPressed: () => Get.back(result: null),
//                         icon: const Icon(Icons.close),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 8),
//                   TextField(
//                     decoration: const InputDecoration(
//                       prefixIcon: Icon(Icons.search),
//                       labelText: 'Search code or description',
//                     ),
//                     onChanged:
//                         (v) => setState(() => q = v.trim().toLowerCase()),
//                   ),
//                   const SizedBox(height: 12),
//                   Expanded(
//                     child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                       stream:
//                           boqRef
//                               .orderBy('order')
//                               .snapshots(), // if no 'order', change to resolvedBoqCode
//                       builder: (_, snap) {
//                         if (snap.hasError) {
//                           return Center(
//                             child: Text('BOQ load error: ${snap.error}'),
//                           );
//                         }
//                         if (!snap.hasData) {
//                           return const Center(
//                             child: CircularProgressIndicator(),
//                           );
//                         }

//                         final items =
//                             snap.data!.docs
//                                 .map((d) {
//                                   final m = d.data();
//                                   final id = d.id;
//                                   final code =
//                                       (m['resolvedBoqCode'] ?? '')
//                                           .toString()
//                                           .trim();
//                                   final desc =
//                                       (m['description'] ?? '')
//                                           .toString()
//                                           .trim();
//                                   final unit =
//                                       (m['unit'] ?? '').toString().trim();
//                                   return BoqPick(
//                                     id: id,
//                                     code: code,

//                                     description: desc,
//                                   );
//                                 })
//                                 .where(
//                                   (x) =>
//                                       x.code.isNotEmpty &&
//                                       x.description.isNotEmpty,
//                                 )
//                                 .toList();

//                         final filtered =
//                             q.isEmpty
//                                 ? items
//                                 : items.where((x) {
//                                   return x.code.toLowerCase().contains(q) ||
//                                       x.description.toLowerCase().contains(q);
//                                 }).toList();

//                         if (filtered.isEmpty) {
//                           return const Center(
//                             child: Text('No matching BOQ items'),
//                           );
//                         }

//                         return ListView.separated(
//                           itemCount: filtered.length,
//                           separatorBuilder: (_, __) => const Divider(height: 1),
//                           itemBuilder: (_, i) {
//                             final b = filtered[i];
//                             return ListTile(
//                               dense: true,
//                               title: Text(b.code),
//                               subtitle: Text(
//                                 b.description,
//                                 maxLines: 2,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                               onTap: () => Get.back(result: b),
//                             );
//                           },
//                         );
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         ),
//       ),
//     ),
//     barrierDismissible: true,
//   );
// }

// Future<BoqPick?> pickBoqItemDialog({
//   required String projectId,
//   required String buildingId,
// }) async {
//   final boqRef = FirebaseFirestore.instance
//       .collection('projects')
//       .doc(projectId)
//       .collection('buildings')
//       .doc(buildingId)
//       .collection('boq');

//   String _s(dynamic v) => (v ?? '').toString().trim();

//   // Prefer resolvedBoqCode; fallback to displayCode; fallback to boqCode
//   String _bestCode(Map<String, dynamic> m) {
//     final resolved = _s(m['resolvedBoqCode']);
//     if (resolved.isNotEmpty) return resolved;

//     final display = _s(m['displayCode']);
//     if (display.isNotEmpty) return display;

//     return _s(m['boqCode']);
//   }

//   bool _isItemRow(Map<String, dynamic> m) {
//     final rt = _s(m['rowType']).toLowerCase();
//     // if rowType not set (old manual rows), treat it as item if it has code+description
//     if (rt.isEmpty) return true;
//     return rt == 'item';
//   }

//   return Get.dialog<BoqPick>(
//     Dialog(
//       child: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
//         child: StatefulBuilder(
//           builder: (_, setState) {
//             String q = '';

//             return Padding(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       const Expanded(
//                         child: Text(
//                           'Pick BOQ Item',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.w700,
//                           ),
//                         ),
//                       ),
//                       IconButton(
//                         onPressed: () => Get.back(result: null),
//                         icon: const Icon(Icons.close),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 8),
//                   TextField(
//                     decoration: const InputDecoration(
//                       prefixIcon: Icon(Icons.search),
//                       labelText: 'Search code or description',
//                     ),
//                     onChanged:
//                         (v) => setState(() => q = v.trim().toLowerCase()),
//                   ),
//                   const SizedBox(height: 12),
//                   Expanded(
//                     child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                       stream: boqRef.orderBy('order').snapshots(),
//                       builder: (_, snap) {
//                         if (snap.hasError) {
//                           return Center(
//                             child: Text('BOQ load error: ${snap.error}'),
//                           );
//                         }
//                         if (!snap.hasData) {
//                           return const Center(
//                             child: CircularProgressIndicator(),
//                           );
//                         }

//                         final items =
//                             snap.data!.docs
//                                 .map((d) {
//                                   final m = d.data();
//                                   final id = d.id;

//                                   // ✅ skip headings/bills/minors if rowType exists
//                                   if (!_isItemRow(m)) return null;

//                                   final code = _bestCode(m);
//                                   final desc = _s(m['description']);

//                                   // ✅ only require code (description can be empty if you want)
//                                   if (code.isEmpty) return null;

//                                   return BoqPick(
//                                     id: id,
//                                     code: code,
//                                     description: desc,
//                                   );
//                                 })
//                                 .whereType<BoqPick>()
//                                 .toList();

//                         final filtered =
//                             q.isEmpty
//                                 ? items
//                                 : items.where((x) {
//                                   final c = x.code.toLowerCase();
//                                   final d = x.description.toLowerCase();
//                                   return c.contains(q) || d.contains(q);
//                                 }).toList();

//                         if (filtered.isEmpty) {
//                           return const Center(
//                             child: Text('No matching BOQ items'),
//                           );
//                         }

//                         return ListView.separated(
//                           itemCount: filtered.length,
//                           separatorBuilder: (_, __) => const Divider(height: 1),
//                           itemBuilder: (_, i) {
//                             final b = filtered[i];
//                             return ListTile(
//                               dense: true,
//                               title: Text(b.code),
//                               subtitle: Text(
//                                 b.description,
//                                 maxLines: 2,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                               onTap: () => Get.back(result: b),
//                             );
//                           },
//                         );
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         ),
//       ),
//     ),
//     barrierDismissible: true,
//   );
// }
