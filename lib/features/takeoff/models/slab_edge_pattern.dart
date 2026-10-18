class SlabEdgePattern {
  final bool top;
  final bool bottom;
  final bool left;
  final bool right;

  const SlabEdgePattern({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  const SlabEdgePattern.none()
    : top = false,
      bottom = false,
      left = false,
      right = false;

  /// Map 1..9 to your “panel pictures”.
  /// Adjust the mapping to match your PDF sketch.
  factory SlabEdgePattern.fromCase(int caseNo) {
    switch (caseNo) {
      case 1: // one long edge at top
        return const SlabEdgePattern(
          top: true,
          bottom: false,
          left: false,
          right: false,
        );
      case 2: // top + bottom
        return const SlabEdgePattern(
          top: true,
          bottom: true,
          left: false,
          right: false,
        );
      case 3: // two short edges (left + right)
        return const SlabEdgePattern(
          top: false,
          bottom: false,
          left: true,
          right: true,
        );
      case 4: // three sides
        return const SlabEdgePattern(
          top: true,
          bottom: true,
          left: true,
          right: false,
        );
      case 5: // inside beams: no edges
        return const SlabEdgePattern.none();
      case 6: // all 4 sides
        return const SlabEdgePattern(
          top: true,
          bottom: true,
          left: true,
          right: true,
        );
      case 7: // left only
        return const SlabEdgePattern(
          top: false,
          bottom: false,
          left: true,
          right: false,
        );
      case 8: // right only
        return const SlabEdgePattern(
          top: false,
          bottom: false,
          left: false,
          right: true,
        );
      case 9: // bottom only
        return const SlabEdgePattern(
          top: false,
          bottom: true,
          left: false,
          right: false,
        );
      default:
        return const SlabEdgePattern.none();
    }
  }

  /// How many meters of edge formwork (using L along X, W along Y).
  double edgePerimeter({required double lengthM, required double widthM}) {
    double p = 0;
    if (top) p += lengthM;
    if (bottom) p += lengthM;
    if (left) p += widthM;
    if (right) p += widthM;
    return p;
  }
}
