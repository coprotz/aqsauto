import 'prepared_drawing_file.dart';

class DrawingStorageEstimate {
  const DrawingStorageEstimate({required this.drawings});

  final List<PreparedDrawingFile> drawings;

  int get drawingPdfBytes {
    return drawings.fold<int>(
      0,
      (total, drawing) => total + drawing.pdfSizeBytes,
    );
  }

  int get thumbnailBytes {
    return drawings.fold<int>(
      0,
      (total, drawing) => total + drawing.thumbnailSizeBytes,
    );
  }

  int get totalBytes {
    return drawingPdfBytes + thumbnailBytes;
  }

  int get drawingCount => drawings.length;
}
