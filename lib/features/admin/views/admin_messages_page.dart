import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminMessagesPage extends StatelessWidget {
  const AdminMessagesPage({super.key});

  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance.collection('contact-messages');

  String _text(Map<String, dynamic> data, String key, {String fallback = '—'}) {
    final value = (data[key] ?? '').toString().trim();
    return value.isEmpty ? fallback : value;
  }

  String _date(dynamic value) {
    final date = value is Timestamp ? value.toDate() : null;
    if (date == null) return 'Date unavailable';

    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _openMessage(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();

    if (_text(data, 'status', fallback: 'new').toLowerCase() == 'new') {
      try {
        await document.reference.update({
          'status': 'read',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        debugPrint('Could not mark contact message as read: $error');
      }
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(_text(data, 'subject', fallback: 'User message')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MessageDetail(label: 'From', value: _text(data, 'name')),
                    _MessageDetail(label: 'Email', value: _text(data, 'email')),
                    _MessageDetail(label: 'Phone', value: _text(data, 'phone')),
                    _MessageDetail(label: 'Source', value: _text(data, 'source')),
                    _MessageDetail(
                      label: 'Received',
                      value: _date(data['createdAt']),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Message',
                      style: TextStyle(
                        color: AqsColors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _text(data, 'message'),
                      style: const TextStyle(
                        color: AqsColors.ink,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Row(
          children: [
            AqsBrand(),
            SizedBox(width: 18),
            Text('User Messages'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _messages.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _MessageState(
              icon: Icons.error_outline_rounded,
              title: 'Messages could not be loaded',
              subtitle: 'Check the admin Firestore permission and try again.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final documents = snapshot.data!.docs;

          if (documents.isEmpty) {
            return const _MessageState(
              icon: Icons.mark_email_read_outlined,
              title: 'No messages yet',
              subtitle: 'Messages sent from the contact form will appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
            itemCount: documents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final document = documents[index];
              final data = document.data();
              final isNew =
                  _text(data, 'status', fallback: 'new').toLowerCase() == 'new';

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: isNew ? const Color(0xFFEFF6FF) : Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: CircleAvatar(
                        backgroundColor:
                            isNew
                                ? AqsColors.primary
                                : const Color(0xFFF2F4F7),
                        child: Icon(
                          isNew
                              ? Icons.mark_email_unread_outlined
                              : Icons.mark_email_read_outlined,
                          color: isNew ? Colors.white : AqsColors.muted,
                        ),
                      ),
                      title: Text(
                        _text(data, 'subject', fallback: 'User message'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isNew ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${_text(data, 'name')} · ${_text(data, 'email')}\n'
                          '${_text(data, 'message')}\n${_date(data['createdAt'])}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      trailing:
                          isNew
                              ? const Chip(label: Text('New'))
                              : const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openMessage(context, document),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageDetail extends StatelessWidget {
  const _MessageDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: AqsColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AqsColors.primary),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AqsColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
