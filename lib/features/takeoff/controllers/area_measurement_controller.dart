import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'dart:ui'; // for Offset

class AreaMeasurementContrroller extends GetxController {
  // Example state fields – adapt to your actual controller
  final RxString activeLabel = ''.obs;
  final RxString activeBoqCode = ''.obs;

  // TODO: implement or move your polygon area helper here
  double _polygonAreaPx(List<Offset> polygon) {
    if (polygon.length < 3) return 0;
    double sum = 0.0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      sum += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return sum / 2.0;
  }

  // TODO: move your Firestore saving logic here
  Future<void> _saveAreaMeasurement({
    required List<Offset> polygon,
    required double areaPxBase,
    double? areaM2,
  }) async {
    // your existing implementation, but using controller's
    // measurementsRef etc.
  }

  Future<void> completeAreaMeasurement({
    required Map<String, dynamic> drawingData,
    required List<Offset> polygon,
  }) async {
    if (polygon.length < 3) return;

    // 1) area in image pixels² (base coords)
    final areaPxBase = _polygonAreaPx(polygon).abs();
    if (areaPxBase <= 0) return;

    // 2) use calibration
    final calibrated = drawingData['calibrated'] == true;
    final pixelsPerUnitBase = (drawingData['pixelsPerUnit'] ?? 0).toDouble();

    double? areaM2;
    if (calibrated && pixelsPerUnitBase > 0) {
      final pxPerMeter = pixelsPerUnitBase; // px per 1 m
      final px2PerM2 = pxPerMeter * pxPerMeter; // px² per 1 m²
      areaM2 = areaPxBase / px2PerM2;
    }

    final ctx = Get.context;
    if (ctx == null) {
      // No UI context (e.g. background) – either auto-save or just return
      await _saveAreaMeasurement(
        polygon: polygon,
        areaPxBase: areaPxBase,
        areaM2: areaM2,
      );
      return;
    }

    final rawLabel = activeLabel.value.trim();
    final label = rawLabel.isEmpty ? 'Area measurement' : rawLabel;
    final rawBoq = activeBoqCode.value.trim();
    final boq =
        rawBoq.isEmpty || rawBoq.toLowerCase() == 'null' ? 'Not linked' : rawBoq;
    const unitDisplay = 'm²';

    final confirm =
        await Get.dialog<bool>(
          AlertDialog(
            title: const Text('Floor area measurement'),
            content:
                calibrated && areaM2 != null
                    ? Text(
                      'Item: $label\n'
                      'BOQ: $boq\n'
                      'Area: ${areaM2.toStringAsFixed(3)} $unitDisplay',
                    )
                    : Text(
                      'Drawing not calibrated.\n'
                      'Polygon area (px²): ${areaPxBase.toStringAsFixed(1)}',
                    ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    await _saveAreaMeasurement(
      polygon: polygon,
      areaPxBase: areaPxBase,
      areaM2: areaM2,
    );
  }
}
