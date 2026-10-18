// import 'package:aqs/features/buildings/views/boq_tab.dart';
// import 'package:aqs/features/buildings/views/drawing_tab.dart';
// import 'package:flutter/material.dart';

// class BuildingDetailPage extends StatelessWidget {
//   final String projectId;
//   final String buildingId;
//   final String buildingName;

//   const BuildingDetailPage({
//     super.key,
//     required this.projectId,
//     required this.buildingId,
//     required this.buildingName,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 2,
//       child: Scaffold(
//         appBar: AppBar(
//           title: Text(buildingName),
//           bottom: const TabBar(
//             tabs: [
//               Tab(text: 'Drawings', icon: Icon(Icons.picture_as_pdf)),
//               Tab(text: 'BOQ', icon: Icon(Icons.list_alt)),
//             ],
//           ),
//         ),
//         body: TabBarView(
//           children: [
//             DrawingsTab(projectId: projectId, buildingId: buildingId),
//             BoqTab(projectId: projectId, buildingId: buildingId),
//           ],
//         ),
//       ),
//     );
//   }
// }
