import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/dashboards/components/project_row_title.dart';
import 'package:aqs/features/dashboards/components/table_header.dart';
import 'package:aqs/features/dashboards/models/project_row_fs.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:flutter/material.dart';

class ProjectsTableFs extends StatefulWidget {
  final List<ProjectRowFs> rows;
  final Future<Map<String, int>> Function(String projectId) getCounts;
  final Future<void> Function(ProjectRowFs row, ProjectStage newStage)
  onChangeStage;

  final void Function(ProjectRowFs row, String action) onRowAction;

  const ProjectsTableFs({
    super.key,
    required this.rows,
    required this.getCounts,
    required this.onChangeStage,
    required this.onRowAction,
  });

  @override
  State<ProjectsTableFs> createState() => _ProjectsTableFsState();
}

class _ProjectsTableFsState extends State<ProjectsTableFs> {
  final ScrollController _horizontalCtrl = ScrollController();

  @override
  void dispose() {
    _horizontalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = max(1520.0, constraints.maxWidth);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AqsColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A101828),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ScrollConfiguration(
              behavior: const _ProjectsTableScrollBehavior(),
              child: Scrollbar(
                controller: _horizontalCtrl,
                thumbVisibility: tableWidth > constraints.maxWidth,
                trackVisibility: tableWidth > constraints.maxWidth,
                interactive: true,
                notificationPredicate:
                    (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        const TableHeader(),
                        if (widget.rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 44),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.folder_open_outlined,
                                  size: 34,
                                  color: Color(0xFF98A2B3),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'No projects match this view',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF475467),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final r in widget.rows)
                            ProjectRowTile(
                              row: r,
                              getCounts: widget.getCounts,
                              onChangeStage: widget.onChangeStage,
                              onRowAction: widget.onRowAction,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProjectsTableScrollBehavior extends MaterialScrollBehavior {
  const _ProjectsTableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}
