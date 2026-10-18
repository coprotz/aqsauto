import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/boq/controllers/boq_import_excel-controller.dart';
import 'package:aqs/features/dashboards/controllers/project_buildings_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BoqImportExcelPageGetX extends GetView<BoqImportExcelController> {
  const BoqImportExcelPageGetX({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 920;

    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        title: const Text('Import BOQ from Excel'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AqsColors.border),
        ),
      ),
      body: Obx(() {
        final projectName = controller.projectName.value.trim();
        final buildingName = controller.structureName.value.trim();
        final projectId = controller.projectId;
        final buildingId = controller.buildingId;
        final importing = controller.importing.value;
        final status = controller.status.value.trim();
        final imported = controller.lastImported.value;

        final importPanel = _ImportPanel(
          projectName: projectName.isEmpty ? 'Project' : projectName,
          buildingName: buildingName.isEmpty ? 'Building' : buildingName,
          clearBeforeImport: controller.clearBeforeImport.value,
          hierarchyMode: controller.importHierarchyMode.value,
          importing: importing,
          buildingId: buildingId,
          projectId: projectId,
          status: status,
          importedRows: imported,
          onClearChanged:
              importing
                  ? null
                  : (value) =>
                      controller.clearBeforeImport.value = value ?? true,
          onHierarchyModeChanged:
              importing
                  ? null
                  : (value) {
                    if (value != null) {
                      controller.importHierarchyMode.value = value;
                    }
                  },
          onImport: importing ? null : controller.pickAndImportExcel,
        );

        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PageIntro(),
                  const SizedBox(height: 16),
                  if (compact)
                    Column(
                      children: [
                        importPanel,
                        const SizedBox(height: 16),
                        const _WorkbookRulesCard(),
                        const SizedBox(height: 16),
                        const _ExampleSheetCard(),
                        const SizedBox(height: 16),
                        const _ColumnGuideCard(),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: importPanel),
                            const SizedBox(width: 16),
                            const Expanded(
                              flex: 6,
                              child: _WorkbookRulesCard(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const _ExampleSheetCard(),
                        const SizedBox(height: 16),
                        const _ColumnGuideCard(),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: Icons.upload_file_rounded),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Single-sheet BOQ import',
                  style: TextStyle(
                    color: AqsColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Attach a building or civil-works BOQ in one worksheet. AQS can detect BILL or SERIES headings automatically and preserve headings and BOQ items in order.',
                  style: TextStyle(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.projectName,
    required this.buildingName,
    required this.clearBeforeImport,
    required this.hierarchyMode,
    required this.importing,
    required this.status,
    required this.importedRows,
    required this.onClearChanged,
    required this.onHierarchyModeChanged,
    required this.onImport,
    required this.projectId,
    required this.buildingId,
  });

  final String projectName;
  final String buildingName;
  final String projectId;
  final String buildingId;
  final bool clearBeforeImport;
  final String hierarchyMode;
  final bool importing;
  final String status;
  final int importedRows;
  final ValueChanged<bool?>? onClearChanged;
  final ValueChanged<String?>? onHierarchyModeChanged;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Import target',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _ContextRow(
            icon: Icons.folder_open_rounded,
            label: 'Project',
            value: projectName,
          ),
          const SizedBox(height: 10),
          _ContextRow(
            icon: Icons.domain_outlined,
            label: 'Building',
            value: buildingName,
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: hierarchyMode,
            onChanged: onHierarchyModeChanged,
            decoration: const InputDecoration(
              labelText: 'BOQ format',
              border: OutlineInputBorder(),
              helperText: 'Automatic detects SERIES headings for civil works.',
            ),
            items: const [
              DropdownMenuItem(
                value: 'auto',
                child: Text('Automatic detection'),
              ),
              DropdownMenuItem(
                value: 'building',
                child: Text('Building works — BILL'),
              ),
              DropdownMenuItem(
                value: 'civil',
                child: Text('Civil works — SERIES'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: clearBeforeImport,
            onChanged: onClearChanged,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Clear existing BOQ items before import',
              style: TextStyle(
                color: AqsColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: const Text(
              'Use this when the Excel file should replace the current building BOQ.',
              style: TextStyle(color: AqsColors.muted),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: importing ? null : onImport,
              icon:
                  importing
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.upload_file_rounded),
              label: Text(
                importing ? 'Importing Excel...' : 'Pick Excel & import',
              ),
            ),
          ),
          const SizedBox(height: 14),
          _StatusBanner(
            status: status,
            importedRows: importedRows,
            onBackToBoq:
                importedRows > 0
                    ? () async {
                      final projectDataController =
                          Get.find<ProjectBuildingsController>();

                      await projectDataController.loadBoq(
                        projectId,
                        buildingId,
                        forceRefresh: true,
                      );

                      Get.back();
                    }
                    : null,
          ),
        ],
      ),
    );
  }
}

class _WorkbookRulesCard extends StatelessWidget {
  const _WorkbookRulesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workbook rules',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 14),
          _RuleRow(
            icon: Icons.filter_1_rounded,
            title: 'Use a recognised header row',
            text:
                'AQS checks the workbook for the first worksheet containing recognised BOQ Code and Description headers.',
          ),
          SizedBox(height: 12),
          _RuleRow(
            icon: Icons.view_agenda_outlined,
            title: 'Keep all BOQ sections in one sheet',
            text:
                'Building BOQs use BILL headings. Civil-works BOQs use SERIES headings such as SERIES 2000 or SERIES 3000.',
          ),
          SizedBox(height: 12),
          _RuleRow(
            icon: Icons.table_rows_outlined,
            title: 'Start with a header row',
            text:
                'The header can be in any of the first 10 rows. AQS needs BOQ Code and Description, with Unit and Rate optional.',
          ),
        ],
      ),
    );
  }
}

class _ExampleSheetCard extends StatelessWidget {
  const _ExampleSheetCard();

  static const rows = [
    _ExampleRow('', 'BILL NO. 1 - PRELIMINARIES', '', ''),
    _ExampleRow('1.1', 'MANAGEMENT & SUPERVISION', '', ''),
    _ExampleRow('A', 'Project Manager / Site Agent', 'Month', '1500'),
    _ExampleRow('B', 'Site Engineer / Setting-out Engineer', 'Month', ''),
    _ExampleRow('', 'BILL NO. 2 - DEMOLITION AND ALTERATIONS', '', ''),
    _ExampleRow('2.1', 'REMOVALS', '', ''),
    _ExampleRow('(i)', 'Existing masonry openings', '', ''),
    _ExampleRow('A', 'Remove existing door and frame', 'No.', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Example Excel sheet',
            style: TextStyle(
              color: AqsColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Building BOQs use BILL rows as shown. Civil BOQs can use SERIES rows in the same code and description columns.',
            style: TextStyle(
              color: AqsColors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AqsColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactTable = constraints.maxWidth < 680;
                  final codeWidth = compactTable ? 86.0 : 120.0;
                  final unitWidth = compactTable ? 76.0 : 120.0;
                  final rateWidth = compactTable ? 76.0 : 110.0;

                  return Table(
                    columnWidths: {
                      0: FixedColumnWidth(codeWidth),
                      1: const FlexColumnWidth(),
                      2: FixedColumnWidth(unitWidth),
                      3: FixedColumnWidth(rateWidth),
                    },
                    border: TableBorder(
                      horizontalInside: const BorderSide(
                        color: AqsColors.border,
                      ),
                    ),
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: AqsColors.primaryDark),
                        children: [
                          _ExampleCell('BOQ Code', header: true),
                          _ExampleCell('Description', header: true),
                          _ExampleCell('Unit', header: true),
                          _ExampleCell('Rate', header: true),
                        ],
                      ),
                      ...rows.map(
                        (row) => TableRow(
                          children: [
                            _ExampleCell(row.code),
                            _ExampleCell(
                              row.description,
                              strong: row.unit.isEmpty,
                            ),
                            _ExampleCell(row.unit),
                            _ExampleCell(row.rate),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleCell extends StatelessWidget {
  const _ExampleCell(this.text, {this.header = false, this.strong = false});

  final String text;
  final bool header;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: header ? 48 : 46),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        maxLines: header ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: header ? Colors.white : AqsColors.ink,
          fontWeight: header || strong ? FontWeight.w900 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _ColumnGuideCard extends StatelessWidget {
  const _ColumnGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AqsColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1E0FF)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accepted column names',
            style: TextStyle(
              color: AqsColors.primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          _AliasRow(label: 'BOQ Code', aliases: 'Item, BOQ, Code, Item Code'),
          _AliasRow(label: 'Description', aliases: 'Desc, Item Description'),
          _AliasRow(label: 'Unit', aliases: 'UOM'),
          _AliasRow(label: 'Rate', aliases: 'Unit Rate, Unit Price, Price'),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.status,
    required this.importedRows,
    this.onBackToBoq,
  });

  final String status;
  final int importedRows;
  final Future<void> Function()? onBackToBoq;

  @override
  Widget build(BuildContext context) {
    final hasError = status.toLowerCase().startsWith('error');

    final hasStatus = status.isNotEmpty;

    final success = importedRows > 0 && !hasError;

    final icon =
        hasError
            ? Icons.error_outline_rounded
            : success
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded;

    final color =
        hasError
            ? const Color(0xFFB42318)
            : success
            ? AqsColors.success
            : AqsColors.primary;

    final background =
        hasError
            ? const Color(0xFFFFF1F3)
            : success
            ? AqsColors.successSoft
            : AqsColors.primarySoft;

    final message =
        hasStatus
            ? status
            : 'Ready for .xlsx or .xls files. Automatic mode recognises BILL and SERIES sections.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),

          if (success && onBackToBoq != null) ...[
            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  await onBackToBoq!();
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to BOQ'),
                style: FilledButton.styleFrom(
                  backgroundColor: AqsColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// class _StatusBanner extends StatelessWidget {
//   const _StatusBanner({
//     required this.status,
//     required this.importedRows,
//   });

//   final String status;
//   final int importedRows;

//   @override
//   Widget build(BuildContext context) {
//     final hasError = status.toLowerCase().startsWith('error');
//     final hasStatus = status.isNotEmpty;
//     final icon =
//         hasError
//             ? Icons.error_outline_rounded
//             : importedRows > 0
//             ? Icons.check_circle_outline_rounded
//             : Icons.info_outline_rounded;
//     final color =
//         hasError
//             ? const Color(0xFFB42318)
//             : importedRows > 0
//             ? AqsColors.success
//             : AqsColors.primary;
//     final background =
//         hasError
//             ? const Color(0xFFFFF1F3)
//             : importedRows > 0
//             ? AqsColors.successSoft
//             : AqsColors.primarySoft;
//     final message =
//         hasStatus
//             ? status
//             : 'Ready for .xlsx or .xls files. Keep the BOQ in the first sheet.';

//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: background,
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: color.withOpacity(0.22)),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Icon(icon, color: color, size: 20),
//           const SizedBox(width: 10),
//           Expanded(
//             child: Text(
//               message,
//               style: TextStyle(
//                 color: color,
//                 fontWeight: FontWeight.w700,
//                 height: 1.35,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AqsColors.primary, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: const TextStyle(
              color: AqsColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AqsColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AqsColors.primarySoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AqsColors.primary, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: const TextStyle(
                  color: AqsColors.muted,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AliasRow extends StatelessWidget {
  const _AliasRow({required this.label, required this.aliases});

  final String label;
  final String aliases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AqsColors.primaryDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              aliases,
              style: const TextStyle(
                color: AqsColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AqsColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _ExampleRow {
  const _ExampleRow(this.code, this.description, this.unit, this.rate);

  final String code;
  final String description;
  final String unit;
  final String rate;
}
