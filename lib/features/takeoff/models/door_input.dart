import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/foundation.dart';

@immutable
class DoorInput {
  String openingKey;
  final String name;
  final double widthM;
  final double heightM;
  final int qty;
  final int leafCount;
  final bool shutterBoqPerLeaf;
  final bool ironmongeryPerLeaf;

  final String scope; // ✅ NEW

  // ---------- existing BOQ codes ----------
  final String boqShutter;
  final String boqFrame;
  final String boqTransom;
  final String boqArchitrave;

  // ✅ NEW: Firestore BOQ doc IDs (used by syncBoqTotals)
  final String boqShutterId;
  final String boqFrameId;
  final String boqTransomId;
  final String boqArchitraveId;

  final bool includeTransom;
  final bool includeArchitrave;
  final int architraveSides;

  // ---------- new optional door components ----------
  final String boqFrameDecor; // m
  final String boqDoorShutterPanel; // m2
  final bool includeDoorGrill;
  final String boqDoorGrill; // m2

  // ✅ NEW: ids for new components
  final String boqFrameDecorId;
  final String boqDoorShutterPanelId;
  final String boqDoorGrillId;

  /// each item: {key,title,boqCode,boqItemId,qty,unit}
  final List<Map<String, dynamic>> ironmongery;

  DoorInput({
    required this.openingKey,
    required this.name,
    required this.widthM,
    required this.heightM,
    required this.qty,
    this.leafCount = 1,
    this.shutterBoqPerLeaf = false,
    this.ironmongeryPerLeaf = false,

    required this.scope, // default

    this.boqShutter = '',
    this.boqFrame = '',
    this.boqTransom = '',
    this.boqArchitrave = '',

    this.boqShutterId = '',
    this.boqFrameId = '',
    this.boqTransomId = '',
    this.boqArchitraveId = '',

    this.includeTransom = false,
    this.includeArchitrave = false,
    this.architraveSides = 2,

    this.boqFrameDecor = '',
    this.boqDoorShutterPanel = '',
    this.includeDoorGrill = false,
    this.boqDoorGrill = '',

    this.boqFrameDecorId = '',
    this.boqDoorShutterPanelId = '',
    this.boqDoorGrillId = '',

    this.ironmongery = const [],
  });

  DoorInput copyWith({
    String? openingKey,
    String? name,
    double? widthM,
    double? heightM,
    int? qty,
    int? leafCount,
    bool? shutterBoqPerLeaf,
    bool? ironmongeryPerLeaf,
    String? scope,
    String? boqShutter,
    String? boqFrame,
    String? boqTransom,
    String? boqArchitrave,

    String? boqShutterId,
    String? boqFrameId,
    String? boqTransomId,
    String? boqArchitraveId,

    bool? includeTransom,
    bool? includeArchitrave,
    int? architraveSides,

    String? boqFrameDecor,
    String? boqDoorShutterPanel,
    bool? includeDoorGrill,
    String? boqDoorGrill,

    String? boqFrameDecorId,
    String? boqDoorShutterPanelId,
    String? boqDoorGrillId,

    List<Map<String, dynamic>>? ironmongery,
  }) {
    return DoorInput(
      openingKey: openingKey ?? this.openingKey,
      name: name ?? this.name,
      widthM: widthM ?? this.widthM,
      heightM: heightM ?? this.heightM,
      qty: qty ?? this.qty,
      leafCount: leafCount ?? this.leafCount,
      shutterBoqPerLeaf: shutterBoqPerLeaf ?? this.shutterBoqPerLeaf,
      ironmongeryPerLeaf:
          ironmongeryPerLeaf ?? this.ironmongeryPerLeaf,

      scope: scope ?? this.scope,

      boqShutter: boqShutter ?? this.boqShutter,
      boqFrame: boqFrame ?? this.boqFrame,
      boqTransom: boqTransom ?? this.boqTransom,
      boqArchitrave: boqArchitrave ?? this.boqArchitrave,

      boqShutterId: boqShutterId ?? this.boqShutterId,
      boqFrameId: boqFrameId ?? this.boqFrameId,
      boqTransomId: boqTransomId ?? this.boqTransomId,
      boqArchitraveId: boqArchitraveId ?? this.boqArchitraveId,

      includeTransom: includeTransom ?? this.includeTransom,
      includeArchitrave: includeArchitrave ?? this.includeArchitrave,
      architraveSides: architraveSides ?? this.architraveSides,

      boqFrameDecor: boqFrameDecor ?? this.boqFrameDecor,
      boqDoorShutterPanel: boqDoorShutterPanel ?? this.boqDoorShutterPanel,
      includeDoorGrill: includeDoorGrill ?? this.includeDoorGrill,
      boqDoorGrill: boqDoorGrill ?? this.boqDoorGrill,

      boqFrameDecorId: boqFrameDecorId ?? this.boqFrameDecorId,
      boqDoorShutterPanelId:
          boqDoorShutterPanelId ?? this.boqDoorShutterPanelId,
      boqDoorGrillId: boqDoorGrillId ?? this.boqDoorGrillId,

      ironmongery: ironmongery ?? this.ironmongery,
    );
  }

  /// Normalize ironmongery maps to always have boqItemId key
  DoorInput ensureIronmongeryHasIds() {
    final fixed =
        ironmongery.map((m) {
          final mm = Map<String, dynamic>.from(m);
          mm['boqItemId'] = (mm['boqItemId'] ?? '').toString();
          mm['boqCode'] = (mm['boqCode'] ?? '').toString();
          mm['qty'] =
              (mm['qty'] is num)
                  ? mm['qty']
                  : (double.tryParse('${mm['qty']}') ?? 0);
          mm['unit'] = (mm['unit'] ?? '').toString();
          mm['title'] = (mm['title'] ?? '').toString();
          mm['key'] = (mm['key'] ?? '').toString();
          return mm;
        }).toList();

    return copyWith(ironmongery: fixed);
  }
}
