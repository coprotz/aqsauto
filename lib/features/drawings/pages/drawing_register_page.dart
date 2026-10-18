// import 'dart:typed_data';

// import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/drawings/controllers/drawings_tab_controller.dart';
// import 'package:aqs/features/drawings/models/drawing_sheet.dart';
// import 'package:aqs/features/drawings/services/drawing_service.dart';
// import 'package:aqs/routes/app_routes.dart' show AppRoutes;

// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:url_launcher/url_launcher.dart';

// class DrawingRegisterPage extends StatefulWidget {
//   const DrawingRegisterPage({
//     super.key,
//     required this.projectId,
//     required this.facilityId,
//     required this.facilityName,
//     this.bundleId,
//   });

//   final String projectId;
//   final String facilityId;
//   final String facilityName;

//   /// Optional:
//   /// if supplied, register can focus on one bundle.
//   final String? bundleId;

//   @override
//   State<DrawingRegisterPage> createState() => _DrawingRegisterPageState();
// }

// class _DrawingRegisterPageState extends State<DrawingRegisterPage> {
//   final _searchController = TextEditingController();
//   final Map<String, Future<Uint8List>> _thumbnailCache = {};

//   String _search = '';

//   String _statusFilter = 'all';

//   @override
//   void dispose() {
//     _searchController.dispose();
//     super.dispose();
//   }

//   bool _matchesSearch(DrawingSheet drawing) {
//     final query = _search.trim().toLowerCase();

//     if (query.isEmpty) {
//       return true;
//     }

//     return drawing.drawingNumber.toLowerCase().contains(query) ||
//         drawing.title.toLowerCase().contains(query) ||
//         drawing.revision.toLowerCase().contains(query) ||
//         drawing.sourcePageNumber.toString().contains(query);
//   }

//   bool _matchesStatus(DrawingSheet drawing) {
//     if (_statusFilter == 'all') {
//       return true;
//     }

//     return drawing.status == _statusFilter;
//   }

//   Future<Uint8List>? _thumbnailFor(DrawingSheet drawing) {
//     final key = drawing.id;

//     return _thumbnailCache.putIfAbsent(key, () async {
//       final doc = await DrawingService.instance.drawingSnapshot(
//         projectId: widget.projectId,
//         facilityId: widget.facilityId,
//         drawingId: drawing.id,
//       );
//       final data = doc.data() ?? <String, dynamic>{};
//       final downloadUrl = (data['downloadUrl'] ?? '').toString().trim();

//       if (downloadUrl.isEmpty) {
//         throw Exception('No drawing PDF URL.');
//       }

//       return DrawingsTabController.renderPdfUrlPagePngBytes(
//         pdfUrl: downloadUrl,
//         pageNumber: 1,
//         scale: 0.35,
//       );
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final stream =
//         widget.bundleId == null
//             ? DrawingService.instance.watchDrawings(
//               projectId: widget.projectId,
//               facilityId: widget.facilityId,
//             )
//             : DrawingService.instance.watchBundleDrawings(
//               projectId: widget.projectId,
//               facilityId: widget.facilityId,
//               bundleId: widget.bundleId!,
//             );

//     return Scaffold(
//       backgroundColor: AqsColors.canvas,

//       appBar: AppBar(title: const Text('Drawing Register')),

//       body: StreamBuilder<List<DrawingSheet>>(
//         stream: stream,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           if (snapshot.hasError) {
//             return Center(
//               child: Text(
//                 'Could not load drawings:\n'
//                 '${snapshot.error}',
//                 textAlign: TextAlign.center,
//               ),
//             );
//           }

//           final allDrawings = snapshot.data ?? const <DrawingSheet>[];

//           final drawings =
//               allDrawings.where(_matchesSearch).where(_matchesStatus).toList()
//                 ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

//           return Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 1350),
//               child: Column(
//                 children: [
//                   Expanded(
//                     child: ListView(
//                       padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
//                       children: [
//                         _Header(
//                           facilityName: widget.facilityName,
//                           drawingCount: allDrawings.length,
//                         ),

//                         const SizedBox(height: 22),

//                         _RegisterSummary(drawings: allDrawings),

//                         const SizedBox(height: 22),

//                         _Toolbar(
//                           searchController: _searchController,
//                           search: _search,
//                           statusFilter: _statusFilter,

//                           onSearchChanged: (value) {
//                             setState(() {
//                               _search = value;
//                             });
//                           },

//                           onClearSearch: () {
//                             _searchController.clear();

//                             setState(() {
//                               _search = '';
//                             });
//                           },

//                           onStatusChanged: (value) {
//                             if (value == null) {
//                               return;
//                             }

//                             setState(() {
//                               _statusFilter = value;
//                             });
//                           },
//                         ),

//                         const SizedBox(height: 18),

//                         if (drawings.isEmpty)
//                           _EmptyRegister(hasDrawings: allDrawings.isNotEmpty)
//                         else
//                           _DrawingRegisterTable(
//                             drawings: drawings,
//                             thumbnailFor: _thumbnailFor,
//                             onOpen: _openDrawing,
//                             onTakeoff: _onStartTakeoff,
//                             onEdit: _editDrawing,
//                             onDelete: _deleteDrawing,
//                           ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   void _openDrawing(DrawingSheet drawing) {
//     Get.toNamed(
//       AppRoutes.drawingViewer,
//       parameters: {
//         'projectId': drawing.projectId,
//         'facilityId': drawing.facilityId,
//         'drawingId': drawing.id,
//       },
//     );
//   }

//   // Future<void> _openDrawing(DrawingSheet drawing) async {
//   //   final drawingUrl = await _downloadUrlFor(drawing);

//   //   if (drawingUrl == null || drawingUrl.isEmpty) {
//   //     if (!mounted) {
//   //       return;
//   //     }

//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(content: Text('This drawing has no viewable PDF URL.')),
//   //     );
//   //     return;
//   //   }

//   //   final uri = Uri.tryParse(drawingUrl);

//   //   if (uri == null) {
//   //     if (!mounted) {
//   //       return;
//   //     }

//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(content: Text('The drawing URL is invalid.')),
//   //     );
//   //     return;
//   //   }

//   //   await launchUrl(uri, webOnlyWindowName: '_blank');
//   // }

//   Future<String?> _downloadUrlFor(DrawingSheet drawing) async {
//     final doc = await DrawingService.instance.drawingSnapshot(
//       projectId: widget.projectId,
//       facilityId: widget.facilityId,
//       drawingId: drawing.id,
//     );

//     final data = doc.data() ?? <String, dynamic>{};

//     return (data['downloadUrl'] ?? '').toString().trim();
//   }

//   Future<void> _editDrawing(DrawingSheet drawing) async {
//     final numberController = TextEditingController(text: drawing.drawingNumber);

//     final titleController = TextEditingController(text: drawing.title);

//     final revisionController = TextEditingController(text: drawing.revision);

//     final result = await showDialog<bool>(
//       context: context,
//       builder: (dialogContext) {
//         return AlertDialog(
//           title: const Text('Edit Drawing'),

//           content: SizedBox(
//             width: 500,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 TextField(
//                   controller: numberController,
//                   decoration: const InputDecoration(
//                     labelText: 'Drawing No.',
//                     border: OutlineInputBorder(),
//                   ),
//                 ),

//                 const SizedBox(height: 14),

//                 TextField(
//                   controller: titleController,
//                   decoration: const InputDecoration(
//                     labelText: 'Drawing Title',
//                     border: OutlineInputBorder(),
//                   ),
//                 ),

//                 const SizedBox(height: 14),

//                 TextField(
//                   controller: revisionController,
//                   decoration: const InputDecoration(
//                     labelText: 'Revision',
//                     border: OutlineInputBorder(),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.of(dialogContext).pop(false);
//               },
//               child: const Text('Cancel'),
//             ),

//             FilledButton(
//               onPressed: () {
//                 Navigator.of(dialogContext).pop(true);
//               },
//               child: const Text('Save Changes'),
//             ),
//           ],
//         );
//       },
//     );

//     if (result != true) {
//       numberController.dispose();
//       titleController.dispose();
//       revisionController.dispose();

//       return;
//     }

//     try {
//       await DrawingService.instance.updateDrawing(
//         projectId: widget.projectId,

//         facilityId: widget.facilityId,

//         drawingId: drawing.id,

//         drawingNumber: numberController.text,

//         title: titleController.text,

//         revision: revisionController.text,

//         status:
//             numberController.text.trim().isEmpty ||
//                     titleController.text.trim().isEmpty
//                 ? 'needs_review'
//                 : drawing.calibrated
//                 ? 'ready'
//                 : 'needs_calibration',
//       );
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Could not update drawing: $error')),
//       );
//     } finally {
//       numberController.dispose();
//       titleController.dispose();
//       revisionController.dispose();
//     }
//   }

//   void _onStartTakeoff(DrawingSheet drawing) {
//     Get.toNamed(
//       AppRoutes.takeoffWorkspace,
//       parameters: {
//         'projectId': widget.projectId,

//         'facilityId': widget.facilityId,

//         'drawingId': drawing.id,
//       },
//     );
//   }

//   Future<void> _deleteDrawing(DrawingSheet drawing) async {
//     final confirm = await showDialog<bool>(
//       context: context,
//       builder: (dialogContext) {
//         return AlertDialog(
//           title: const Text('Delete drawing?'),
//           content: Text(
//             'This will remove "${drawing.title}" from the drawing register.',
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

//     if (confirm != true || !mounted) {
//       return;
//     }

//     try {
//       await DrawingService.instance.deleteDrawing(
//         projectId: widget.projectId,
//         facilityId: widget.facilityId,
//         drawingId: drawing.id,
//       );

//       if (!mounted) {
//         return;
//       }

//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('Drawing deleted.')));
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Could not delete drawing: $error')),
//       );
//     }
//   }
// }

// class _Header extends StatelessWidget {
//   const _Header({required this.facilityName, required this.drawingCount});

//   final String facilityName;
//   final int drawingCount;

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
//                   'Drawing Register',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 25,
//                     fontWeight: FontWeight.w900,
//                     letterSpacing: -0.5,
//                   ),
//                 ),

//                 const SizedBox(height: 5),

//                 Text(
//                   '$drawingCount registered '
//                   '${drawingCount == 1 ? 'drawing' : 'drawings'}',
//                   style: const TextStyle(color: Color(0xFFD0D5DD)),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _RegisterSummary extends StatelessWidget {
//   const _RegisterSummary({required this.drawings});

//   final List<DrawingSheet> drawings;

//   @override
//   Widget build(BuildContext context) {
//     final calibrated = drawings.where((drawing) => drawing.calibrated).length;

//     final review =
//         drawings.where((drawing) => drawing.status == 'needs_review').length;

//     final measured =
//         drawings.where((drawing) => drawing.measurementCount > 0).length;

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: Wrap(
//         spacing: 34,
//         runSpacing: 18,
//         children: [
//           _SummaryMetric(
//             label: 'Drawings',
//             value: '${drawings.length}',
//             icon: Icons.description_outlined,
//           ),

//           _SummaryMetric(
//             label: 'Calibrated',
//             value: '$calibrated',
//             icon: Icons.rule_outlined,
//           ),

//           _SummaryMetric(
//             label: 'Needs Review',
//             value: '$review',
//             icon: Icons.rate_review_outlined,
//           ),

//           _SummaryMetric(
//             label: 'Measured',
//             value: '$measured',
//             icon: Icons.straighten_outlined,
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryMetric extends StatelessWidget {
//   const _SummaryMetric({
//     required this.label,
//     required this.value,
//     required this.icon,
//   });

//   final String label;
//   final String value;
//   final IconData icon;

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

// class _Toolbar extends StatelessWidget {
//   const _Toolbar({
//     required this.searchController,
//     required this.search,
//     required this.statusFilter,
//     required this.onSearchChanged,
//     required this.onClearSearch,
//     required this.onStatusChanged,
//   });

//   final TextEditingController searchController;

//   final String search;
//   final String statusFilter;

//   final ValueChanged<String> onSearchChanged;

//   final VoidCallback onClearSearch;

//   final ValueChanged<String?> onStatusChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final searchBox = TextField(
//             controller: searchController,
//             decoration: InputDecoration(
//               hintText: 'Search drawing number, title, revision or PDF page',
//               prefixIcon: const Icon(Icons.search_rounded),
//               suffixIcon:
//                   search.isEmpty
//                       ? null
//                       : IconButton(
//                         onPressed: onClearSearch,
//                         icon: const Icon(Icons.close_rounded),
//                       ),
//               border: const OutlineInputBorder(),
//             ),
//             onChanged: onSearchChanged,
//           );

//           final filter = DropdownButtonFormField<String>(
//             value: statusFilter,
//             decoration: const InputDecoration(
//               labelText: 'Status',
//               border: OutlineInputBorder(),
//             ),
//             items: const [
//               DropdownMenuItem(value: 'all', child: Text('All Drawings')),

//               DropdownMenuItem(
//                 value: 'needs_review',
//                 child: Text('Needs Review'),
//               ),

//               DropdownMenuItem(
//                 value: 'needs_calibration',
//                 child: Text('Needs Calibration'),
//               ),

//               DropdownMenuItem(value: 'ready', child: Text('Ready')),

//               DropdownMenuItem(value: 'measured', child: Text('Measured')),

//               DropdownMenuItem(value: 'superseded', child: Text('Superseded')),
//             ],
//             onChanged: onStatusChanged,
//           );

//           if (constraints.maxWidth < 700) {
//             return Column(
//               children: [searchBox, const SizedBox(height: 12), filter],
//             );
//           }

//           return Row(
//             children: [
//               Expanded(child: searchBox),

//               const SizedBox(width: 14),

//               SizedBox(width: 220, child: filter),
//             ],
//           );
//         },
//       ),
//     );
//   }
// }

// class _DrawingRegisterTable extends StatelessWidget {
//   const _DrawingRegisterTable({
//     required this.drawings,
//     required this.thumbnailFor,
//     required this.onOpen,
//     required this.onEdit,
//     required this.onDelete,
//     required this.onTakeoff,
//   });

//   final List<DrawingSheet> drawings;
//   final Future<Uint8List>? Function(DrawingSheet drawing) thumbnailFor;

//   final ValueChanged<DrawingSheet> onOpen;

//   final ValueChanged<DrawingSheet> onEdit;

//   final ValueChanged<DrawingSheet> onDelete;
//   final ValueChanged<DrawingSheet> onTakeoff;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: Column(
//         children: [
//           const _TableHeader(),

//           ...drawings.asMap().entries.map((entry) {
//             final index = entry.key;

//             final drawing = entry.value;

//             return Column(
//               children: [
//                 _DrawingRow(
//                   drawing: drawing,
//                   thumbnailFuture: thumbnailFor(drawing),
//                   onTakeoff: () {
//                     onTakeoff(drawing);
//                   },
//                   onOpen: () {
//                     onOpen(drawing);
//                   },
//                   onEdit: () {
//                     onEdit(drawing);
//                   },
//                   onDelete: () {
//                     onDelete(drawing);
//                   },
//                 ),

//                 if (index < drawings.length - 1) const Divider(height: 1),
//               ],
//             );
//           }),
//         ],
//       ),
//     );
//   }
// }

// class _TableHeader extends StatelessWidget {
//   const _TableHeader();

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       color: const Color(0xFFF9FAFB),
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       child: const Row(
//         children: [
//           SizedBox(
//             width: 78,
//             child: Text('PREVIEW', style: _HeaderTextStyle.style),
//           ),

//           SizedBox(
//             width: 110,
//             child: Text('DRAWING NO.', style: _HeaderTextStyle.style),
//           ),

//           Expanded(child: Text('TITLE', style: _HeaderTextStyle.style)),

//           SizedBox(
//             width: 90,
//             child: Text('REV.', style: _HeaderTextStyle.style),
//           ),

//           SizedBox(
//             width: 90,
//             child: Text('SOURCE', style: _HeaderTextStyle.style),
//           ),

//           SizedBox(
//             width: 140,
//             child: Text('STATUS', style: _HeaderTextStyle.style),
//           ),

//           SizedBox(
//             width: 130,
//             child: Text('MEASUREMENTS', style: _HeaderTextStyle.style),
//           ),

//           SizedBox(
//             width: 126,
//             child: Text('ACTIONS', style: _HeaderTextStyle.style),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _HeaderTextStyle {
//   static const style = TextStyle(
//     color: AqsColors.muted,
//     fontSize: 9,
//     fontWeight: FontWeight.w900,
//   );
// }

// class _DrawingThumbnail extends StatelessWidget {
//   const _DrawingThumbnail({required this.thumbnailFuture});

//   final Future<Uint8List>? thumbnailFuture;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: 54,
//       height: 66,
//       clipBehavior: Clip.antiAlias,
//       decoration: BoxDecoration(
//         color: const Color(0xFFF9FAFB),
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: const Color(0xFFE4E7EC)),
//       ),
//       child:
//           thumbnailFuture == null
//               ? const Icon(Icons.description_outlined, color: AqsColors.muted)
//               : FutureBuilder<Uint8List>(
//                 future: thumbnailFuture,
//                 builder: (context, snapshot) {
//                   if (snapshot.hasData) {
//                     return Image.memory(snapshot.data!, fit: BoxFit.cover);
//                   }

//                   if (snapshot.hasError) {
//                     return const Icon(
//                       Icons.description_outlined,
//                       color: AqsColors.muted,
//                     );
//                   }

//                   return const Center(
//                     child: SizedBox(
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     ),
//                   );
//                 },
//               ),
//     );
//   }
// }

// class _DrawingRow extends StatelessWidget {
//   const _DrawingRow({
//     required this.drawing,
//     required this.thumbnailFuture,
//     required this.onOpen,
//     required this.onEdit,
//     required this.onDelete,
//     required this.onTakeoff,
//   });

//   final DrawingSheet drawing;
//   final Future<Uint8List>? thumbnailFuture;

//   final VoidCallback onOpen;
//   final VoidCallback onEdit;
//   final VoidCallback onDelete;
//   final VoidCallback onTakeoff;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onOpen,
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         child: Row(
//           children: [
//             SizedBox(
//               width: 78,
//               child: _DrawingThumbnail(thumbnailFuture: thumbnailFuture),
//             ),

//             SizedBox(
//               width: 110,
//               child: Text(
//                 drawing.drawingNumber.isEmpty ? '—' : drawing.drawingNumber,
//                 style: const TextStyle(
//                   color: AqsColors.ink,
//                   fontWeight: FontWeight.w900,
//                 ),
//               ),
//             ),

//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     drawing.title,
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       color: AqsColors.ink,
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),

//                   const SizedBox(height: 3),

//                   Text(
//                     drawing.sourceFileName,
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       color: AqsColors.muted,
//                       fontSize: 10,
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             SizedBox(
//               width: 90,
//               child: Text(drawing.revision.isEmpty ? '—' : drawing.revision),
//             ),

//             SizedBox(
//               width: 90,
//               child: Text(
//                 'Page ${drawing.sourcePageNumber}',
//                 style: const TextStyle(color: AqsColors.muted, fontSize: 11),
//               ),
//             ),

//             SizedBox(width: 140, child: _StatusChip(drawing: drawing)),

//             SizedBox(
//               width: 130,
//               child: Text(
//                 '${drawing.measurementCount}',
//                 style: const TextStyle(
//                   color: AqsColors.ink,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//             ),

//             SizedBox(
//               width: 166,
//               child: Row(
//                 children: [
//                   IconButton(
//                     tooltip: 'Start Take-Off',
//                     onPressed: onTakeoff,
//                     icon: const Icon(Icons.architecture_outlined, size: 19),
//                   ),
//                   IconButton(
//                     tooltip: 'Open drawing',
//                     onPressed: onOpen,
//                     icon: const Icon(Icons.open_in_new_rounded, size: 19),
//                   ),

//                   IconButton(
//                     tooltip: 'Edit',
//                     onPressed: onEdit,
//                     icon: const Icon(Icons.edit_outlined, size: 19),
//                   ),

//                   IconButton(
//                     tooltip: 'Delete',
//                     onPressed: onDelete,
//                     icon: const Icon(
//                       Icons.delete_outline_rounded,
//                       size: 19,
//                       color: Color(0xFFB42318),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _StatusChip extends StatelessWidget {
//   const _StatusChip({required this.drawing});

//   final DrawingSheet drawing;

//   String get _label {
//     switch (drawing.status) {
//       case 'needs_review':
//         return 'NEEDS REVIEW';

//       case 'needs_calibration':
//         return 'CALIBRATE';

//       case 'ready':
//         return 'READY';

//       case 'measured':
//         return 'MEASURED';

//       case 'superseded':
//         return 'SUPERSEDED';

//       default:
//         return drawing.status.toUpperCase();
//     }
//   }

//   Color get _background {
//     switch (drawing.status) {
//       case 'needs_review':
//         return const Color(0xFFFFFAEB);

//       case 'needs_calibration':
//         return const Color(0xFFEFF8FF);

//       case 'ready':
//       case 'measured':
//         return const Color(0xFFECFDF3);

//       default:
//         return const Color(0xFFF2F4F7);
//     }
//   }

//   Color get _foreground {
//     switch (drawing.status) {
//       case 'needs_review':
//         return const Color(0xFFB54708);

//       case 'needs_calibration':
//         return const Color(0xFF175CD3);

//       case 'ready':
//       case 'measured':
//         return const Color(0xFF027A48);

//       default:
//         return const Color(0xFF667085);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Align(
//       alignment: Alignment.centerLeft,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
//         decoration: BoxDecoration(
//           color: _background,
//           borderRadius: BorderRadius.circular(30),
//         ),
//         child: Text(
//           _label,
//           style: TextStyle(
//             color: _foreground,
//             fontSize: 9,
//             fontWeight: FontWeight.w900,
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _EmptyRegister extends StatelessWidget {
//   const _EmptyRegister({required this.hasDrawings});

//   final bool hasDrawings;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(48),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//       ),
//       child: Center(
//         child: Column(
//           children: [
//             const Icon(
//               Icons.architecture_outlined,
//               color: AqsColors.muted,
//               size: 38,
//             ),

//             const SizedBox(height: 12),

//             Text(
//               hasDrawings
//                   ? 'No drawings match your filter.'
//                   : 'No drawings have been uploaded yet.',
//               style: const TextStyle(
//                 color: AqsColors.ink,
//                 fontWeight: FontWeight.w800,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
