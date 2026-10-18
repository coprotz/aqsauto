class EdgeSel {
  final int index;
  final double lengthM;
  bool exposed;
  EdgeSel({required this.index, required this.lengthM, this.exposed = false});
}

class RebarTemplate {
  final String rawMark;
  final String direction; // 'alongL' or 'alongB'
  final double embedM;
  final double extraM;
  final String boqCode;
  final String boqDesc;

  const RebarTemplate({
    required this.rawMark,
    required this.direction,
    required this.embedM,
    required this.extraM,
    required this.boqCode,
    required this.boqDesc,
  });
}

class SlabSegmentTemplate {
  final double thicknessM;
  final bool includeSoffit;
  final bool includeEdge;

  final String concreteCode;
  final String concreteDesc;

  final String soffitCode;
  final String soffitDesc;

  final String edgeCode;
  final String edgeDesc;

  final double embedM;
  final double extraM;

  final List<int> exposedEdgeIdx; // edge indexes that were ticked last time
  final List<RebarTemplate> rebars;

  const SlabSegmentTemplate({
    required this.thicknessM,
    required this.includeSoffit,
    required this.includeEdge,
    required this.concreteCode,
    required this.concreteDesc,
    required this.soffitCode,
    required this.soffitDesc,
    required this.edgeCode,
    required this.edgeDesc,
    required this.embedM,
    required this.extraM,
    required this.exposedEdgeIdx,
    required this.rebars,
  });
}

// ✅ controller fields
String? draftSlabGroupId;
SlabSegmentTemplate? lastSlabTemplate; // last SAVED segment template
SlabSegmentTemplate? slabClipboard;      // copy/paste template