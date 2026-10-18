import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/drawings/services/pdf_drawing_service.dart';
import 'package:flutter/material.dart';

class DrawingPageThumbnail extends StatefulWidget {
  const DrawingPageThumbnail({
    super.key,
    required this.pdfBytes,
    required this.pageIndex,
    this.width = 100,
    this.enabled = true,
  });

  final Uint8List pdfBytes;
  final int pageIndex;
  final bool enabled;

  final double width;

  @override
  State<DrawingPageThumbnail> createState() => _DrawingPageThumbnailState();

  static void clearCache() {}
}

class _DrawingPageThumbnailState extends State<DrawingPageThumbnail> {
  static final Map<int, Uint8List> _cache = <int, Uint8List>{};

  Uint8List? _thumbnail;

  bool _loading = false;

  bool _failed = false;

  @override
  void initState() {
    super.initState();

    final cached = _cache[widget.pageIndex];

    if (cached != null) {
      _thumbnail = cached;
    }
  }

  // static void clearCache() {
  //   _cache.clear();
  // }

  Future<void> _load() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;

      _failed = false;
    });

    try {
      final image = await PdfDrawingService.instance.queueThumbnail(
        pdfBytes: widget.pdfBytes,

        pageIndex: widget.pageIndex,

        //
        // Small preview is enough.
        //
        width: 130,
      );

      if (image != null && image.isNotEmpty) {
        _cache[widget.pageIndex] = image;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _thumbnail = image;

        _loading = false;
      });
    } catch (error) {
      debugPrint(
        'Thumbnail page '
        '${widget.pageIndex + 1} '
        'failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _failed = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant DrawingPageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.enabled &&
        widget.enabled &&
        _thumbnail == null &&
        !_loading) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,

      height: widget.width * 1.30,

      clipBehavior: Clip.antiAlias,

      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),

      child: _buildPreview(),
    );
  }

  Widget _buildPreview() {
    if (_thumbnail != null) {
      return Image.memory(
        _thumbnail!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    if (_failed) {
      return Center(
        child: TextButton.icon(
          onPressed: widget.enabled ? _load : null,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Retry preview'),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Center(
      child: TextButton.icon(
        onPressed: widget.enabled ? _load : null,
        icon: const Icon(Icons.visibility_outlined, size: 17),
        label: const Text('Load preview'),
      ),
    );
  }
}
