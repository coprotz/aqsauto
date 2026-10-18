import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/boq/views/boq_tab_getx.dart';
import 'package:aqs/features/dashboards/views/building_measurements_tab.dart';
import 'package:aqs/features/dashboards/views/building_notes_tab.dart';
import 'package:aqs/features/dashboards/views/drawing_tab.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProjectBuildingDetailsPage extends StatefulWidget {
  final String projectId;
  final String projectName;
  final String buildingId;
  final String buildingName;
  final String buildingCode;
  final int initialTabIndex;

  const ProjectBuildingDetailsPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.buildingId,
    required this.buildingName,
    required this.buildingCode,
    this.initialTabIndex = 0,
  });

  @override
  State<ProjectBuildingDetailsPage> createState() =>
      _ProjectBuildingDetailsPageState();
}

class _ProjectBuildingDetailsPageState extends State<ProjectBuildingDetailsPage>
    with SingleTickerProviderStateMixin {
  String? _activeDrawingId;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _tabController.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _openProject() {
    Get.toNamed(
      AppRoutes.projectBuildingsPath(widget.projectId, widget.projectName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 720;
    final veryCompact = viewportWidth < 380;
    final buildingLabel =
        widget.buildingCode.trim().isEmpty
            ? widget.buildingName
            : '${widget.buildingName} - ${widget.buildingCode}';

    return Scaffold(
      backgroundColor: AqsColors.canvas,
      body: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 20,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: const BorderSide(color: AqsColors.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to project buildings',
                  onPressed: _openProject,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                SizedBox(width: compact ? 2 : 4),
                AqsBrand(compact: true, markSize: compact ? 30 : 34),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        buildingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 16 : 17,
                          color: const Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _ProjectLinkBreadcrumb(
                        projectName: widget.projectName,
                        buildingName: widget.buildingName,
                        compact: compact,
                        onTap: _openProject,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: compact ? 8 : 12),
                if (veryCompact)
                  IconButton.filled(
                    tooltip:
                        _tabController.index == 1 ? 'Drawings' : 'Open BOQ',
                    onPressed:
                        () => _tabController.animateTo(
                          _tabController.index == 1 ? 0 : 1,
                        ),
                    icon: Icon(
                      _tabController.index == 1
                          ? Icons.architecture_outlined
                          : Icons.receipt_long_outlined,
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed:
                        () => _tabController.animateTo(
                          _tabController.index == 1 ? 0 : 1,
                        ),
                    icon: Icon(
                      _tabController.index == 1
                          ? Icons.architecture_outlined
                          : Icons.receipt_long_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _tabController.index == 1 ? 'Drawings' : 'BOQ',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                DrawingsTabGetX(
                  projectId: widget.projectId,
                  buildingId: widget.buildingId,
                  projectName: widget.projectName,
                  buildingName: widget.buildingName,
                  activeDrawingId: _activeDrawingId,
                  onDrawingSelected:
                      (drawingId) =>
                          setState(() => _activeDrawingId = drawingId),
                ),
                BoqTabGetX(
                  projectId: widget.projectId,
                  projectName: widget.projectName,
                  buildingId: widget.buildingId,
                  imageUrl: '',
                  drawingTitle: '',
                  drawingId: 'building-${widget.buildingId}',
                  buildingName: widget.buildingName,
                ),
                BuildingMeasurementsTab(
                  projectId: widget.projectId,
                  buildingId: widget.buildingId,
                  activeDrawingId: _activeDrawingId,
                  onBackToDrawings: () => _tabController.animateTo(0),
                  onDrawingSelected:
                      (drawingId) =>
                          setState(() => _activeDrawingId = drawingId),
                ),
                BuildingNotesTab(
                  projectId: widget.projectId,
                  buildingId: widget.buildingId,
                  buildingName: widget.buildingName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectLinkBreadcrumb extends StatelessWidget {
  const _ProjectLinkBreadcrumb({
    required this.projectName,
    required this.buildingName,
    required this.compact,
    required this.onTap,
  });

  final String projectName;
  final String buildingName;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: AqsColors.primary,
      fontWeight: FontWeight.w700,
      fontSize: 12,
      decoration: TextDecoration.underline,
      decorationColor: AqsColors.primary,
    );
    const mutedStyle = TextStyle(
      color: Color(0xFF667085),
      fontWeight: FontWeight.w500,
      fontSize: 12,
    );

    return Row(
      children: [
        Flexible(
          child: Tooltip(
            message: 'Open project',
            child: InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: linkStyle,
                ),
              ),
            ),
          ),
        ),
        if (!compact) ...[
          const Text(' / ', style: mutedStyle),
          Flexible(
            child: Text(
              buildingName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mutedStyle,
            ),
          ),
        ],
      ],
    );
  }
}
