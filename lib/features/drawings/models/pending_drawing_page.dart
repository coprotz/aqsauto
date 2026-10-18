import 'dart:typed_data';

class PendingDrawingPage {
  PendingDrawingPage({
    required this.pageIndex,
    required this.sourcePageNumber,
    required this.sortOrder,
    required this.selected,
    required this.drawingNumber,
    required this.title,
    this.estimatedPdfSizeBytes = 0,
    this.pdfSizeBytes,
    this.thumbnailBytes,
  });

  /// Zero-based internal PDF page index.
  ///
  /// Example:
  /// PDF page 1 = pageIndex 0
  final int pageIndex;

  /// Human-readable original PDF page number.
  ///
  /// Example:
  /// PDF page 1 = sourcePageNumber 1
  final int sourcePageNumber;

  /// Working drawing-register order.
  ///
  /// This may change when the QS reorders drawings.
  int sortOrder;

  /// Whether this page will become a DrawingSheet.
  bool selected;

  /// QS editable drawing number.
  ///
  /// Example:
  /// A-001
  /// S-101
  String drawingNumber;

  /// QS editable drawing title.
  ///
  /// Example:
  /// Ground Floor Plan
  String title;

  /// Estimated share of the original bundle PDF.
  ///
  /// Used before exact single-page extraction is prepared.
  int estimatedPdfSizeBytes;

  /// Exact standalone single-page PDF size, if a future workflow extracts pages.
  int? pdfSizeBytes;

  /// Size shown in the upload page and stored against the drawing.
  ///
  /// Prefer the real standalone PDF size when Syncfusion has extracted the
  /// page. Before that finishes, fall back to the initial bundle-share
  /// estimate so the UI never shows 0 B.
  int get displayPdfSizeBytes => pdfSizeBytes ?? estimatedPdfSizeBytes;

  bool get hasExactPdfSize => pdfSizeBytes != null && pdfSizeBytes! > 0;

  /// Local thumbnail before upload.
  Uint8List? thumbnailBytes;

  PendingDrawingPage copyWith({
    int? pageIndex,
    int? sourcePageNumber,
    int? sortOrder,
    bool? selected,
    String? drawingNumber,
    String? title,
    int? estimatedPdfSizeBytes,
    int? pdfSizeBytes,
    Uint8List? thumbnailBytes,
  }) {
    return PendingDrawingPage(
      pageIndex: pageIndex ?? this.pageIndex,
      sourcePageNumber: sourcePageNumber ?? this.sourcePageNumber,
      sortOrder: sortOrder ?? this.sortOrder,
      selected: selected ?? this.selected,
      drawingNumber: drawingNumber ?? this.drawingNumber,
      title: title ?? this.title,
      estimatedPdfSizeBytes:
          estimatedPdfSizeBytes ?? this.estimatedPdfSizeBytes,
      pdfSizeBytes: pdfSizeBytes ?? this.pdfSizeBytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
    );
  }
}
