import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class BuildingNotesTab extends StatefulWidget {
  const BuildingNotesTab({
    super.key,
    required this.projectId,
    required this.buildingId,
    required this.buildingName,
  });

  final String projectId;
  final String buildingId;
  final String buildingName;

  @override
  State<BuildingNotesTab> createState() => _BuildingNotesTabState();
}

class _BuildingNotesTabState extends State<BuildingNotesTab> {
  static const _categories = <String>[
    'General',
    'Site',
    'Client',
    'QS',
    'Issue',
  ];

  final TextEditingController _searchController = TextEditingController();
  String _categoryFilter = 'All';

  CollectionReference<Map<String, dynamic>> get _notesRef =>
      FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('buildings')
          .doc(widget.buildingId)
          .collection('notes');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Map<String, String> _userFields(String prefix) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    final email = user?.email?.trim() ?? '';
    final fallbackName = email.isNotEmpty ? email : 'Unknown user';

    return {
      '${prefix}ByUid': user?.uid ?? '',
      '${prefix}ByName': displayName.isNotEmpty ? displayName : fallbackName,
      '${prefix}ByEmail': email,
    };
  }

  Future<void> _saveNote({_BuildingNote? note}) async {
    final result = await _showNoteEditor(note: note);
    if (result == null) return;

    try {
      final noteRef = note == null ? _notesRef.doc() : _notesRef.doc(note.id);
      final uploadedAttachment =
          result.pickedAttachment == null
              ? null
              : await _uploadAttachment(
                noteId: noteRef.id,
                attachment: result.pickedAttachment!,
              );
      final keepsExistingAttachment =
          note != null &&
          result.attachmentName == note.attachmentName &&
          result.attachmentUrl == note.attachmentUrl;
      final data = <String, dynamic>{
        'title': result.title,
        'body': result.body,
        'category': result.category,
        'pinned': result.pinned,
        'attachmentName':
            uploadedAttachment?.name ?? result.attachmentName,
        'attachmentUrl': uploadedAttachment?.url ?? result.attachmentUrl,
        'attachmentPath':
            uploadedAttachment?.path ??
            (keepsExistingAttachment ? result.attachmentPath : ''),
        'updatedAt': FieldValue.serverTimestamp(),
        ..._userFields('updated'),
      };

      if (note == null) {
        await noteRef.set({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
          ..._userFields('created'),
        });
        _showMessage('Note added.');
      } else {
        await noteRef.update(data);
        if (note.attachmentPath.isNotEmpty && !keepsExistingAttachment) {
          await _deleteStoredAttachment(note.attachmentPath);
        }
        _showMessage('Note updated.');
      }
    } catch (e) {
      _showMessage('Could not save note: $e');
    }
  }

  Future<_StoredAttachment> _uploadAttachment({
    required String noteId,
    required _PickedAttachment attachment,
  }) async {
    final safeName = attachment.name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final storagePath =
        'projects/${widget.projectId}/buildings/${widget.buildingId}'
        '/notes/$noteId/attachments/'
        '${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref(storagePath);

    await ref.putData(attachment.bytes);
    final url = await ref.getDownloadURL();
    return _StoredAttachment(
      name: attachment.name,
      url: url,
      path: storagePath,
    );
  }

  Future<void> _deleteStoredAttachment(String path) async {
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {
      // Note saves and deletes should still succeed if Storage cleanup fails.
    }
  }

  Future<_NoteEditorResult?> _showNoteEditor({_BuildingNote? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final bodyController = TextEditingController(text: note?.body ?? '');
    final attachmentNameController = TextEditingController(
      text: note?.attachmentName ?? '',
    );
    final attachmentUrlController = TextEditingController(
      text: note?.attachmentUrl ?? '',
    );
    final formKey = GlobalKey<FormState>();
    var category =
        _categories.contains(note?.category) ? note!.category : _categories[0];
    var pinned = note?.pinned ?? false;
    _PickedAttachment? pickedAttachment;

    try {
      return await showDialog<_NoteEditorResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(note == null ? 'Add note' : 'Edit note'),
                content: SizedBox(
                  width: 620,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                              hintText: 'e.g. Client requested revised ceiling finish',
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Enter a note title.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: category,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items:
                                _categories
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => category = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: bodyController,
                            minLines: 5,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Comment',
                              alignLabelWithHint: true,
                              hintText: 'Write the instruction, comment, issue, or site note.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: attachmentNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Attachment name',
                                    hintText: 'e.g. Revised sketch',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: attachmentUrlController,
                                  decoration: const InputDecoration(
                                    labelText: 'Attachment link',
                                    hintText: 'https://...',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked =
                                      await FilePicker.platform.pickFiles(
                                    withData: true,
                                  );
                                  if (picked == null ||
                                      picked.files.isEmpty) {
                                    return;
                                  }

                                  final file = picked.files.single;
                                  final bytes = file.bytes;
                                  if (bytes == null) {
                                    _showMessage(
                                      'Could not read the selected file.',
                                    );
                                    return;
                                  }

                                  setDialogState(() {
                                    pickedAttachment = _PickedAttachment(
                                      name: file.name,
                                      bytes: bytes,
                                    );
                                    attachmentNameController.text = file.name;
                                    attachmentUrlController.clear();
                                  });
                                },
                                icon: const Icon(Icons.attach_file_rounded),
                                label: const Text('Attach file'),
                              ),
                              if (pickedAttachment != null)
                                _PickedAttachmentPill(
                                  fileName: pickedAttachment!.name,
                                  onClear:
                                      () => setDialogState(
                                        () => pickedAttachment = null,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: pinned,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Pin this note',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Pinned notes stay at the top of the list.',
                            ),
                            onChanged: (value) {
                              setDialogState(() => pinned = value ?? false);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      Navigator.pop(
                        dialogContext,
                        _NoteEditorResult(
                          title: titleController.text.trim(),
                          body: bodyController.text.trim(),
                          category: category,
                          pinned: pinned,
                          attachmentName:
                              attachmentNameController.text.trim(),
                          attachmentUrl: attachmentUrlController.text.trim(),
                          attachmentPath: note?.attachmentPath ?? '',
                          pickedAttachment: pickedAttachment,
                        ),
                      );
                    },
                    icon: Icon(
                      note == null
                          ? Icons.add_rounded
                          : Icons.check_rounded,
                    ),
                    label: Text(note == null ? 'Add note' : 'Save changes'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      bodyController.dispose();
      attachmentNameController.dispose();
      attachmentUrlController.dispose();
    }
  }

  Future<void> _deleteNote(_BuildingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Color(0xFFD92D20),
          ),
          title: const Text('Delete note?'),
          content: Text(
            '"${note.title}" will be removed from this building.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD92D20),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _notesRef.doc(note.id).delete();
      if (note.attachmentPath.isNotEmpty) {
        await _deleteStoredAttachment(note.attachmentPath);
      }
      _showMessage('Note deleted.');
    } catch (e) {
      _showMessage('Could not delete note: $e');
    }
  }

  Future<void> _togglePinned(_BuildingNote note) async {
    try {
      await _notesRef.doc(note.id).update({
        'pinned': !note.pinned,
        'updatedAt': FieldValue.serverTimestamp(),
        ..._userFields('updated'),
      });
    } catch (e) {
      _showMessage('Could not update note: $e');
    }
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showMessage('Attachment link must start with http:// or https://.');
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        _showMessage('Could not open attachment.');
      }
    } catch (_) {
      _showMessage('Could not open attachment.');
    }
  }

  List<_BuildingNote> _filterNotes(List<_BuildingNote> notes) {
    final search = _searchController.text.trim().toLowerCase();
    final filtered =
        notes.where((note) {
          final matchesCategory =
              _categoryFilter == 'All' || note.category == _categoryFilter;
          final haystack = [
            note.title,
            note.body,
            note.category,
            note.createdByName,
            note.updatedByName,
            note.attachmentName,
            note.attachmentUrl,
          ].join(' ').toLowerCase();
          return matchesCategory && (search.isEmpty || haystack.contains(search));
        }).toList();

    filtered.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.sortDate.compareTo(a.sortDate);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _notesRef.orderBy('updatedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        final notes =
            snapshot.data?.docs.map(_BuildingNote.fromDoc).toList() ??
                <_BuildingNote>[];
        final filteredNotes = _filterNotes(notes);

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final padding = compact ? 12.0 : 24.0;

            if (snapshot.hasError) {
              return _NotesFailure(
                message: 'Could not load notes: ${snapshot.error}',
              );
            }

            return ListView(
              padding: EdgeInsets.all(padding),
              children: [
                _NotesHeader(
                  buildingName: widget.buildingName,
                  compact: compact,
                  onAdd: () => _saveNote(),
                ),
                const SizedBox(height: 16),
                _NotesSummaryRow(
                  total: notes.length,
                  pinned: notes.where((note) => note.pinned).length,
                  attachments:
                      notes.where((note) => note.attachmentUrl.isNotEmpty).length,
                  compact: compact,
                ),
                const SizedBox(height: 16),
                _NotesFilters(
                  searchController: _searchController,
                  categoryFilter: _categoryFilter,
                  categories: const ['All', ..._categories],
                  onCategoryChanged:
                      (category) => setState(() => _categoryFilter = category),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    notes.isEmpty)
                  const _NotesLoading()
                else if (notes.isEmpty)
                  _NotesEmpty(
                    onAdd: () => _saveNote(),
                  )
                else if (filteredNotes.isEmpty)
                  const _NotesNoResults()
                else
                  ...filteredNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _NoteCard(
                        note: note,
                        onEdit: () => _saveNote(note: note),
                        onDelete: () => _deleteNote(note),
                        onTogglePinned: () => _togglePinned(note),
                        onOpenAttachment:
                            note.attachmentUrl.isEmpty
                                ? null
                                : () => _openAttachment(note.attachmentUrl),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NotesHeader extends StatelessWidget {
  const _NotesHeader({
    required this.buildingName,
    required this.compact,
    required this.onAdd,
  });

  final String buildingName;
  final bool compact;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.notes_rounded, color: AqsColors.primary),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notes',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AqsColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Track comments, site instructions, issues, and attachment links for $buildingName.',
          style: const TextStyle(
            color: AqsColors.muted,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
    final action = FilledButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add_rounded),
      label: const Text('New note'),
    );

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(height: 14),
                  copy,
                  const SizedBox(height: 14),
                  action,
                ],
              )
              : Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: copy),
                  const SizedBox(width: 14),
                  action,
                ],
              ),
    );
  }
}

class _NotesSummaryRow extends StatelessWidget {
  const _NotesSummaryRow({
    required this.total,
    required this.pinned,
    required this.attachments,
    required this.compact,
  });

  final int total;
  final int pinned;
  final int attachments;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _NotesSummaryCard(
        icon: Icons.notes_outlined,
        label: 'Notes',
        value: total.toString(),
      ),
      _NotesSummaryCard(
        icon: Icons.push_pin_outlined,
        label: 'Pinned',
        value: pinned.toString(),
      ),
      _NotesSummaryCard(
        icon: Icons.attach_file_rounded,
        label: 'Attachments',
        value: attachments.toString(),
      ),
    ];

    if (compact) {
      return Column(
        children:
            cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: card,
                  ),
                )
                .toList(),
      );
    }

    return Row(
      children:
          cards
              .map(
                (card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: card,
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _NotesSummaryCard extends StatelessWidget {
  const _NotesSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AqsColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AqsColors.ink,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AqsColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotesFilters extends StatelessWidget {
  const _NotesFilters({
    required this.searchController,
    required this.categoryFilter,
    required this.categories,
    required this.onCategoryChanged,
  });

  final TextEditingController searchController;
  final String categoryFilter;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search notes, people, categories, or attachments',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                categories
                    .map(
                      (category) => ChoiceChip(
                        label: Text(category),
                        selected: categoryFilter == category,
                        onSelected: (_) => onCategoryChanged(category),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePinned,
    required this.onOpenAttachment,
  });

  final _BuildingNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePinned;
  final VoidCallback? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CategoryPill(category: note.category),
                  if (note.pinned) const _PinnedPill(),
                ],
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      note.displayDate,
                      style: const TextStyle(
                        color: AqsColors.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: note.pinned ? 'Unpin note' : 'Pin note',
                    child: IconButton(
                      onPressed: onTogglePinned,
                      icon: Icon(
                        note.pinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit note',
                    child: IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete note',
                    child: IconButton(
                      onPressed: onDelete,
                      color: const Color(0xFFD92D20),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            note.title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (note.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note.body,
              style: const TextStyle(
                color: AqsColors.text,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (note.attachmentUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            _AttachmentLink(
              name:
                  note.attachmentName.isEmpty
                      ? 'Attachment'
                      : note.attachmentName,
              url: note.attachmentUrl,
              onOpen: onOpenAttachment,
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _AuditText(
                icon: Icons.person_outline_rounded,
                text: 'Created by ${note.createdByName}',
              ),
              if (note.createdByUid.isNotEmpty)
                _AuditText(
                  icon: Icons.badge_outlined,
                  text: 'UID ${note.createdByUid}',
                ),
              _AuditText(
                icon: Icons.update_rounded,
                text: 'Last edited by ${note.updatedByName}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = switch (category) {
      'Issue' => const Color(0xFFD92D20),
      'Client' => const Color(0xFF7A5AF8),
      'Site' => const Color(0xFF039855),
      'QS' => const Color(0xFFDC6803),
      _ => AqsColors.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PinnedPill extends StatelessWidget {
  const _PinnedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFEC84B)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin_rounded, size: 14, color: Color(0xFFB54708)),
          SizedBox(width: 4),
          Text(
            'Pinned',
            style: TextStyle(
              color: Color(0xFFB54708),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentLink extends StatelessWidget {
  const _AttachmentLink({
    required this.name,
    required this.url,
    required this.onOpen,
  });

  final String name;
  final String url;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AqsColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file_rounded, color: AqsColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new_rounded, color: AqsColors.muted),
          ],
        ),
      ),
    );
  }
}

class _PickedAttachmentPill extends StatelessWidget {
  const _PickedAttachmentPill({
    required this.fileName,
    required this.onClear,
  });

  final String fileName;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFB2CCFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            size: 16,
            color: AqsColors.primary,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AqsColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AqsColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditText extends StatelessWidget {
  const _AuditText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AqsColors.muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: AqsColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _NotesEmpty extends StatelessWidget {
  const _NotesEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.notes_outlined,
      title: 'No notes yet',
      subtitle: 'Add comments, reminders, issues, or attachment links for this building.',
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create first note'),
      ),
    );
  }
}

class _NotesNoResults extends StatelessWidget {
  const _NotesNoResults();

  @override
  Widget build(BuildContext context) {
    return const _CenteredState(
      icon: Icons.search_off_rounded,
      title: 'No matching notes',
      subtitle: 'Try another search term or category.',
    );
  }
}

class _NotesLoading extends StatelessWidget {
  const _NotesLoading();

  @override
  Widget build(BuildContext context) {
    return const _CenteredState(
      icon: Icons.sync_rounded,
      title: 'Loading notes',
      subtitle: 'Fetching building notes.',
      action: Padding(
        padding: EdgeInsets.only(top: 6),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _NotesFailure extends StatelessWidget {
  const _NotesFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.error_outline_rounded,
      title: 'Notes unavailable',
      subtitle: message,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AqsColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AqsColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AqsColors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AqsColors.muted,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class _BuildingNote {
  const _BuildingNote({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.pinned,
    required this.attachmentName,
    required this.attachmentUrl,
    required this.attachmentPath,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByUid,
    required this.createdByName,
    required this.updatedByName,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final bool pinned;
  final String attachmentName;
  final String attachmentUrl;
  final String attachmentPath;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final String createdByUid;
  final String createdByName;
  final String updatedByName;

  factory _BuildingNote.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return _BuildingNote(
      id: doc.id,
      title: _text(data['title'], fallback: 'Untitled note'),
      body: _text(data['body']),
      category: _text(data['category'], fallback: 'General'),
      pinned: data['pinned'] == true,
      attachmentName: _text(data['attachmentName']),
      attachmentUrl: _text(data['attachmentUrl']),
      attachmentPath: _text(data['attachmentPath']),
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      createdByUid: _text(data['createdByUid']),
      createdByName: _text(data['createdByName'], fallback: 'Unknown user'),
      updatedByName: _text(data['updatedByName'], fallback: 'Unknown user'),
    );
  }

  DateTime get sortDate =>
      updatedAt?.toDate() ??
      createdAt?.toDate() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String get displayDate {
    final date = updatedAt?.toDate() ?? createdAt?.toDate();
    if (date == null) return 'Just now';
    return DateFormat('dd MMM yyyy, HH:mm').format(date);
  }
}

class _NoteEditorResult {
  const _NoteEditorResult({
    required this.title,
    required this.body,
    required this.category,
    required this.pinned,
    required this.attachmentName,
    required this.attachmentUrl,
    required this.attachmentPath,
    required this.pickedAttachment,
  });

  final String title;
  final String body;
  final String category;
  final bool pinned;
  final String attachmentName;
  final String attachmentUrl;
  final String attachmentPath;
  final _PickedAttachment? pickedAttachment;
}

class _PickedAttachment {
  const _PickedAttachment({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

class _StoredAttachment {
  const _StoredAttachment({
    required this.name,
    required this.url,
    required this.path,
  });

  final String name;
  final String url;
  final String path;
}

String _text(Object? value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}
