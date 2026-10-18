import 'package:flutter/material.dart';

enum TakeoffMode { view, calibrate, measureLength, measureArea, editSegment }

// enum BeamAction { continue_, save, cancel }

enum ChainState { idle, waitingP1, waitingNext }

enum SegmentAction { cancel, saveSegment, continueChain, finishTotal }

enum BeamAction { cancel, continue_, save, saveStop }

enum StrokeMode { adaptive, constantOnScreen }

enum DotMode { none, all, chainEndpointsOnly }

enum DotScaleMode { constantOnScreen, constantOnCanvas }

enum SegHandle { none, p1, p2, move }

enum SegmentEditTool { move, extend, rotate, none }

enum SegmentHandle { none, p1, p2, line }

enum ColumnState { idle, drawing }

enum RowType { structure, bill, subheading, item, billFooter }

enum AddBoqChoice { manual, template, excel }

enum FootingSection { footing, column, earthworks, other }

enum SlabSaveAction { cancel, addMore, finish }

enum FoundationSaveAction { cancel, addMore, finish, hide }

enum SourceKind { doc, boqCodeSum }

enum FoundationWallSection {
  wall,
  earthworks,
  concrete,
  formwork,
  rebar,
  other,
}

enum WallType { internal, external }

enum OpeningScope { internal, external }

enum LinkSourceMode { doc, boq }

enum QtySourceMode { measured, boqOverride }

enum BeamSaveAction { cancel, addMore, finish }

enum ColumnSaveAction { cancel, hide, addMore, finish }

enum OpeningCategory { door, window }

enum FrameMeasureMode { number, perimeterM }

enum WallSaveAction { cancel, minimize, addMore, finish }

enum LengthDraftAction { addPoint, undo, cancel, finish }

enum LenDialogAction { cancel, cont, save }

enum CountDialogAction { cancel, cont, save }

enum RoofSaveAction { cancel, addMore, finish, cancelled, saved, failed }
// enum RoofSaveAction { cancel, addMore, finish }

enum PitchMode { angleDeg, slopeFactor }

enum RoofSystem { timber, steel }

enum RoofEdgeTag { eave, ridge, hip, valley, barge }

enum DrawMode { none, polyline, polygon }

enum TrussSaveAction { cancel, addMore, finish }

enum StairSaveAction { cancel, addMore, finish }

enum StairPart { flightWithSteps, landingOnly }

enum RampPart { landing, sloping }

enum RampSaveAction { cancel, addMore, finish }

enum RWAction { cancel, addMore, finish }

enum RoofEdgeType { eave, hip, valley, ridge }

enum ProjectStage { tender, progress, valuation, verification }

enum TakeOffCategory {
  wallsFinishes,
  beamsLintels,
  slabsFloors,
  foundations,
  stairsRamps,
  roofCoverings,
  roofStructure,
  roadsKerbs,
  areasVolumes,
  doorsWindows,
  servicesPipework,
  boqVerification,
}

extension TakeOffCategoryX on TakeOffCategory {
  String get label {
    switch (this) {
      case TakeOffCategory.wallsFinishes:
        return 'Walls & Finishes';

      case TakeOffCategory.beamsLintels:
        return 'Beams & Lintels';

      case TakeOffCategory.slabsFloors:
        return 'Slabs & Floors';

      case TakeOffCategory.foundations:
        return 'Foundations';

      case TakeOffCategory.stairsRamps:
        return 'Stairs & Ramps';

      case TakeOffCategory.roofCoverings:
        return 'Roof Coverings';

      case TakeOffCategory.roofStructure:
        return 'Roof Structure';

      case TakeOffCategory.roadsKerbs:
        return 'Roads & Kerbs';

      case TakeOffCategory.areasVolumes:
        return 'Areas & Volumes';

      case TakeOffCategory.doorsWindows:
        return 'Doors & Windows';

      case TakeOffCategory.servicesPipework:
        return 'Services & Pipework';

      case TakeOffCategory.boqVerification:
        return 'BOQ Verification';
    }
  }

  IconData get icon {
    switch (this) {
      case TakeOffCategory.wallsFinishes:
        return Icons.view_column_outlined;

      case TakeOffCategory.beamsLintels:
        return Icons.horizontal_rule_rounded;

      case TakeOffCategory.slabsFloors:
        return Icons.grid_on_outlined;

      case TakeOffCategory.foundations:
        return Icons.foundation_outlined;

      case TakeOffCategory.stairsRamps:
        return Icons.stairs_outlined;

      case TakeOffCategory.roofCoverings:
        return Icons.roofing_outlined;

      case TakeOffCategory.roofStructure:
        return Icons.carpenter_outlined;

      case TakeOffCategory.roadsKerbs:
        return Icons.add_road_outlined;

      case TakeOffCategory.areasVolumes:
        return Icons.crop_square_outlined;

      case TakeOffCategory.doorsWindows:
        return Icons.door_front_door_outlined;

      case TakeOffCategory.servicesPipework:
        return Icons.linear_scale_outlined;

      case TakeOffCategory.boqVerification:
        return Icons.verified_outlined;
    }
  }
}

enum TakeOffMeasurementMode {
  pan,
  select,
  calibrate,
  length,
  area,
  count,
  volume,
}

enum PillTone { blue, green, grey, red, amber }

// enum StairSaveAction { cancel, addMore, finish }

// enum RoofEdgeTag { eave, ridge, hip, valley, barge }

// enum TakeoffMode { view, calibrate, measureLength, measureArea, editSegment }
