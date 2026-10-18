import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/tutorials/models/tutorial_video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class TutorialVideosPage extends StatelessWidget {
  const TutorialVideosPage({super.key});

  Stream<List<TutorialVideo>> _videosStream() {
    return FirebaseFirestore.instance
        .collection('tutorial_videos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map(TutorialVideo.fromDoc)
                  .where((video) => video.isPublished)
                  .toList(),
        );
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const AqsBrand(),
        actions: [
          TextButton(
            onPressed: () => Get.offAllNamed(AppRoutes.landing),
            child: const Text('Landing page'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<List<TutorialVideo>>(
        stream: _videosStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load videos: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final videos = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 48, 22, 70),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tutorial videos',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Short practical guides for measuring, creating BOQs, and managing projects in AQS.',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 17,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 34),
                    if (videos.isEmpty)
                      const _EmptyTutorials()
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth < 680
                                  ? 1
                                  : constraints.maxWidth < 980
                                  ? 2
                                  : 3;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 18) /
                                  columns;
                          return Wrap(
                            spacing: 18,
                            runSpacing: 18,
                            children: [
                              for (final video in videos)
                                SizedBox(
                                  width: width,
                                  child: _TutorialVideoCard(
                                    video: video,
                                    onPlay: () => _openVideo(video.youtubeUrl),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TutorialVideoCard extends StatelessWidget {
  const TutorialVideoCard({
    super.key,
    required this.video,
    required this.onPlay,
  });

  final TutorialVideo video;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => _TutorialVideoCard(video: video, onPlay: onPlay);
}

class _TutorialVideoCard extends StatelessWidget {
  const _TutorialVideoCard({required this.video, required this.onPlay});

  final TutorialVideo video;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final thumb = video.effectiveThumbnailUrl;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAECF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb.isEmpty)
                      Container(
                        color: const Color(0xFFEFF4FF),
                        child: const Icon(
                          Icons.smart_display_outlined,
                          color: Color(0xFF155EEF),
                          size: 54,
                        ),
                      )
                    else
                      Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Container(
                              color: const Color(0xFFEFF4FF),
                              child: const Icon(
                                Icons.smart_display_outlined,
                                color: Color(0xFF155EEF),
                                size: 54,
                              ),
                            ),
                      ),
                    Container(color: Colors.black.withOpacity(0.18)),
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF155EEF),
                          size: 38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title.isEmpty ? 'Untitled tutorial' : video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF101828),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    video.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(
                        Icons.ondemand_video_rounded,
                        size: 17,
                        color: AqsColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Watch on YouTube',
                        style: TextStyle(
                          color: AqsColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTutorials extends StatelessWidget {
  const _EmptyTutorials();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.video_library_outlined, color: AqsColors.primary, size: 46),
          SizedBox(height: 12),
          Text(
            'Tutorial videos will appear here once the admin uploads them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
