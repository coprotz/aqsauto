import 'package:aqs/features/drawings/controllers/drawings_tab_controller.dart';
import 'package:aqs/features/takeoff/controllers/composite_beam_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/image_takeoff_controller.dart';
import 'package:aqs/features/takeoff/controllers/measuring_item_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_config_controller.dart';
import 'package:aqs/features/takeoff/controllers/walling_taleofff_controller.dart';
import 'package:aqs/features/takeoff/drawing_take_off_page.dart';
import 'package:aqs/features/takeoff/image_takeoff_page_getx.dart'; // your GetX version
import 'package:aqs/features/bindings/image_takeoff_binding.dart'; // binding for ImageTakeoffController
import 'package:aqs/features/takeoff/models/reinforcement_callout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DrawingsTabGetX extends StatelessWidget {
  const DrawingsTabGetX({
    super.key,
    required this.projectId,
    required this.buildingId,
  });

  final String projectId;
  final String buildingId;

  DrawingsTabController _ensureController() {
    final tag = '$projectId|$buildingId';
    if (Get.isRegistered<DrawingsTabController>(tag: tag)) {
      return Get.find<DrawingsTabController>(tag: tag);
    }
    return Get.put(
      DrawingsTabController(projectId: projectId, buildingId: buildingId),
      tag: tag,
    );
  }

  Widget _buildStatusWidget(Map<String, dynamic> data) {
    final status = (data['processingStatus'] ?? 'pending') as String;
    final error = (data['processingError'] ?? '') as String;

    if (status == 'pending' || status == 'processing') {
      return Row(
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            'Converting drawing to image...',
            style: TextStyle(fontSize: 11),
          ),
        ],
      );
    }

    if (status == 'error') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              error.isNotEmpty
                  ? 'Error converting drawing:\n$error'
                  : 'Error converting drawing.',
              style: const TextStyle(fontSize: 11, color: Colors.red),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Row(
      children: const [
        Icon(Icons.check_circle, color: Colors.green, size: 16),
        SizedBox(width: 6),
        Text(
          'Drawing image ready',
          style: TextStyle(fontSize: 11, color: Colors.green),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _ensureController();
    final bar = ReinforcementCallout.tryParse('36Y12-08-150T1');

    if (bar != null) {
      print(bar.quantity); // 36
      print(bar.diameterMm); // 12
      print(bar.barMark); // 08
      print(bar.spacingMm); // 150
      print(bar.layer); // T1
      print(bar.kgPerM); // 0.888...
    }
    return Scaffold(
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                c.drawingsRef
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Error loading drawings'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No drawings yet. Tap + to upload PDFs or a package.',
                  ),
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final doc = docs[i];
                  final data = doc.data();

                  final title =
                      (data['title'] ?? 'Untitled drawing').toString();
                  final sheetNumber = (data['sheetNumber'] ?? '').toString();
                  final calibrated = data['calibrated'] == true;

                  final status =
                      (data['processingStatus'] ?? 'pending').toString();
                  final error = (data['processingError'] ?? '').toString();

                  // ✅ NOW: use imageUrl directly (R2/Worker public url)
                  final imageUrl = (data['imageUrl'] ?? '').toString().trim();

                  return ListTile(
                    // leading: Icon(
                    //   (status == 'ready' && imageUrl.isNotEmpty)
                    //       ? Icons.image_outlined
                    //       : Icons.picture_as_pdf,
                    leading:
                        (status == 'ready' && imageUrl.isNotEmpty)
                            ? Icon(Icons.image_outlined)
                            : CircularProgressIndicator(),
                    title: Text(title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sheetNumber.isNotEmpty
                              ? 'Sheet: $sheetNumber'
                              : 'Unlabeled sheet',
                        ),
                        const SizedBox(height: 4),
                        _buildStatusWidget(data),
                      ],
                    ),
                    trailing: Icon(
                      calibrated
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: calibrated ? Colors.green : null,
                    ),
                    onTap: () async {
                      // ✅ open image when ready + imageUrl exists
                      if (status == 'ready' && imageUrl.isNotEmpty) {
                        try {
                          Get.snackbar('Opening', 'Opening image drawing...');

                          // ✅ ensure old drawing controllers are gone
                          Get.delete<MeasuringItemController>(force: true);
                          Get.delete<ImageTakeoffController>(force: true);
                          Get.delete<WallingConfigController>(force: true);
                          Get.delete<WallingTakeoffController>(force: true);
                          Get.delete<CompositeBeamTakeoffController>(
                            force: true,
                          );

                          Get.to(
                            () => const ImageTakeoffPageGetX(),
                            binding: ImageTakeoffBinding(),
                            arguments: {
                              'projectId': projectId,
                              'buildingId': buildingId,
                              'drawingId': doc.id,
                              'drawingTitle': title,
                              'imageUrl': imageUrl, // ✅ already full url
                            },
                          );
                          return;
                        } catch (e) {
                          Get.snackbar(
                            'Failed',
                            'Failed to open image drawing: $e\nOpening PDF instead.',
                          );
                        }
                      } else if (status == 'error') {
                        Get.snackbar(
                          'Conversion failed',
                          error.isNotEmpty
                              ? 'Drawing image conversion failed:\n$error'
                              : 'Drawing image conversion failed.',
                          duration: const Duration(seconds: 6),
                        );
                      } else if (status == 'pending' ||
                          status == 'processing' ||
                          status == 'uploading') {
                        Get.snackbar(
                          'Processing',
                          'Image still processing, opening PDF viewer...',
                        );
                      }

                      // PDF fallback
                      Get.to(
                        () => DrawingTakeoffPage(
                          projectId: projectId,
                          buildingId: buildingId,
                          drawingId: doc.id,
                          drawingTitle: title,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),

          Obx(() {
            if (!c.isSelectingDrawingFiles.value) {
              return const SizedBox.shrink();
            }

            final message =
                c.uploadFileName.value ?? 'Opening drawing file picker...';

            return Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.18),
                alignment: Alignment.center,
                child: Material(
                  elevation: 18,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Preparing drawing upload',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF667085),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Upload progress overlay (Obx)
          Obx(() {
            if (!c.isUploading.value) return const SizedBox.shrink();

            final p = c.uploadProgress.value;
            final name = c.uploadFileName.value ?? 'Uploading drawing...';

            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                elevation: 8,
                color: Colors.black.withOpacity(0.8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: (p > 0 && p < 1) ? p : null,
                              minHeight: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),

      floatingActionButton: Obx(() {
        final busy = c.isUploading.value || c.isSelectingDrawingFiles.value;

        return FloatingActionButton(
          tooltip: 'Upload drawing package',
          onPressed:
              busy
                  ? null
                  : () => c.uploadDrawingToR2(
                    context: context,
                    buildingId: buildingId,
                    drawingsRef: c.drawingsRef,
                    projectId: projectId,
                  ),
          child:
              busy
                  ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.add),
        );
      }),
    );
  }
}
