// import 'package:aqs/features/buildings/views/building_detail_page.dart';
// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

// class ProjectDetailPage extends StatelessWidget {
//   final String projectId;
//   final String projectName;

//   const ProjectDetailPage({
//     super.key,
//     required this.projectId,
//     required this.projectName,
//   });

//   Future<void> _showAddBuildingDialog(BuildContext context) async {
//     final nameController = TextEditingController();
//     final codeController = TextEditingController();

//     await showDialog(
//       context: context,
//       builder: (ctx) {
//         return AlertDialog(
//           title: const Text('Add Building'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               TextField(
//                 controller: nameController,
//                 decoration: const InputDecoration(
//                   labelText: 'Building name',
//                   hintText: 'e.g. Terminal Building',
//                 ),
//               ),
//               TextField(
//                 controller: codeController,
//                 decoration: const InputDecoration(
//                   labelText: 'Code (optional)',
//                   hintText: 'e.g. TB-01',
//                 ),
//               ),
//             ],
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(ctx).pop(),
//               child: const Text('Cancel'),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 final name = nameController.text.trim();
//                 if (name.isEmpty) return;

//                 await FirebaseFirestore.instance
//                     .collection('projects')
//                     .doc(projectId)
//                     .collection('buildings')
//                     .add({
//                       'name': name,
//                       'code': codeController.text.trim(),
//                       'createdAt': FieldValue.serverTimestamp(),
//                     });

//                 // Close dialog
//                 Navigator.of(ctx).pop();
//               },
//               child: const Text('Save'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final buildingsRef = FirebaseFirestore.instance
//         .collection('projects')
//         .doc(projectId)
//         .collection('buildings')
//         .orderBy('createdAt', descending: false);

//     return Scaffold(
//       appBar: AppBar(title: Text(projectName)),
//       body: StreamBuilder<QuerySnapshot>(
//         stream: buildingsRef.snapshots(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           if (snapshot.hasError) {
//             return Center(child: Text('Error: ${snapshot.error}'));
//           }

//           final docs = snapshot.data?.docs ?? [];

//           if (docs.isEmpty) {
//             return Center(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   const Text(
//                     'No buildings yet for this project.',
//                     style: TextStyle(fontSize: 16),
//                   ),
//                   const SizedBox(height: 12),
//                   ElevatedButton.icon(
//                     onPressed: () => _showAddBuildingDialog(context),
//                     icon: const Icon(Icons.add_business),
//                     label: const Text('Create first building'),
//                   ),
//                 ],
//               ),
//             );
//           }

//           return ListView.separated(
//             itemCount: docs.length,
//             separatorBuilder: (_, __) => const Divider(height: 0),
//             itemBuilder: (context, index) {
//               final doc = docs[index];
//               final data = doc.data() as Map<String, dynamic>;
//               final buildingId = doc.id;
//               final name = data['name'] ?? 'Unnamed building';
//               final code = (data['code'] ?? '') as String;

//               return ListTile(
//                 leading: const Icon(Icons.apartment),
//                 title: Text(name),
//                 subtitle: code.isNotEmpty ? Text(code) : null,
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () {
//                   Navigator.of(context).push(
//                     MaterialPageRoute(
//                       builder:
//                           (_) => BuildingDetailPage(
//                             projectId: projectId,
//                             buildingId: buildingId,
//                             buildingName: name,
//                           ),
//                     ),
//                   );
//                 },
//               );
//             },
//           );
//         },
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () => _showAddBuildingDialog(context),
//         child: const Icon(Icons.add),
//       ),
//     );
//   }
// }
