import 'dart:async';
import 'dart:typed_data';

import 'package:aqs/features/drawings/models/pending_drawing_page.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion_pdf;

// import '../models/pending_drawing_page.dart';

class PdfDrawingService {
  PdfDrawingService._();

  static final PdfDrawingService instance = PdfDrawingService._();

  Future<void> _thumbnailQueue = Future<void>.value();

  Future<List<PendingDrawingPage>> inspectPdf(Uint8List pdfBytes) async {
    final safeBytes = Uint8List.fromList(pdfBytes);

    final document = await PdfDocument.openData(safeBytes);

    try {
      final count = document.pagesCount;

      debugPrint('PDF pages detected: $count');

      final basePageSize = count > 0 ? safeBytes.lengthInBytes ~/ count : 0;
      var remainder = count > 0 ? safeBytes.lengthInBytes % count : 0;

      return List.generate(count, (index) {
        final estimatedSize = basePageSize + (remainder > 0 ? 1 : 0);
        if (remainder > 0) {
          remainder -= 1;
        }

        return PendingDrawingPage(
          pageIndex: index,

          sourcePageNumber: index + 1,

          sortOrder: index + 1,

          selected: false,

          drawingNumber: '',

          title: '',

          estimatedPdfSizeBytes: estimatedSize,
        );
      });
    } finally {
      await document.close();
    }
  }

  Future<List<PendingDrawingPage>> inspectPdfWithFallbackReader(
    Uint8List pdfBytes,
  ) async {
    final safeBytes = Uint8List.fromList(pdfBytes);
    final document = syncfusion_pdf.PdfDocument(inputBytes: safeBytes);

    try {
      final count = document.pages.count;

      debugPrint('PDF pages detected by fallback reader: $count');

      final basePageSize = count > 0 ? safeBytes.lengthInBytes ~/ count : 0;
      var remainder = count > 0 ? safeBytes.lengthInBytes % count : 0;

      return List.generate(count, (index) {
        final estimatedSize = basePageSize + (remainder > 0 ? 1 : 0);

        if (remainder > 0) {
          remainder -= 1;
        }

        return PendingDrawingPage(
          pageIndex: index,
          sourcePageNumber: index + 1,
          sortOrder: index + 1,
          selected: false,
          drawingNumber: '',
          title: '',
          estimatedPdfSizeBytes: estimatedSize,
        );
      });
    } finally {
      document.dispose();
    }
  }

  Future<Uint8List?> queueThumbnail({
    required Uint8List pdfBytes,
    required int pageIndex,
    double width = 140,
  }) {
    final completer = Completer<Uint8List?>();

    _thumbnailQueue = _thumbnailQueue.then((_) async {
      try {
        final result = await renderThumbnail(
          pdfBytes: pdfBytes,
          pageIndex: pageIndex,
          width: width,
        );

        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// Generates a thumbnail for one page.
  ///
  /// This is intentionally separate from inspectPdf()
  /// so a 100-page PDF doesn't have to render all
  /// thumbnails before the UI can appear.
  Future<Uint8List?> renderThumbnail({
    required Uint8List pdfBytes,
    required int pageIndex,
    double width = 240,
  }) async {
    if (pdfBytes.isEmpty) {
      return null;
    }

    PdfDocument? document;
    PdfPage? page;

    try {
      //
      // IMPORTANT FOR FLUTTER WEB / PDF.JS
      //
      // PDF.js may transfer/detach the underlying ArrayBuffer.
      // Therefore each document open must receive its own
      // independent Uint8List.
      //
      final safeBytes = Uint8List.fromList(pdfBytes);

      document = await PdfDocument.openData(safeBytes);

      final pageNumber = pageIndex + 1;

      if (pageNumber < 1 || pageNumber > document.pagesCount) {
        throw Exception('Invalid PDF page number: $pageNumber');
      }

      page = await document.getPage(pageNumber);

      final sourceWidth = page.width;

      final sourceHeight = page.height;

      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw Exception('Invalid PDF page dimensions.');
      }

      final ratio = sourceHeight / sourceWidth;

      final targetWidth = width;

      final targetHeight = targetWidth * ratio;

      final image = await page.render(width: targetWidth, height: targetHeight);

      if (image == null) {
        throw Exception('PDF renderer returned no image.');
      }

      if (image.bytes.isEmpty) {
        throw Exception('PDF renderer returned empty image bytes.');
      }

      //
      // Copy rendered bytes too so they are completely
      // independent from renderer-managed memory.
      //
      return Uint8List.fromList(image.bytes);
    } catch (error, stackTrace) {
      print(
        'Thumbnail render failed '
        'for page ${pageIndex + 1}: '
        '$error',
      );

      print(stackTrace);

      rethrow;
    } finally {
      try {
        await page?.close();
      } catch (_) {}

      try {
        await document?.close();
      } catch (_) {}
    }
  }

  /// Generates thumbnails for all pages.
  ///
  /// Useful initially, but for very large PDFs
  /// we will prefer lazy thumbnail loading.
  Future<List<PendingDrawingPage>> inspectPdfWithThumbnails(
    Uint8List bytes, {
    double thumbnailWidth = 220,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('The selected PDF is empty.');
    }

    //
    // Give PDF.js its own independent buffer.
    //
    final safeBytes = Uint8List.fromList(bytes);

    final document = await PdfDocument.openData(safeBytes);

    try {
      final result = <PendingDrawingPage>[];
      final pageCount = document.pagesCount;
      final basePageSize =
          pageCount > 0 ? safeBytes.lengthInBytes ~/ pageCount : 0;
      var remainder = pageCount > 0 ? safeBytes.lengthInBytes % pageCount : 0;

      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final sourcePageNumber = pageIndex + 1;
        final estimatedSize = basePageSize + (remainder > 0 ? 1 : 0);
        if (remainder > 0) {
          remainder -= 1;
        }

        Uint8List? thumbnailBytes;

        PdfPage? page;

        try {
          page = await document.getPage(sourcePageNumber);

          final ratio = page.height / page.width;

          final image = await page.render(
            width: thumbnailWidth,
            height: thumbnailWidth * ratio,
          );

          if (image != null && image.bytes.isNotEmpty) {
            thumbnailBytes = Uint8List.fromList(image.bytes);
          }
        } catch (error) {
          print(
            'Could not render page '
            '$sourcePageNumber: '
            '$error',
          );
        } finally {
          try {
            await page?.close();
          } catch (_) {}
        }

        result.add(
          PendingDrawingPage(
            pageIndex: pageIndex,

            sourcePageNumber: sourcePageNumber,

            sortOrder: sourcePageNumber,

            selected: true,

            drawingNumber: '',

            title: '',

            estimatedPdfSizeBytes: estimatedSize,

            thumbnailBytes: thumbnailBytes,
          ),
        );
      }

      return result;
    } finally {
      await document.close();
    }
  }
}
