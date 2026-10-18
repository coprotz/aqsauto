import 'package:aqs/features/buildings/controllers/building_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BuildingDetailBinding extends Bindings {
  @override
  void dependencies() {
    final raw = Get.arguments;

    // Safer: allow passing Map or null
    final args =
        (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    String _str(String key) => (args[key] ?? '').toString().trim();
    String _firstNonEmpty(List<String> keys) {
      for (final k in keys) {
        final v = _str(k);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final projectId = _str('projectId');
    final buildingId = _str('buildingId');

    // optional but recommended
    final buildingName = _str('buildingName');

    // drawing id / title (optional depending on your page)
    final drawingId = _firstNonEmpty(['drawingId', 'id', 'docId', 'projectId']);

    // ✅ accept either stored download URL or storage path
    // - imageUrl: full https://... token url
    // - imagePath: "projects/.../drawings/xxx.pdf"
    final imageUrl = _firstNonEmpty(['imageUrl', 'downloadUrl']);
    final imagePath = _firstNonEmpty(['imagePath', 'filePath', 'storagePath']);

    // title: prefer drawingTitle, otherwise fallback to drawingName, then buildingName
    final drawingTitle =
        _firstNonEmpty(['drawingTitle', 'drawingName', 'title']).isNotEmpty
            ? _firstNonEmpty(['drawingTitle', 'drawingName', 'title'])
            : (buildingName.isNotEmpty ? buildingName : 'Drawing');

    // ---- required checks ----
    if (projectId.isEmpty || buildingId.isEmpty) {
      throw ArgumentError(
        'BuildingDetailBinding missing projectId/buildingId. '
        'Provided args keys: ${args.keys.toList()}',
      );
    }

    // ---- sanity checks for image ----
    // If your controller expects a URL, don't pass empty.
    // If you support either, pass both and let controller resolve.
    if (imageUrl.isEmpty && imagePath.isEmpty) {
      // You can relax this if the page can open without a drawing
      debugPrint(
        'BuildingDetailBinding: No imageUrl/imagePath provided. args keys=${args.keys.toList()}',
      );
    }

    Get.put(
      BuildingDetailController(
        projectId: projectId,
        buildingId: buildingId,
        buildingName: buildingName,
        drawingId: drawingId,
        // ✅ pass URL if present; otherwise pass path and let controller call getDownloadURL()
        imageUrl: imageUrl.isNotEmpty ? imageUrl : imagePath,
        drawingTitle: drawingTitle,
      ),
    );
  }
}
