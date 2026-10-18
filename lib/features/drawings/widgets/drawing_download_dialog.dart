import 'package:aqs/features/drawings/models/drawing_row.dart';
import 'package:flutter/material.dart';

class DrawingDownloadDialog extends StatefulWidget {
  const DrawingDownloadDialog({super.key, required this.drawings});

  final List<DrawingRow> drawings;

  @override
  State<DrawingDownloadDialog> createState() =>
      _DrawingDownloadDialogState();
}

class _DrawingDownloadDialogState extends State<DrawingDownloadDialog> {
  final _searchController = TextEditingController();
  late final Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.drawings
        .where((drawing) => drawing.downloadUrl.trim().isNotEmpty)
        .map((drawing) => drawing.id)
        .toSet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DrawingRow> get _visibleDrawings {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.drawings;
    return widget.drawings.where((drawing) {
      return drawing.title.toLowerCase().contains(query) ||
          drawing.sheetNumber.toLowerCase().contains(query);
    }).toList();
  }

  List<DrawingRow> get _selectedDrawings => widget.drawings
      .where((drawing) => _selectedIds.contains(drawing.id))
      .toList();

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(
          widget.drawings
              .where((drawing) => drawing.downloadUrl.trim().isNotEmpty)
              .map((drawing) => drawing.id),
        );
    });
  }

  void _clearAll() => setState(_selectedIds.clear);

  @override
  Widget build(BuildContext context) {
    final visible = _visibleDrawings;
    final selectedCount = _selectedIds.length;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 40,
        vertical: compact ? 16 : 24,
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          const Expanded(child: Text('Download Drawings')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: compact ? double.maxFinite : 650,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.68,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the original drawing files to include in the download.',
                style: TextStyle(color: Color(0xFF667085)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search drawing or sheet number',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                Row(
                  children: [
                    TextButton(
                      onPressed: _selectAll,
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: selectedCount == 0 ? null : _clearAll,
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$selectedCount of ${widget.drawings.length} selected',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                Row(
                  children: [
                    TextButton(
                      onPressed: _selectAll,
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: selectedCount == 0 ? null : _clearAll,
                      child: const Text('Clear all'),
                    ),
                    const Spacer(),
                    Text(
                      '$selectedCount of ${widget.drawings.length} selected',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const Divider(height: 1),
              Flexible(
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text('No drawings match your search.'),
                        ),
                      )
                    : Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final drawing = visible[index];
                            final available =
                                drawing.downloadUrl.trim().isNotEmpty;
                            return CheckboxListTile(
                              value: _selectedIds.contains(drawing.id),
                              onChanged: !available
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedIds.add(drawing.id);
                                        } else {
                                          _selectedIds.remove(drawing.id);
                                        }
                                      });
                                    },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                drawing.title.trim().isEmpty
                                    ? 'Untitled drawing'
                                    : drawing.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                !available
                                    ? 'Original file unavailable'
                                    : drawing.sheetNumber.trim().isEmpty
                                    ? 'PDF drawing'
                                    : 'Sheet ${drawing.sheetNumber}',
                              ),
                              secondary: Icon(
                                available
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.cloud_off_outlined,
                                color: available
                                    ? const Color(0xFFD92D20)
                                    : const Color(0xFF98A2B3),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(_selectedDrawings),
          icon: const Icon(Icons.download_rounded),
          label: Text(
            'Download $selectedCount ${selectedCount == 1 ? 'drawing' : 'drawings'}',
          ),
        ),
      ],
    );
  }
}
