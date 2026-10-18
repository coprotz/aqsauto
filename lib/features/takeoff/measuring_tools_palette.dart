import 'package:flutter/material.dart';
import 'package:aqs/features/utils/enum.dart';

class MeasurementToolDefinition {
  const MeasurementToolDefinition({
    required this.measureType,
    required this.label,
    required this.icon,
    required this.group,
    this.unit,
  });

  final String measureType;
  final String label;
  final IconData icon;
  final String group;
  final String? unit;
}

class MeasuringToolsPalette extends StatefulWidget {
  const MeasuringToolsPalette({
    super.key,
    required this.activeMeasureType,
    required this.activeLabel,
    required this.onSelected,
    required this.onConfigure,
    required this.mode,
    required this.currentColor,
    required this.strokeWidth,
    required this.onPan,
    required this.onCalibrate,
    required this.onEdit,
    required this.onUndo,
    required this.onRedo,
    required this.onRefresh,
    required this.onColor,
    required this.onThickness,
    required this.onZoomIn,
    required this.onZoomOut,
    this.compact = false,
  });

  final String? activeMeasureType;
  final String? activeLabel;
  final ValueChanged<MeasurementToolDefinition> onSelected;
  final VoidCallback onConfigure;
  final TakeoffMode mode;
  final Color currentColor;
  final double strokeWidth;
  final VoidCallback onPan;
  final VoidCallback onCalibrate;
  final VoidCallback onEdit;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onRefresh;
  final VoidCallback onColor;
  final VoidCallback onThickness;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool compact;

  @override
  State<MeasuringToolsPalette> createState() => _MeasuringToolsPaletteState();
}

class _MeasuringToolsPaletteState extends State<MeasuringToolsPalette> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const _tools = <MeasurementToolDefinition>[
    MeasurementToolDefinition(
      measureType: 'length',
      label: 'Length',
      icon: Icons.straighten,
      group: 'Basic',
      unit: 'm',
    ),
    MeasurementToolDefinition(
      measureType: 'area',
      label: 'Area',
      icon: Icons.crop_square,
      group: 'Basic',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'volume',
      label: 'Volume',
      icon: Icons.view_in_ar,
      group: 'Basic',
      unit: 'm3',
    ),
    MeasurementToolDefinition(
      measureType: 'count',
      label: 'Count',
      icon: Icons.fact_check_outlined,
      group: 'Basic',
      unit: 'nr',
    ),
    MeasurementToolDefinition(
      measureType: 'walling',
      label: 'Walling',
      icon: Icons.view_week_outlined,
      group: 'Structure',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeBeam',
      label: 'Beam',
      icon: Icons.horizontal_rule,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeSlab',
      label: 'Slab',
      icon: Icons.grid_on,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'slabRebarAi',
      label: 'Slab Rebar',
      icon: Icons.auto_awesome,
      group: 'Structure',
      unit: 'kg',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeColumn',
      label: 'Column',
      icon: Icons.crop_portrait,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeFooting',
      label: 'Footing',
      icon: Icons.foundation,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'plinth',
      label: 'Plinth',
      icon: Icons.layers_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'groundPreparation',
      label: 'Ground prep',
      icon: Icons.landscape_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeStair',
      label: 'Stairs',
      icon: Icons.stairs,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'liftShaft',
      label: 'Lift shaft',
      icon: Icons.elevator_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'undergroundStructure',
      label: 'Underground structures',
      icon: Icons.inventory_2_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeRamp',
      label: 'Ramp',
      icon: Icons.trending_up,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeRetainingWall',
      label: 'Retaining wall',
      icon: Icons.signpost_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'concreteBenchWorktop',
      label: 'Bench & Worktop',
      icon: Icons.countertops_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'foundationWall',
      label: 'Foundation wall',
      icon: Icons.account_balance_outlined,
      group: 'Structure',
    ),
    MeasurementToolDefinition(
      measureType: 'roofsheeting',
      label: 'Roof covering',
      icon: Icons.roofing,
      group: 'Roof',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'compositeRoofing',
      label: 'Timber roof structure',
      icon: Icons.carpenter,
      group: 'Roof',
    ),
    MeasurementToolDefinition(
      measureType: 'trussTemplate',
      label: 'Steel roof structure',
      icon: Icons.change_history,
      group: 'Roof',
    ),
    MeasurementToolDefinition(
      measureType: 'tiling',
      label: 'Tiles',
      icon: Icons.dashboard_outlined,
      group: 'Finishes',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'ceiling',
      label: 'Ceiling',
      icon: Icons.border_top,
      group: 'Finishes',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'door',
      label: 'Door',
      icon: Icons.door_front_door_outlined,
      group: 'Openings',
      unit: 'nr',
    ),
    MeasurementToolDefinition(
      measureType: 'window',
      label: 'Window',
      icon: Icons.window_outlined,
      group: 'Openings',
      unit: 'nr',
    ),
    MeasurementToolDefinition(
      measureType: 'roadProfile',
      label: 'Road profile',
      icon: Icons.route_outlined,
      group: 'Civil',
      unit: 'm',
    ),
    MeasurementToolDefinition(
      measureType: 'civilWork',
      label: 'Kerbstone',
      icon: Icons.add_road,
      group: 'Civil',
      unit: 'm',
    ),
    MeasurementToolDefinition(
      measureType: 'drainage',
      label: 'Drainage',
      icon: Icons.water,
      group: 'Civil',
      unit: 'm',
    ),
    MeasurementToolDefinition(
      measureType: 'pavement',
      label: 'Pavement area',
      icon: Icons.texture,
      group: 'Civil',
      unit: 'm2',
    ),
    MeasurementToolDefinition(
      measureType: 'pipe',
      label: 'Pipe / service',
      icon: Icons.route,
      group: 'Services',
      unit: 'm',
    ),
  ];

  Future<void> _handleToolTap(MeasurementToolDefinition tool) async {
    // All measuring tools are available from every subscription plan.
    widget.onSelected(tool);
  }

  String _howToUse(MeasurementToolDefinition tool) {
    final type = tool.measureType.toLowerCase();
    final label = tool.label.toLowerCase();

    if (type == 'length') return 'Click along the required run; finish the chain to save the measured length.';
    if (type == 'area') return 'Trace the boundary as a polygon and close it to calculate the area.';
    if (type == 'volume') return 'Measure the footprint, then enter the required depth or height to calculate volume.';
    if (type == 'count') return 'Click each repeated item on the drawing; AQS totals the number of points.';
    if (type == 'walling') return 'Measure the wall run, enter height/thickness, add simple opening deductions, then select wall finishes and BOQ items.';
    if (type == 'compositebeam') return 'Measure the beam run, then enter the beam section and reinforcement/formwork details.';
    if (type == 'compositeslab') return 'Trace the slab area, then enter thickness and applicable concrete/formwork details.';
    if (type == 'slabrebarai') return 'Measure one representative bar (continuous for bends or segments), enter mark/size/quantity/spacing, then add more bars before commit.';
    if (type == 'compositecolumn') return 'Select/count columns and enter the section, height, concrete, formwork and reinforcement details.';
    if (type == 'compositefooting') return 'Measure/select the footing and enter dimensions, excavation, concrete, formwork and reinforcement details.';
    if (type == 'plinth') return 'Measure the plinth geometry and select the required plinth treatments/finishes and BOQ outputs.';
    if (type == 'groundpreparation') return 'Trace the ground area and enter preparation layers or treatment depths required by the BOQ.';
    if (type == 'compositestair') return 'Measure the stair geometry, then enter flight/landing dimensions so AQS derives concrete, formwork and finishes.';
    if (type == 'liftshaft') return 'Measure the lift pit/shaft geometry and enter pit, wall and level information for substructure/superstructure quantities.';
    if (type == 'undergroundstructure') return 'Draw the outside wall rectangle, choose a tank/chamber preset, enter depth and construction details, then map excavation, concrete, formwork, reinforcement, waterproofing and backfill to BOQ items.';
    if (type == 'compositeramp') return 'Measure the ramp footprint/run and enter levels, thickness and finishes to calculate quantities.';
    if (type == 'compositeretainingwall') return 'Measure the retaining-wall run and enter wall/base dimensions, excavation, concrete and reinforcement.';
    if (type == 'foundationwall') return 'Measure the foundation-wall segment, enter trench/strip/wall dimensions, map BOQs, then save.';
    if (type == 'roofsheeting') return 'Trace the roof plane/covering area and enter roof-covering details for area-based take-off.';
    if (type == 'compositeroofing') return 'Measure timber roof members/runs and enter member sizes; repeat members before final save.';
    if (type == 'trusstemplate') return 'Measure the steel truss/member geometry, choose member type and size, then calculate steel weight.';
    if (type == 'tiling') return 'Trace the tiled area, add deductions where needed, then select the tile BOQ item.';
    if (type == 'ceiling') return 'Trace the ceiling area and select the ceiling type/BOQ; deduct openings where applicable.';
    if (type == 'door') return 'Place/select doors and enter the door size, type and component BOQ details.';
    if (type == 'window') return 'Place/select windows and enter the window size, type and component BOQ details.';
    if (type == 'roadprofile') return 'Measure the road alignment and enter road-earthwork width/depth or fill information; pavement and kerbs use their own tools.';
    if (type == 'civilwork' || label.contains('kerb')) return 'Trace each kerb/chute/edge-beam chain, assign its BOQ, add more chains, then commit the group.';
    if (type == 'drainage') return 'Measure the drain centreline, choose the drain/culvert profile, adjust geometry/depths, map calculated outputs, then commit.';
    if (type == 'pavement') return 'Trace one or more pavement zones, add deduction polygons if needed, choose pavement type/layers and map BOQ outputs.';
    if (type == 'pipe') return 'Measure the pipe/service route as a chain, then enter size/type and select the corresponding BOQ.';

    return 'Select the tool, measure the relevant geometry on the drawing, complete its details, then save the BOQ quantities.';
  }

  @override
  Widget build(BuildContext context) {
    final active = (widget.activeMeasureType ?? '').trim().toLowerCase();
    final activeLabel = (widget.activeLabel ?? '').trim().toLowerCase();
    final groups = <String, List<MeasurementToolDefinition>>{};
    for (final tool in _tools) {
      (groups[tool.group] ??= []).add(tool);
    }

    if (widget.compact) {
      return Material(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.architecture_rounded,
                      color: Color(0xFF155EEF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Measurement tools',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          widget.activeLabel?.trim().isNotEmpty == true
                              ? 'Active: ${widget.activeLabel}'
                              : 'Choose a tool for the drawing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configure active tool',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: widget.onConfigure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 2.7,
                            ),
                        itemCount: entry.value.length,
                        itemBuilder: (context, index) {
                          final tool = entry.value[index];
                          final selected =
                              active == tool.measureType.toLowerCase() &&
                              (active != 'walling' ||
                                  activeLabel == tool.label.toLowerCase());
                          return Tooltip(
                            message: '${tool.label}\nHow to use: ${_howToUse(tool)}',
                            waitDuration: const Duration(milliseconds: 350),
                            showDuration: const Duration(seconds: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _handleToolTap(tool),
                              child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    selected
                                        ? const Color(0xFFEFF4FF)
                                        : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      selected
                                          ? const Color(0xFF155EEF)
                                          : const Color(0xFFD0D5DD),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    tool.icon,
                                    size: 22,
                                    color:
                                        selected
                                            ? const Color(0xFF155EEF)
                                            : const Color(0xFF344054),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      tool.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: Material(
        elevation: 0,
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 118,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF111827),
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                child: Column(
                  children: [
                    const Icon(
                      Icons.architecture_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Take-off',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    IconButton(
                      tooltip: 'Configure active tool',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.settings,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: widget.onConfigure,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  thickness: 5,
                  radius: const Radius.circular(999),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 10, 11, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                          child: Column(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: widget.currentColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.activeLabel?.trim().isNotEmpty == true
                                    ? widget.activeLabel!
                                    : 'Select tool',
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 10, 2, 5),
                            child: Text(
                              entry.key.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                          Column(
                            children:
                                entry.value.map((tool) {
                                  final selected =
                                      active ==
                                          tool.measureType.toLowerCase() &&
                                      (active != 'walling' ||
                                          activeLabel ==
                                              tool.label.toLowerCase());
                                  return Tooltip(
                                    message: '${tool.label}\nHow to use: ${_howToUse(tool)}',
                                    waitDuration: const Duration(milliseconds: 350),
                                    showDuration: const Duration(seconds: 10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _handleToolTap(tool),
                                      child: Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          bottom: 7,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              selected
                                                  ? Colors.blue.shade50
                                                  : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color:
                                                selected
                                                    ? Colors.blue
                                                    : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                                tool.icon,
                                                size: 20,
                                                color:
                                                    selected
                                                        ? Colors.blue
                                                        : Colors.black87,
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              tool.label,
                                              maxLines: 2,
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    selected
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
