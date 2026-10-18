class DrawingRow {
  final String id;
  final String title;
  final String sheetNumber;
  final bool calibrated;
  final String status;
  final String error;
  final String imageUrl;
  final String downloadUrl;
  final String imagePath;
  final int sourcePageNumber;
  final bool packageUpload;
  final bool clientRenderedImage;
  final Map<String, dynamic> raw;

  const DrawingRow({
    required this.id,
    required this.title,
    required this.sheetNumber,
    required this.calibrated,
    required this.status,
    required this.error,
    required this.imageUrl,
    required this.downloadUrl,
    required this.imagePath,
    required this.sourcePageNumber,
    required this.packageUpload,
    required this.clientRenderedImage,
    required this.raw,
  });

  String get scopedImageUrl {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !uri.hasScheme) return imageUrl;

    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'aqsDrawingId': id,
            if (imagePath.isNotEmpty) 'aqsImagePath': imagePath,
            'aqsPage': '$sourcePageNumber',
          },
        )
        .toString();
  }
}
