import 'package:cloud_firestore/cloud_firestore.dart';

class TutorialVideo {
  const TutorialVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.youtubeUrl,
    required this.createdAt,
    required this.isPublished,
  });

  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String youtubeUrl;
  final DateTime? createdAt;
  final bool isPublished;

  factory TutorialVideo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final created = data['createdAt'];
    return TutorialVideo(
      id: doc.id,
      title: (data['title'] ?? '').toString().trim(),
      description: (data['description'] ?? '').toString().trim(),
      thumbnailUrl: (data['thumbnailUrl'] ?? '').toString().trim(),
      youtubeUrl: (data['youtubeUrl'] ?? '').toString().trim(),
      createdAt: created is Timestamp ? created.toDate() : null,
      isPublished: data['isPublished'] != false,
    );
  }

  String get effectiveThumbnailUrl {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    final id = youtubeVideoId(youtubeUrl);
    if (id == null) return '';
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }
}

String? youtubeVideoId(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return null;

  final uri = Uri.tryParse(clean);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  if (host.contains('youtu.be')) {
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return id.isEmpty ? null : id;
  }

  if (host.contains('youtube.com')) {
    final watchId = uri.queryParameters['v'];
    if (watchId != null && watchId.trim().isNotEmpty) return watchId.trim();

    final segments = uri.pathSegments;
    final shorts = segments.indexOf('shorts');
    if (shorts >= 0 && shorts + 1 < segments.length) {
      return segments[shorts + 1];
    }
    final embed = segments.indexOf('embed');
    if (embed >= 0 && embed + 1 < segments.length) {
      return segments[embed + 1];
    }
  }

  return null;
}
