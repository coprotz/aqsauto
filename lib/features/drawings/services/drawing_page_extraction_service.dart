import 'dart:typed_data';

import 'package:aqs/features/drawings/models/drawing_storage_estimate.dart';
import 'package:aqs/features/drawings/models/pending_drawing_page.dart';
import 'package:aqs/features/drawings/models/prepared_drawing_file.dart';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class DrawingPageExtractionService {
  DrawingPageExtractionService._();

  static final DrawingPageExtractionService instance =
      DrawingPageExtractionService._();

  Future<DrawingStorageEstimate> prepareSelectedPages({
    required Uint8List sourcePdfBytes,
    required List<PendingDrawingPage> pages,
  }) async {
    if (sourcePdfBytes.isEmpty) {
      throw Exception('Source PDF is empty.');
    }

    final selectedPages =
        pages.where((page) => page.selected).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (selectedPages.isEmpty) {
      throw Exception('Select at least one drawing.');
    }

    final prepared = <PreparedDrawingFile>[];

    //
    // We create one standalone PDF
    // for each selected source page.
    //
    for (final selectedPage in selectedPages) {
      final extractedBytes = await _extractSinglePage(
        sourcePdfBytes: sourcePdfBytes,
        sourcePageNumber: selectedPage.sourcePageNumber,
      );

      prepared.add(
        PreparedDrawingFile(
          pageIndex: selectedPage.pageIndex,

          sourcePageNumber: selectedPage.sourcePageNumber,

          sortOrder: selectedPage.sortOrder,

          drawingNumber: selectedPage.drawingNumber.trim(),

          title: selectedPage.title.trim(),

          pdfBytes: extractedBytes,

          pdfSizeBytes: extractedBytes.lengthInBytes,

          //
          // We can connect the small
          // existing preview later.
          //
          thumbnailBytes: selectedPage.thumbnailBytes,
        ),
      );
    }

    return DrawingStorageEstimate(drawings: prepared);
  }

  Future<Map<int, int>> estimatePageStorageShares({
    required Uint8List sourcePdfBytes,
    required List<PendingDrawingPage> pages,
  }) async {
    if (sourcePdfBytes.isEmpty || pages.isEmpty) {
      return const {};
    }

    final orderedPages =
        pages.toList()
          ..sort((a, b) => a.sourcePageNumber.compareTo(b.sourcePageNumber));

    final weights = <int, int>{};

    for (final page in orderedPages) {
      final extractedBytes = await _extractSinglePage(
        sourcePdfBytes: sourcePdfBytes,
        sourcePageNumber: page.sourcePageNumber,
      );

      weights[page.pageIndex] = extractedBytes.lengthInBytes;
    }

    final totalWeight = weights.values.fold<int>(
      0,
      (total, size) => total + size,
    );

    if (totalWeight <= 0) {
      return const {};
    }

    final sourceSize = sourcePdfBytes.lengthInBytes;
    var allocated = 0;

    final rawShares =
        orderedPages.map((page) {
            final weight = weights[page.pageIndex] ?? 0;
            final rawShare = sourceSize * weight / totalWeight;
            final wholeBytes = rawShare.floor();

            allocated += wholeBytes;

            return _PageStorageShare(
              pageIndex: page.pageIndex,
              bytes: wholeBytes,
              remainder: rawShare - wholeBytes,
            );
          }).toList()
          ..sort((a, b) {
            final byRemainder = b.remainder.compareTo(a.remainder);

            if (byRemainder != 0) {
              return byRemainder;
            }

            return a.pageIndex.compareTo(b.pageIndex);
          });

    var remaining = sourceSize - allocated;

    for (final share in rawShares) {
      if (remaining <= 0) {
        break;
      }

      share.bytes += 1;
      remaining -= 1;
    }

    return {for (final share in rawShares) share.pageIndex: share.bytes};
  }

  Future<Map<int, int>> extractPagePdfSizes({
    required Uint8List sourcePdfBytes,
    required List<PendingDrawingPage> pages,
  }) async {
    if (sourcePdfBytes.isEmpty || pages.isEmpty) {
      return const {};
    }

    final orderedPages =
        pages.toList()
          ..sort((a, b) => a.sourcePageNumber.compareTo(b.sourcePageNumber));

    final sizes = <int, int>{};

    for (final page in orderedPages) {
      final extractedBytes = await _extractSinglePage(
        sourcePdfBytes: sourcePdfBytes,
        sourcePageNumber: page.sourcePageNumber,
      );

      sizes[page.pageIndex] = extractedBytes.lengthInBytes;
    }

    return sizes;
  }

  Future<Uint8List> _extractSinglePage({
    required Uint8List sourcePdfBytes,
    required int sourcePageNumber,
  }) async {
    //
    // Syncfusion expects zero-based page index.
    //
    final targetIndex = sourcePageNumber - 1;

    if (targetIndex < 0) {
      throw Exception('Invalid source page number.');
    }

    //
    // IMPORTANT:
    // Make an independent source copy.
    //
    final sourceCopy = Uint8List.fromList(sourcePdfBytes);

    final document = PdfDocument(inputBytes: sourceCopy);

    try {
      if (targetIndex >= document.pages.count) {
        throw Exception('PDF page $sourcePageNumber does not exist.');
      }

      //
      // Remove all pages except the
      // required source page.
      //
      // Work backwards so indexes remain stable.
      //
      for (var index = document.pages.count - 1; index >= 0; index--) {
        if (index == targetIndex) {
          continue;
        }

        document.pages.removeAt(index);
      }

      //
      // The current API can save the modified
      // document directly as Uint8List.
      //
      final bytes = await document.saveAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Extracted PDF page is empty.');
      }

      return bytes;
    } finally {
      document.dispose();
    }
  }
}

class _PageStorageShare {
  _PageStorageShare({
    required this.pageIndex,
    required this.bytes,
    required this.remainder,
  });

  final int pageIndex;
  int bytes;
  final double remainder;
}
