// import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/drawings/models/drawing_bundle.dart';
// import 'package:aqs/features/drawings/models/drawing_sheet.dart';
// import 'package:aqs/features/drawings/pages/upload_drawing_bundle_page.dart';
// import 'package:aqs/features/drawings/services/drawing_service.dart';
// import 'package:aqs/routes/app_routes.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';

// class FacilityDrawingsPage extends StatelessWidget {
//   const FacilityDrawingsPage({
//     super.key,
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//   });

//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AqsColors.canvas,
//       appBar: AppBar(
//         title: const Text('Drawings'),
//         actions: [
//           Padding(
//             padding: const EdgeInsets.only(right: 16),
//             child: FilledButton.icon(
//               onPressed: () async {
//                 Get.toNamed(
//                   AppRoutes.uploadDrawingBundle,
//                   parameters: {
//                     'projectId': projectId,
//                     'facilityId': facilityId,
//                     'facilityName': facilityName,
//                   },
//                 );
//               },
//               icon: const Icon(Icons.upload_file_rounded),
//               label: const Text('Upload Drawings'),
//             ),
//           ),
//         ],
//       ),
//       body: StreamBuilder<List<DrawingBundle>>(
//         stream: DrawingService.instance.watchBundles(
//           projectId: projectId,
//           facilityId: facilityId,
//         ),
//         builder: (context, bundleSnapshot) {
//           return StreamBuilder<List<DrawingSheet>>(
//             stream: DrawingService.instance.watchDrawings(
//               projectId: projectId,
//               facilityId: facilityId,
//             ),
//             builder: (context, drawingSnapshot) {
//               final loading =
//                   bundleSnapshot.connectionState == ConnectionState.waiting ||
//                   drawingSnapshot.connectionState == ConnectionState.waiting;
//               final bundles = bundleSnapshot.data ?? const <DrawingBundle>[];
//               final drawings = drawingSnapshot.data ?? const <DrawingSheet>[];
//               final calibrated =
//                   drawings.where((drawing) => drawing.calibrated).length;
//               final measured =
//                   drawings
//                       .where((drawing) => drawing.measurementCount > 0)
//                       .length;

//               return Center(
//                 child: ConstrainedBox(
//                   constraints: const BoxConstraints(maxWidth: 1250),
//                   child: ListView(
//                     padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
//                     children: [
//                       _Header(facilityName: facilityName),

//                       const SizedBox(height: 22),

//                       _DrawingSummary(
//                         bundleCount: bundles.length,
//                         drawingCount: drawings.length,
//                         calibratedCount: calibrated,
//                         measuredCount: measured,
//                       ),

//                       const SizedBox(height: 26),

//                       const Text(
//                         'Drawing Bundles',
//                         style: TextStyle(
//                           color: AqsColors.ink,
//                           fontSize: 22,
//                           fontWeight: FontWeight.w900,
//                           letterSpacing: -0.4,
//                         ),
//                       ),

//                       const SizedBox(height: 6),

//                       const Text(
//                         'Organise drawings by discipline, issue and revision before take-off.',
//                         style: TextStyle(color: AqsColors.muted, height: 1.4),
//                       ),

//                       const SizedBox(height: 18),

//                       if (bundleSnapshot.hasError || drawingSnapshot.hasError)
//                         _ErrorCard(
//                           message:
//                               '${bundleSnapshot.error ?? drawingSnapshot.error}',
//                         )
//                       else if (loading)
//                         const _LoadingCard()
//                       else if (bundles.isEmpty && drawings.isEmpty)
//                         _EmptyDrawings(
//                           onUpload: () async {
//                             await _openUploadPage(context);
//                           },
//                         )
//                       else ...[
//                         if (bundles.isNotEmpty)
//                           ...bundles.map(
//                             (bundle) => Padding(
//                               padding: const EdgeInsets.only(bottom: 12),
//                               child: _BundleCard(
//                                 bundle: bundle,
//                                 projectId: projectId,
//                                 facilityId: facilityId,
//                                 facilityName: facilityName,

//                                 onAddDrawings: () {
//                                   Get.toNamed(
//                                     AppRoutes.uploadDrawingBundle,
//                                     parameters: {
//                                       'projectId': projectId,
//                                       'facilityId': facilityId,
//                                       'facilityName': facilityName,
//                                       'bundleId': bundle.id,
//                                       'mode': 'append',
//                                     },
//                                   );
//                                 },

//                                 onEdit: () {
//                                   _editBundle(context, bundle);
//                                 },

//                                 onDelete: () {
//                                   _deleteBundle(context, bundle);
//                                 },
//                               ),
//                             ),
//                           )
//                         else
//                           _LegacyDrawingsCard(
//                             drawings: drawings,
//                             projectId: projectId,
//                             facilityId: facilityId,
//                             facilityName: facilityName,
//                           ),
//                       ],
//                     ],
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }

//   Future<void> _openUploadPage(BuildContext context) async {
//     await Navigator.of(context).push(
//       MaterialPageRoute(
//         builder:
//             (_) => UploadDrawingBundlePage(
//               projectId: projectId,
//               facilityId: facilityId,
//               facilityName: facilityName,
//             ),
//       ),
//     );
//   }

//   Future<void> _editBundle(BuildContext context, DrawingBundle bundle) async {
//     final nameController = TextEditingController(text: bundle.name);
//     final revisionController = TextEditingController(text: bundle.revision);
//     final descriptionController = TextEditingController(
//       text: bundle.description,
//     );
//     const disciplineValues = {
//       'architectural',
//       'structural',
//       'civil',
//       'mechanical',
//       'electrical',
//       'plumbing',
//       'general',
//       'other',
//     };
//     const issueTypeValues = {
//       'construction',
//       'tender',
//       'preliminary',
//       'revised',
//       'as_built',
//       'other',
//     };
//     var discipline =
//         disciplineValues.contains(bundle.discipline.trim())
//             ? bundle.discipline.trim()
//             : 'architectural';
//     var issueType =
//         issueTypeValues.contains(bundle.issueType.trim())
//             ? bundle.issueType.trim()
//             : 'construction';

//     final saved = await showDialog<bool>(
//       context: context,
//       builder: (dialogContext) {
//         return StatefulBuilder(
//           builder: (context, setDialogState) {
//             return AlertDialog(
//               title: const Text('Edit drawing bundle'),
//               content: SizedBox(
//                 width: 520,
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     TextField(
//                       controller: nameController,
//                       decoration: const InputDecoration(
//                         labelText: 'Bundle name',
//                         border: OutlineInputBorder(),
//                       ),
//                     ),
//                     const SizedBox(height: 14),
//                     DropdownButtonFormField<String>(
//                       value: discipline,
//                       decoration: const InputDecoration(
//                         labelText: 'Discipline',
//                         border: OutlineInputBorder(),
//                       ),
//                       items: const [
//                         DropdownMenuItem(
//                           value: 'architectural',
//                           child: Text('Architectural'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'structural',
//                           child: Text('Structural'),
//                         ),
//                         DropdownMenuItem(value: 'civil', child: Text('Civil')),
//                         DropdownMenuItem(
//                           value: 'mechanical',
//                           child: Text('Mechanical'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'electrical',
//                           child: Text('Electrical'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'plumbing',
//                           child: Text('Plumbing'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'general',
//                           child: Text('General'),
//                         ),
//                         DropdownMenuItem(value: 'other', child: Text('Other')),
//                       ],
//                       onChanged: (value) {
//                         if (value == null) return;
//                         setDialogState(() => discipline = value);
//                       },
//                     ),
//                     const SizedBox(height: 14),
//                     DropdownButtonFormField<String>(
//                       value: issueType,
//                       decoration: const InputDecoration(
//                         labelText: 'Issue type',
//                         border: OutlineInputBorder(),
//                       ),
//                       items: const [
//                         DropdownMenuItem(
//                           value: 'construction',
//                           child: Text('Construction'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'tender',
//                           child: Text('Tender'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'preliminary',
//                           child: Text('Preliminary'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'revised',
//                           child: Text('Revised'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'as_built',
//                           child: Text('As Built'),
//                         ),
//                         DropdownMenuItem(value: 'other', child: Text('Other')),
//                       ],
//                       onChanged: (value) {
//                         if (value == null) return;
//                         setDialogState(() => issueType = value);
//                       },
//                     ),
//                     const SizedBox(height: 14),
//                     TextField(
//                       controller: revisionController,
//                       decoration: const InputDecoration(
//                         labelText: 'Revision',
//                         border: OutlineInputBorder(),
//                       ),
//                     ),
//                     const SizedBox(height: 14),
//                     TextField(
//                       controller: descriptionController,
//                       minLines: 2,
//                       maxLines: 3,
//                       decoration: const InputDecoration(
//                         labelText: 'Description',
//                         border: OutlineInputBorder(),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               actions: [
//                 TextButton(
//                   onPressed: () => Navigator.of(dialogContext).pop(false),
//                   child: const Text('Cancel'),
//                 ),
//                 FilledButton(
//                   onPressed: () {
//                     if (nameController.text.trim().isEmpty) {
//                       return;
//                     }
//                     Navigator.of(dialogContext).pop(true);
//                   },
//                   child: const Text('Save'),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );

//     if (saved != true || !context.mounted) {
//       nameController.dispose();
//       revisionController.dispose();
//       descriptionController.dispose();
//       return;
//     }

//     try {
//       await DrawingService.instance.updateBundle(
//         projectId: projectId,
//         facilityId: facilityId,
//         bundleId: bundle.id,
//         name: nameController.text.trim(),
//         discipline: discipline,
//         issueType: issueType,
//         revision: revisionController.text.trim(),
//         description: descriptionController.text.trim(),
//       );

//       if (context.mounted) {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(const SnackBar(content: Text('Bundle updated.')));
//       }
//     } catch (error) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Could not update bundle: $error')),
//         );
//       }
//     } finally {
//       nameController.dispose();
//       revisionController.dispose();
//       descriptionController.dispose();
//     }
//   }

//   Future<void> _deleteBundle(BuildContext context, DrawingBundle bundle) async {
//     final confirm = await showDialog<bool>(
//       context: context,
//       builder: (dialogContext) {
//         return AlertDialog(
//           title: const Text('Delete bundle?'),
//           content: Text(
//             'This will delete "${bundle.name}" and all drawings inside it.',
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(dialogContext).pop(false),
//               child: const Text('Cancel'),
//             ),
//             FilledButton(
//               style: FilledButton.styleFrom(
//                 backgroundColor: const Color(0xFFB42318),
//               ),
//               onPressed: () => Navigator.of(dialogContext).pop(true),
//               child: const Text('Delete'),
//             ),
//           ],
//         );
//       },
//     );

//     if (confirm != true || !context.mounted) {
//       return;
//     }

//     try {
//       await DrawingService.instance.deleteBundle(
//         projectId: projectId,
//         facilityId: facilityId,
//         bundleId: bundle.id,
//       );

//       if (context.mounted) {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(const SnackBar(content: Text('Bundle deleted.')));
//       }
//     } catch (error) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Could not delete bundle: $error')),
//         );
//       }
//     }
//   }
// }

// class _Header extends StatelessWidget {
//   const _Header({required this.facilityName});

//   final String facilityName;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: const Color(0xFF101828),
//         borderRadius: BorderRadius.circular(24),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 54,
//             height: 54,
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.10),
//               borderRadius: BorderRadius.circular(16),
//             ),
//             child: const Icon(
//               Icons.architecture_outlined,
//               color: Colors.white,
//               size: 28,
//             ),
//           ),

//           const SizedBox(width: 15),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   facilityName,
//                   style: const TextStyle(
//                     color: Color(0xFFBFD2FA),
//                     fontSize: 12,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),

//                 const SizedBox(height: 4),

//                 const Text(
//                   'Drawing Workspace',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 25,
//                     fontWeight: FontWeight.w900,
//                     letterSpacing: -0.5,
//                   ),
//                 ),

//                 const SizedBox(height: 6),

//                 const Text(
//                   'Upload and manage drawing bundles, revisions and drawing sheets for this facility.',
//                   style: TextStyle(color: Color(0xFFD0D5DD), height: 1.4),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _DrawingSummary extends StatelessWidget {
//   const _DrawingSummary({
//     required this.bundleCount,
//     required this.drawingCount,
//     required this.calibratedCount,
//     required this.measuredCount,
//   });

//   final int bundleCount;
//   final int drawingCount;
//   final int calibratedCount;
//   final int measuredCount;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Wrap(
//         spacing: 34,
//         runSpacing: 20,
//         children: [
//           _SummaryMetric(
//             icon: Icons.folder_copy_outlined,
//             label: 'Bundles',
//             value: '$bundleCount',
//           ),

//           _SummaryMetric(
//             icon: Icons.description_outlined,
//             label: 'Drawing Sheets',
//             value: '$drawingCount',
//           ),

//           _SummaryMetric(
//             icon: Icons.rule_outlined,
//             label: 'Calibrated',
//             value: '$calibratedCount',
//           ),

//           _SummaryMetric(
//             icon: Icons.straighten_outlined,
//             label: 'Measured',
//             value: '$measuredCount',
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryMetric extends StatelessWidget {
//   const _SummaryMetric({
//     required this.icon,
//     required this.label,
//     required this.value,
//   });

//   final IconData icon;
//   final String label;
//   final String value;

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           width: 40,
//           height: 40,
//           decoration: BoxDecoration(
//             color: AqsColors.primary.withOpacity(0.08),
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: Icon(icon, color: AqsColors.primary, size: 20),
//         ),

//         const SizedBox(width: 10),

//         Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               value,
//               style: const TextStyle(
//                 color: AqsColors.ink,
//                 fontSize: 18,
//                 fontWeight: FontWeight.w900,
//               ),
//             ),

//             Text(
//               label,
//               style: const TextStyle(color: AqsColors.muted, fontSize: 10),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }

// class _LoadingCard extends StatelessWidget {
//   const _LoadingCard();

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: const Row(
//         children: [
//           SizedBox(
//             width: 22,
//             height: 22,
//             child: CircularProgressIndicator(strokeWidth: 2),
//           ),
//           SizedBox(width: 12),
//           Text(
//             'Loading drawings...',
//             style: TextStyle(
//               color: AqsColors.muted,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ErrorCard extends StatelessWidget {
//   const _ErrorCard({required this.message});

//   final String message;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: const Color(0xFFFFFBFA),
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: const Color(0xFFFECDCA)),
//       ),
//       child: Text(
//         'Could not load drawings: $message',
//         style: const TextStyle(
//           color: Color(0xFFB42318),
//           fontWeight: FontWeight.w700,
//         ),
//       ),
//     );
//   }
// }

// class _BundleCard extends StatelessWidget {
//   const _BundleCard({
//     required this.bundle,
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//     required this.onAddDrawings,
//     required this.onEdit,
//     required this.onDelete,
//   });

//   final DrawingBundle bundle;

//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   final VoidCallback onAddDrawings;
//   final VoidCallback onEdit;
//   final VoidCallback onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       bundle.name,
//                       style: const TextStyle(
//                         fontSize: 17,
//                         fontWeight: FontWeight.w900,
//                       ),
//                     ),

//                     const SizedBox(height: 5),

//                     Text(
//                       '${bundle.disciplineLabel} • '
//                       '${bundle.pageCount} drawings',
//                       style: const TextStyle(color: Color(0xFF667085)),
//                     ),
//                   ],
//                 ),
//               ),

//               PopupMenuButton<String>(
//                 onSelected: (value) {
//                   switch (value) {
//                     case 'add':
//                       onAddDrawings();
//                       break;

//                     case 'edit':
//                       onEdit();
//                       break;

//                     case 'delete':
//                       onDelete();
//                       break;
//                   }
//                 },
//                 itemBuilder:
//                     (context) => const [
//                       PopupMenuItem(
//                         value: 'add',
//                         child: Row(
//                           children: [
//                             Icon(Icons.add_photo_alternate_outlined, size: 19),
//                             SizedBox(width: 10),
//                             Text('Add Drawings'),
//                           ],
//                         ),
//                       ),

//                       PopupMenuItem(
//                         value: 'edit',
//                         child: Row(
//                           children: [
//                             Icon(Icons.edit_outlined, size: 19),
//                             SizedBox(width: 10),
//                             Text('Edit Bundle'),
//                           ],
//                         ),
//                       ),

//                       PopupMenuDivider(),

//                       PopupMenuItem(
//                         value: 'delete',
//                         child: Row(
//                           children: [
//                             Icon(Icons.delete_outline, size: 19),
//                             SizedBox(width: 10),
//                             Text('Delete Bundle'),
//                           ],
//                         ),
//                       ),
//                     ],
//               ),
//             ],
//           ),

//           const SizedBox(height: 18),

//           Row(
//             children: [
//               OutlinedButton.icon(
//                 onPressed: onAddDrawings,
//                 icon: const Icon(Icons.add_rounded),
//                 label: const Text('Add Drawings'),
//               ),

//               const SizedBox(width: 10),

//               OutlinedButton.icon(
//                 onPressed: () {
//                   Get.toNamed(
//                     AppRoutes.drawingRegister,
//                     parameters: {
//                       'projectId': projectId,
//                       'facilityId': facilityId,
//                       'facilityName': facilityName,
//                       'bundleId': bundle.id,
//                     },
//                   );
//                 },
//                 icon: const Icon(Icons.list_alt_outlined),
//                 label: const Text('View Drawings'),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _LegacyDrawingsCard extends StatelessWidget {
//   const _LegacyDrawingsCard({
//     required this.drawings,
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//   });

//   final List<DrawingSheet> drawings;
//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 46,
//             height: 46,
//             decoration: BoxDecoration(
//               color: AqsColors.primary.withOpacity(0.08),
//               borderRadius: BorderRadius.circular(14),
//             ),
//             child: const Icon(
//               Icons.description_outlined,
//               color: AqsColors.primary,
//             ),
//           ),
//           const SizedBox(width: 14),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   '${drawings.length} uploaded ${drawings.length == 1 ? 'drawing' : 'drawings'}',
//                   style: const TextStyle(
//                     color: AqsColors.ink,
//                     fontSize: 16,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 const Text(
//                   'These drawings were uploaded before bundle metadata was added.',
//                   style: TextStyle(
//                     color: AqsColors.muted,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(width: 14),
//           OutlinedButton.icon(
//             onPressed: () {
//               Get.toNamed(
//                 AppRoutes.drawingRegister,
//                 parameters: {
//                   'projectId': projectId,
//                   'facilityId': facilityId,
//                   'facilityName': facilityName,
//                 },
//               );
//             },
//             icon: const Icon(Icons.visibility_outlined, size: 18),
//             label: const Text('View drawings'),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _StatusChip extends StatelessWidget {
//   const _StatusChip({required this.status});

//   final String status;

//   @override
//   Widget build(BuildContext context) {
//     final ready = status.toLowerCase() == 'ready';

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//       decoration: BoxDecoration(
//         color: ready ? const Color(0xFFECFDF3) : const Color(0xFFFFF7E8),
//         borderRadius: BorderRadius.circular(30),
//       ),
//       child: Text(
//         ready ? 'Ready' : status,
//         style: TextStyle(
//           color: ready ? const Color(0xFF027A48) : const Color(0xFFB54708),
//           fontSize: 11,
//           fontWeight: FontWeight.w900,
//         ),
//       ),
//     );
//   }
// }

// class _EmptyDrawings extends StatelessWidget {
//   final VoidCallback onUpload;
//   const _EmptyDrawings({required this.onUpload});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 54),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Column(
//         children: [
//           Container(
//             width: 76,
//             height: 76,
//             decoration: BoxDecoration(
//               color: AqsColors.primary.withOpacity(0.08),
//               shape: BoxShape.circle,
//             ),
//             child: const Icon(
//               Icons.upload_file_rounded,
//               color: AqsColors.primary,
//               size: 36,
//             ),
//           ),

//           const SizedBox(height: 18),

//           const Text(
//             'Upload the first drawing bundle',
//             style: TextStyle(
//               color: AqsColors.ink,
//               fontSize: 20,
//               fontWeight: FontWeight.w900,
//             ),
//           ),

//           const SizedBox(height: 7),

//           ConstrainedBox(
//             constraints: BoxConstraints(maxWidth: 560),
//             child: Text(
//               'A drawing bundle can contain architectural, structural, civil, mechanical, electrical or other project drawings.',
//               textAlign: TextAlign.center,
//               style: TextStyle(color: AqsColors.muted, height: 1.45),
//             ),
//           ),

//           const SizedBox(height: 20),

//           FilledButton.icon(
//             onPressed: onUpload,
//             icon: Icon(Icons.upload_file_rounded),
//             label: Text('Upload Drawing Bundle'),
//           ),
//         ],
//       ),
//     );
//   }
// }
