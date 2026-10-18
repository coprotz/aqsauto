import 'dart:convert';
import 'dart:typed_data';

import 'package:aqs/features/drawings/models/drawing_row.dart';
import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';

class DrawingDownloadProgress {
  const DrawingDownloadProgress({
    required this.completed,
    required this.total,
    required this.currentDrawing,
  });

  final int completed;
  final int total;
  final String currentDrawing;
}

class DrawingDownloadResult {
  const DrawingDownloadResult({
    required this.downloaded,
    required this.failedDrawings,
  });

  final int downloaded;
  final List<String> failedDrawings;

  int get failed => failedDrawings.length;
}

/// Downloads the original drawing PDFs already referenced by the register.
///
/// Multiple files are written into one standards-compliant ZIP archive. The
/// ZIP uses the "store" method because PDFs are normally compressed already;
/// recompressing them in the browser wastes time and memory for little gain.
class DrawingDownloadService {
  DrawingDownloadService({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              responseType: ResponseType.bytes,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 5),
              validateStatus:
                  (status) => status != null && status >= 200 && status < 300,
            ),
          );

  final Dio _client;

  Future<DrawingDownloadResult> download({
    required List<DrawingRow> drawings,
    required String projectName,
    required String buildingName,
    void Function(DrawingDownloadProgress progress)? onProgress,
  }) async {
    if (drawings.isEmpty) {
      throw const FormatException('Select at least one drawing.');
    }

    final files = <_DownloadedDrawing>[];
    final failures = <String>[];
    final usedNames = <String>{};

    for (var index = 0; index < drawings.length; index++) {
      final drawing = drawings[index];
      final label = _drawingLabel(drawing);
      onProgress?.call(
        DrawingDownloadProgress(
          completed: index,
          total: drawings.length,
          currentDrawing: label,
        ),
      );

      try {
        final url = drawing.downloadUrl.trim();
        if (url.isEmpty) {
          throw StateError('Original drawing file is unavailable.');
        }
        final response = await _client.get<List<int>>(url);
        final data = response.data;
        if (data == null || data.isEmpty) {
          throw StateError('The downloaded file is empty.');
        }
        final bytes = data is Uint8List ? data : Uint8List.fromList(data);
        files.add(
          _DownloadedDrawing(
            name: _uniquePdfName(drawing, usedNames),
            bytes: bytes,
          ),
        );
      } catch (_) {
        failures.add(label);
      }

      onProgress?.call(
        DrawingDownloadProgress(
          completed: index + 1,
          total: drawings.length,
          currentDrawing: label,
        ),
      );
    }

    if (files.isEmpty) {
      throw StateError('None of the selected drawing files could be downloaded.');
    }

    if (drawings.length == 1 && files.length == 1) {
      final file = files.single;
      await FileSaver.instance.saveFile(
        name: _withoutPdfExtension(file.name),
        bytes: file.bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    } else {
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final project = _safeFilePart(projectName, fallback: 'Project');
      final building = _safeFilePart(buildingName, fallback: 'Building');
      final zipBytes = _StoredZipEncoder().encode(files);
      await FileSaver.instance.saveFile(
        name: 'AQS_${project}_${building}_Drawings_$stamp',
        bytes: zipBytes,
        fileExtension: 'zip',
        mimeType: MimeType.other,
        customMimeType: 'application/zip',
      );
    }

    return DrawingDownloadResult(
      downloaded: files.length,
      failedDrawings: List.unmodifiable(failures),
    );
  }

  static String _drawingLabel(DrawingRow drawing) {
    final title = drawing.title.trim();
    return title.isEmpty ? 'Untitled drawing' : title;
  }

  static String _uniquePdfName(DrawingRow drawing, Set<String> usedNames) {
    final sheet = _safeFilePart(drawing.sheetNumber, fallback: '');
    final title = _safeFilePart(_drawingLabel(drawing), fallback: 'Drawing');
    final base = sheet.isEmpty ? title : '${sheet}_$title';
    var candidate = '$base.pdf';
    var suffix = 2;
    while (!usedNames.add(candidate.toLowerCase())) {
      candidate = '${base}_$suffix.pdf';
      suffix++;
    }
    return candidate;
  }

  static String _safeFilePart(String value, {required String fallback}) {
    final cleaned = value
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static String _withoutPdfExtension(String value) => value.replaceFirst(
    RegExp(r'\.pdf$', caseSensitive: false),
    '',
  );
}

class _DownloadedDrawing {
  const _DownloadedDrawing({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _ZipEntry {
  const _ZipEntry({
    required this.nameBytes,
    required this.crc32,
    required this.size,
    required this.localHeaderOffset,
  });

  final Uint8List nameBytes;
  final int crc32;
  final int size;
  final int localHeaderOffset;
}

/// Minimal ZIP encoder using the store method (compression method 0).
/// This avoids adding another package dependency to the existing application.
class _StoredZipEncoder {
  static const int _utf8Flag = 0x0800;
  static final List<int> _crcTable = List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
    return crc;
  }, growable: false);

  Uint8List encode(List<_DownloadedDrawing> files) {
    final output = BytesBuilder(copy: false);
    final centralEntries = <_ZipEntry>[];
    var offset = 0;
    final dateTime = _dosDateTime(DateTime.now());

    for (final file in files) {
      final nameBytes = Uint8List.fromList(utf8.encode(file.name));
      final crc = _crc32(file.bytes);
      final header = BytesBuilder(copy: false)
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(_utf8Flag))
        ..add(_u16(0))
        ..add(_u16(dateTime.time))
        ..add(_u16(dateTime.date))
        ..add(_u32(crc))
        ..add(_u32(file.bytes.length))
        ..add(_u32(file.bytes.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(nameBytes);
      final headerBytes = header.takeBytes();
      centralEntries.add(
        _ZipEntry(
          nameBytes: nameBytes,
          crc32: crc,
          size: file.bytes.length,
          localHeaderOffset: offset,
        ),
      );
      output
        ..add(headerBytes)
        ..add(file.bytes);
      offset += headerBytes.length + file.bytes.length;
    }

    final centralStart = offset;
    for (final entry in centralEntries) {
      final header = BytesBuilder(copy: false)
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(_utf8Flag))
        ..add(_u16(0))
        ..add(_u16(dateTime.time))
        ..add(_u16(dateTime.date))
        ..add(_u32(entry.crc32))
        ..add(_u32(entry.size))
        ..add(_u32(entry.size))
        ..add(_u16(entry.nameBytes.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(entry.localHeaderOffset))
        ..add(entry.nameBytes);
      final bytes = header.takeBytes();
      output.add(bytes);
      offset += bytes.length;
    }

    final centralSize = offset - centralStart;
    output
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(centralEntries.length))
      ..add(_u16(centralEntries.length))
      ..add(_u32(centralSize))
      ..add(_u32(centralStart))
      ..add(_u16(0));
    return output.takeBytes();
  }

  static ({int date, int time}) _dosDateTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year.clamp(1980, 2107).toInt();
    return (
      date: ((year - 1980) << 9) | (local.month << 5) | local.day,
      time: (local.hour << 11) | (local.minute << 5) | (local.second ~/ 2),
    );
  }

  static Uint8List _u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = (crc >> 8) ^ _crcTable[(crc ^ byte) & 0xff];
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
