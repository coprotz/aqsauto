// import 'package:aqs/features/projects/views/project_detail_page.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';

// class ProjectsListPage extends StatelessWidget {
//   const ProjectsListPage({super.key});

//   CollectionReference get _projectsRef =>
//       FirebaseFirestore.instance.collection('projects');

//   Future<void> _createProject(BuildContext context) async {
//     final nameController = TextEditingController();
//     final clientController = TextEditingController();
//     final currencyController = TextEditingController(text: 'TZS');

//     final result = await showDialog<bool>(
//       context: context,
//       builder: (ctx) {
//         return AlertDialog(
//           title: const Text('New Project'),
//           content: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               TextField(
//                 controller: nameController,
//                 decoration: const InputDecoration(labelText: 'Project name'),
//               ),
//               TextField(
//                 controller: clientController,
//                 decoration: const InputDecoration(
//                   labelText: 'Client (optional)',
//                 ),
//               ),
//               TextField(
//                 controller: currencyController,
//                 decoration: const InputDecoration(labelText: 'Currency'),
//               ),
//             ],
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(ctx, false),
//               child: const Text('Cancel'),
//             ),
//             FilledButton(
//               onPressed: () => Navigator.pop(ctx, true),
//               child: const Text('Create'),
//             ),
//           ],
//         );
//       },
//     );

//     if (result != true) return;
//     final name = nameController.text.trim();
//     final client = clientController.text.trim();
//     final currency =
//         currencyController.text.trim().isEmpty
//             ? 'TZS'
//             : currencyController.text.trim();

//     if (name.isEmpty) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('Project name is required')));
//       return;
//     }

//     await _projectsRef.add({
//       'name': name,
//       'clientName': client.isEmpty ? null : client,
//       'currency': currency,
//       'createdAt': FieldValue.serverTimestamp(),
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Projects')),
//       body: StreamBuilder<QuerySnapshot>(
//         stream: _projectsRef.orderBy('createdAt', descending: true).snapshots(),
//         builder: (context, snapshot) {
//           if (snapshot.hasError) {
//             print(snapshot.error);
//             return const Center(child: Text('Error loading projects'));
//           }
//           if (!snapshot.hasData) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           final docs = snapshot.data!.docs;
//           if (docs.isEmpty) {
//             return const Center(child: Text('No projects yet. Add one.'));
//           }

//           return ListView.builder(
//             itemCount: docs.length,
//             itemBuilder: (ctx, i) {
//               final doc = docs[i];
//               final data = doc.data() as Map<String, dynamic>;
//               final name = data['name'] ?? 'Untitled';
//               final client = data['clientName'] ?? '';
//               return ListTile(
//                 title: Text(name),
//                 subtitle: client.isNotEmpty ? Text(client) : null,
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () {
//                   Navigator.of(context).push(
//                     MaterialPageRoute(
//                       builder:
//                           (_) => ProjectDetailPage(
//                             projectId: doc.id,
//                             projectName: name,
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
//         onPressed: () => _createProject(context),
//         child: const Icon(Icons.add),
//       ),
//     );
//   }
// }
