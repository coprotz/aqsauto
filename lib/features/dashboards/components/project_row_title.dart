import 'package:aqs/features/dashboards/components/menu_row.dart';
import 'package:aqs/features/dashboards/components/stage_pill.dart';
import 'package:aqs/features/dashboards/models/project_row_fs.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProjectRowTile extends StatelessWidget {
  final ProjectRowFs row;

  /// Must return keys: buildings, drawings, measurements, boqItems
  final Future<Map<String, int>> Function(String projectId) getCounts;

  final Future<void> Function(ProjectRowFs row, ProjectStage newStage)
  onChangeStage;

  /// Keep actions as before
  final void Function(ProjectRowFs row, String action) onRowAction;

  const ProjectRowTile({
    required this.row,
    required this.getCounts,
    required this.onChangeStage,
    required this.onRowAction,
  });

  @override
  Widget build(BuildContext context) {
    final created = row.createdAt?.toDate();
    final createdTxt =
        created == null ? '-' : DateFormat('dd MMM yyyy').format(created);

    final currencyTxt = row.currency.trim().isEmpty ? '-' : row.currency.trim();
    final clientTxt =
        row.clientName.trim().isEmpty ? '-' : row.clientName.trim();

    return FutureBuilder<Map<String, int>>(
      future: getCounts(row.id),
      builder: (context, snap) {
        String value(String key) {
          if (snap.connectionState == ConnectionState.waiting) {
            return 'Loading...';
          }
          if (snap.hasError) return 'Unavailable';
          return snap.data?[key]?.toString() ?? '0';
        }

        Widget countCell(String key) {
          final loading = snap.connectionState == ConnectionState.waiting;
          if (loading) {
            return const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Loading',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }

          return Text(
            value(key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF344054),
              fontWeight: FontWeight.w500,
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.black.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              // Project
              Expanded(
                flex: 4,
                child: Text(
                  row.name.isEmpty ? '(No name)' : row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),

              // Client
              Expanded(
                flex: 3,
                child: Text(
                  clientTxt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Stage
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    StagePill(stage: row.stage),
                    const SizedBox(width: 6),
                    PopupMenuButton<ProjectStage>(
                      tooltip: 'Change stage',
                      onSelected: (s) => onChangeStage(row, s),
                      itemBuilder:
                          (_) =>
                              ProjectStage.values
                                  .map(
                                    (s) => PopupMenuItem<ProjectStage>(
                                      value: s,
                                      child: Text(s.label),
                                    ),
                                  )
                                  .toList(),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Currency
              Expanded(flex: 2, child: Text(currencyTxt)),

              // Buildings / Drawings / Measures / BOQ Items (aggregated across buildings)
              Expanded(flex: 2, child: countCell('buildings')),
              Expanded(flex: 2, child: countCell('drawings')),
              Expanded(flex: 2, child: countCell('measurements')),
              Expanded(flex: 2, child: countCell('boqItems')),

              // Created
              Expanded(flex: 2, child: Text(createdTxt)),

              // ✅ Actions (KEPT AS BEFORE)
              SizedBox(
                width: 40,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (v2) => onRowAction(row, v2),
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem(
                            value: 'Open Project',
                            child: MenuRow(
                              icon: Icons.open_in_new_rounded,
                              text: 'Open Project',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'Start Construction',
                            child: MenuRow(
                              icon: Icons.build_circle_rounded,
                              text: 'Start Construction',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'Create IPC',
                            child: MenuRow(
                              icon: Icons.payments_rounded,
                              text:
                                  row.ipcCount > 0
                                      ? 'Create next IPC (now #${row.ipcCount + 1})'
                                      : 'Create IPC',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'Verify BOQ',
                            child: MenuRow(
                              icon: Icons.verified_rounded,
                              text: 'BOQ Verification',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'Back to Tender',
                            child: MenuRow(
                              icon: Icons.restart_alt_rounded,
                              text: 'Back to Tender',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'Rename',
                            child: MenuRow(
                              icon: Icons.edit_rounded,
                              text: 'Rename',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'Archive',
                            child: MenuRow(
                              icon: Icons.archive_outlined,
                              text: 'Archive',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'Duplicate',
                            child: MenuRow(
                              icon: Icons.copy_rounded,
                              text: 'Duplicate',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'Delete',
                            child: MenuRow(
                              icon: Icons.delete_outline_rounded,
                              text: 'Delete',
                              danger: true,
                            ),
                          ),
                        ],
                    child: Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.black.withOpacity(0.65),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
