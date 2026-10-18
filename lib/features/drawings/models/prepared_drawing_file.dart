import 'dart:typed_data';

class PreparedDrawingFile {
  const PreparedDrawingFile({
    required this.pageIndex,
    required this.sourcePageNumber,
    required this.sortOrder,
    required this.drawingNumber,
    required this.title,
    required this.pdfBytes,
    required this.pdfSizeBytes,
    this.thumbnailBytes,
  });

  final int pageIndex;
  final int sourcePageNumber;
  final int sortOrder;

  final String drawingNumber;
  final String title;

  /// Standalone single-page PDF.
  final Uint8List pdfBytes;

  /// Exact storage size of the standalone PDF.
  final int pdfSizeBytes;

  /// Optional small preview.
  final Uint8List? thumbnailBytes;

  int get thumbnailSizeBytes => thumbnailBytes?.lengthInBytes ?? 0;

  int get totalStorageBytes => pdfSizeBytes + thumbnailSizeBytes;
}
