import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/tutorials/models/tutorial_video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminTutorialVideosPage extends StatefulWidget {
  const AdminTutorialVideosPage({super.key});

  @override
  State<AdminTutorialVideosPage> createState() => _AdminTutorialVideosPageState();
}

class _AdminTutorialVideosPageState extends State<AdminTutorialVideosPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _thumbnailUrl = TextEditingController();
  final _youtubeUrl = TextEditingController();
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('tutorial_videos');

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _thumbnailUrl.dispose();
    _youtubeUrl.dispose();
    super.dispose();
  }

  Future<bool> _isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final token = await user.getIdTokenResult(true);
      return token.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Stream<List<TutorialVideo>> _videosStream() {
    return _ref
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TutorialVideo.fromDoc).toList());
  }

  Future<void> _saveVideo() async {
    final title = _title.text.trim();
    final youtubeUrl = _youtubeUrl.text.trim();
    if (title.isEmpty || youtubeUrl.isEmpty) {
      Get.snackbar(
        'Tutorial video',
        'Title and YouTube URL are required.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final now = FieldValue.serverTimestamp();
      await _ref.add({
        'title': title,
        'description': _description.text.trim(),
        'thumbnailUrl': _thumbnailUrl.text.trim(),
        'youtubeUrl': youtubeUrl,
        'isPublished': true,
        'createdByUid': user?.uid ?? '',
        'createdAt': now,
        'updatedAt': now,
      });
      _title.clear();
      _description.clear();
      _thumbnailUrl.clear();
      _youtubeUrl.clear();
      Get.snackbar(
        'Tutorial video',
        'Video uploaded',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('Tutorial video', 'Upload failed: $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteVideo(TutorialVideo video) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete tutorial video?'),
        content: Text('This will remove "${video.title}" from the landing page.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _ref.doc(video.id).delete();
  }

  Future<void> _togglePublished(TutorialVideo video) async {
    await _ref.doc(video.id).update({
      'isPublished': !video.isPublished,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, access) {
        if (access.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (access.data != true) {
          return const _AdminOnlyMessage();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UploadTutorialCard(
                title: _title,
                description: _description,
                thumbnailUrl: _thumbnailUrl,
                youtubeUrl: _youtubeUrl,
                saving: _saving,
                onSave: _saveVideo,
              ),
              const SizedBox(height: 22),
              StreamBuilder<List<TutorialVideo>>(
                stream: _videosStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Could not load tutorials: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final videos = snapshot.data!;
                  if (videos.isEmpty) {
                    return const _AdminEmptyVideos();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Uploaded tutorial videos',
                        style: TextStyle(
                          color: Color(0xFF101828),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final video in videos) ...[
                        _AdminTutorialTile(
                          video: video,
                          onTogglePublished: () => _togglePublished(video),
                          onDelete: () => _deleteVideo(video),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UploadTutorialCard extends StatelessWidget {
  const _UploadTutorialCard({
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.youtubeUrl,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController thumbnailUrl;
  final TextEditingController youtubeUrl;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload tutorial video',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add the YouTube link and details. The latest published videos will appear on the landing page.',
            style: TextStyle(color: AqsColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final fields = [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: youtubeUrl,
                  decoration: const InputDecoration(
                    labelText: 'YouTube URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: thumbnailUrl,
                  decoration: const InputDecoration(
                    labelText: 'Thumbnail URL',
                    helperText: 'Optional. If empty, AQS tries to use the YouTube thumbnail.',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: description,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
              ];
              if (stacked) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: fields[2]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon:
                  saving
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.upload_rounded),
              label: Text(saving ? 'Uploading...' : 'Upload video'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTutorialTile extends StatelessWidget {
  const _AdminTutorialTile({
    required this.video,
    required this.onTogglePublished,
    required this.onDelete,
  });

  final TutorialVideo video;
  final VoidCallback onTogglePublished;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final thumb = video.effectiveThumbnailUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 136,
              height: 78,
              child:
                  thumb.isEmpty
                      ? Container(
                        color: const Color(0xFFEFF4FF),
                        child: const Icon(Icons.smart_display_outlined),
                      )
                      : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Container(
                              color: const Color(0xFFEFF4FF),
                              child: const Icon(Icons.smart_display_outlined),
                            ),
                      ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  video.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AqsColors.muted),
                ),
                const SizedBox(height: 7),
                Text(
                  video.isPublished ? 'Published' : 'Hidden',
                  style: TextStyle(
                    color:
                        video.isPublished
                            ? const Color(0xFF027A48)
                            : const Color(0xFFB42318),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onTogglePublished,
            child: Text(video.isPublished ? 'Hide' : 'Publish'),
          ),
          IconButton(
            tooltip: 'Delete video',
            onPressed: onDelete,
            color: Colors.red,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _AdminEmptyVideos extends StatelessWidget {
  const _AdminEmptyVideos();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AqsColors.border),
      ),
      child: const Text(
        'No tutorial videos uploaded yet.',
        style: TextStyle(color: AqsColors.muted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AdminOnlyMessage extends StatelessWidget {
  const _AdminOnlyMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Admin access required.',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
