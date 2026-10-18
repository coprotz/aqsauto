import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/boq/services/boq_import_service.dart';
import 'package:aqs/features/boq2/services/boq_import_service.dart';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class UploadBoqPage extends StatefulWidget {
  const UploadBoqPage({
    super.key,
    required this.projectId,
    required this.facilityId,
  });

  final String projectId;
  final String facilityId;

  @override
  State<UploadBoqPage> createState() => _UploadBoqPageState();
}

class _UploadBoqPageState extends State<UploadBoqPage> {
  bool _loadingFile = false;
  bool _importing = false;

  String? _fileName;

  Excel? _workbook;

  List<String> _sheetNames = const [];

  String? _selectedSheet;

  List<List<String>> _rows = const [];

  int _headerRowIndex = 0;

  int? _itemNoColumn;
  int? _descriptionColumn;
  int? _unitColumn;
  int? _quantityColumn;
  int? _rateColumn;
  int? _amountColumn;

  String _cellText(Data? cell) {
    if (cell == null) {
      return '';
    }

    return cell.value?.toString().trim() ?? '';
  }

  bool _matchesAny(String value, List<String> candidates) {
    final normalized = value.trim().toLowerCase();

    for (final candidate in candidates) {
      if (normalized == candidate.toLowerCase()) {
        return true;
      }
    }

    return false;
  }

  Future<void> _pickExcelFile() async {
    if (_loadingFile) {
      return;
    }

    setState(() {
      _loadingFile = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,

        withData: true,

        type: FileType.custom,

        allowedExtensions: const ['xlsx', 'xls'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;

      final bytes = file.bytes;

      if (bytes == null) {
        throw Exception('The selected Excel file could not be read.');
      }

      final workbook = Excel.decodeBytes(Uint8List.fromList(bytes));

      final sheetNames = workbook.tables.keys.toList();

      if (sheetNames.isEmpty) {
        throw Exception('No worksheets were found in this workbook.');
      }

      setState(() {
        _fileName = file.name;

        _workbook = workbook;

        _sheetNames = sheetNames;

        _selectedSheet = sheetNames.first;
      });

      _loadSelectedSheet();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read BOQ: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingFile = false;
        });
      }
    }
  }

  void _loadSelectedSheet() {
    final workbook = _workbook;

    final sheetName = _selectedSheet;

    if (workbook == null || sheetName == null) {
      return;
    }

    final sheet = workbook.tables[sheetName];

    if (sheet == null) {
      return;
    }

    final rows = <List<String>>[];

    for (final row in sheet.rows) {
      rows.add(row.map((cell) => _cellText(cell)).toList());
    }

    final detectedHeader = _detectHeaderRow(rows);

    setState(() {
      _rows = rows;

      _headerRowIndex = detectedHeader;
    });

    _detectColumns();
  }

  int _detectHeaderRow(List<List<String>> rows) {
    if (rows.isEmpty) {
      return 0;
    }

    final scanCount = rows.length > 25 ? 25 : rows.length;

    var bestRow = 0;
    var bestScore = -1;

    for (var rowIndex = 0; rowIndex < scanCount; rowIndex++) {
      final row = rows[rowIndex];

      var score = 0;

      for (final cell in row) {
        final value = cell.trim().toLowerCase();

        if (_matchesAny(value, const [
          'item',
          'item no',
          'item no.',
          'item number',
          'no',
          'no.',
        ])) {
          score += 1;
        }

        if (_matchesAny(value, const [
          'description',
          'item description',
          'particulars',
          'details',
        ])) {
          score += 3;
        }

        if (_matchesAny(value, const ['unit', 'units'])) {
          score += 2;
        }

        if (_matchesAny(value, const ['quantity', 'qty'])) {
          score += 2;
        }

        if (_matchesAny(value, const ['rate', 'unit rate'])) {
          score += 1;
        }

        if (_matchesAny(value, const ['amount', 'total amount', 'total'])) {
          score += 1;
        }
      }

      if (score > bestScore) {
        bestScore = score;

        bestRow = rowIndex;
      }
    }

    return bestRow;
  }

  void _detectColumns() {
    if (_rows.isEmpty) {
      return;
    }

    final safeHeaderIndex = _headerRowIndex.clamp(0, _rows.length - 1);

    final headers = _rows[safeHeaderIndex];

    int? itemNo;
    int? description;
    int? unit;
    int? quantity;
    int? rate;
    int? amount;

    for (var index = 0; index < headers.length; index++) {
      final header = headers[index].trim().toLowerCase();

      if (itemNo == null &&
          _matchesAny(header, const [
            'item',
            'item no',
            'item no.',
            'item number',
            'no',
            'no.',
          ])) {
        itemNo = index;
      }

      if (description == null &&
          _matchesAny(header, const [
            'description',
            'item description',
            'particulars',
            'details',
          ])) {
        description = index;
      }

      if (unit == null && _matchesAny(header, const ['unit', 'units'])) {
        unit = index;
      }

      if (quantity == null && _matchesAny(header, const ['quantity', 'qty'])) {
        quantity = index;
      }

      if (rate == null && _matchesAny(header, const ['rate', 'unit rate'])) {
        rate = index;
      }

      if (amount == null &&
          _matchesAny(header, const ['amount', 'total amount', 'total'])) {
        amount = index;
      }
    }

    setState(() {
      _itemNoColumn = itemNo;

      _descriptionColumn = description;

      _unitColumn = unit;

      _quantityColumn = quantity;

      _rateColumn = rate;

      _amountColumn = amount;
    });
  }

  int get _columnCount {
    var maximum = 0;

    for (final row in _rows) {
      if (row.length > maximum) {
        maximum = row.length;
      }
    }

    return maximum;
  }

  String _headerName(int index) {
    if (_rows.isEmpty) {
      return 'Column ${index + 1}';
    }

    final safeHeaderIndex = _headerRowIndex.clamp(0, _rows.length - 1);

    final row = _rows[safeHeaderIndex];

    if (index < 0 || index >= row.length) {
      return 'Column ${index + 1}';
    }

    final value = row[index].trim();

    if (value.isEmpty) {
      return 'Column ${index + 1}';
    }

    return value;
  }

  List<DropdownMenuItem<int?>> _columnItems() {
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('Not mapped')),
    ];

    for (var index = 0; index < _columnCount; index++) {
      items.add(
        DropdownMenuItem<int?>(
          value: index,

          child: Text(_headerName(index), overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return items;
  }

  String _valueAt(List<String> row, int? column) {
    if (column == null || column < 0 || column >= row.length) {
      return '';
    }

    return row[column].trim();
  }

  List<List<String>> get _previewRows {
    if (_rows.isEmpty) {
      return const [];
    }

    final start = _headerRowIndex + 1;

    if (start >= _rows.length) {
      return const [];
    }

    final end = (start + 15) > _rows.length ? _rows.length : start + 15;

    return _rows.sublist(start, end);
  }

  int get _dataRowCount {
    if (_rows.isEmpty) {
      return 0;
    }

    var count = 0;

    final start = _headerRowIndex + 1;

    for (var index = start; index < _rows.length; index++) {
      final row = _rows[index];

      final description = _valueAt(row, _descriptionColumn);

      final itemNo = _valueAt(row, _itemNoColumn);

      final unit = _valueAt(row, _unitColumn);

      if (description.isNotEmpty || itemNo.isNotEmpty || unit.isNotEmpty) {
        count++;
      }
    }

    return count;
  }

  bool get _canImport {
    return _workbook != null &&
        _selectedSheet != null &&
        _descriptionColumn != null &&
        !_importing;
  }

  Future<void> _continueImport() async {
    if (!_canImport) {
      return;
    }

    setState(() {
      _importing = true;
    });

    try {
      final usableRows = <Map<String, dynamic>>[];

      final start = _headerRowIndex + 1;

      for (var index = start; index < _rows.length; index++) {
        final row = _rows[index];

        final itemNo = _valueAt(row, _itemNoColumn);

        final description = _valueAt(row, _descriptionColumn);

        final unit = _valueAt(row, _unitColumn);

        final quantity = _valueAt(row, _quantityColumn);

        final rate = _valueAt(row, _rateColumn);

        final amount = _valueAt(row, _amountColumn);

        if (itemNo.isEmpty && description.isEmpty && unit.isEmpty) {
          continue;
        }

        usableRows.add({
          'itemNo': itemNo,

          'description': description,

          'unit': unit,

          'quantity': quantity,

          'rate': rate,

          'amount': amount,
        });
      }

      if (usableRows.isEmpty) {
        throw Exception('No usable BOQ rows were found.');
      }

      final fileName = _fileName ?? 'BOQ.xlsx';

      final templateName = fileName.replaceFirst(
        RegExp(r'\.xlsx?$', caseSensitive: false),
        '',
      );

      final result = await BoqImportService.instance.importBoq(
        projectId: widget.projectId,
        facilityId: widget.facilityId,
        templateName: templateName,
        originalFileName: fileName,
        worksheetName: _selectedSheet ?? '',
        rows: usableRows,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,

        barrierDismissible: false,

        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF039855)),
                SizedBox(width: 10),
                Text('BOQ imported'),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The Excel BOQ has been converted into an AQS measurement template.',
                ),

                const SizedBox(height: 18),

                _ImportResultRow(label: 'Bills', value: '${result.billCount}'),

                const SizedBox(height: 8),

                _ImportResultRow(
                  label: 'BOQ items',
                  value: '${result.itemCount}',
                ),

                const SizedBox(height: 8),

                _ImportResultRow(
                  label: 'Headings',
                  value: '${result.headingCount}',
                ),
              ],
            ),

            actions: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();

                  Navigator.of(context).pop(result);
                },
                icon: const Icon(Icons.table_rows_outlined),
                label: const Text('View BOQ'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('BOQ import failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,

      appBar: AppBar(title: const Text('Import BOQ')),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),

          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),

            children: [
              const Text(
                'Import BOQ from Excel',
                style: TextStyle(
                  color: AqsColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Upload an existing BOQ, map its columns and convert the workbook into an AQS measurement template.',
                style: TextStyle(
                  color: AqsColors.muted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 24),

              _UploadCard(
                fileName: _fileName,

                loading: _loadingFile,

                onPick: _pickExcelFile,
              ),

              if (_workbook != null) ...[
                const SizedBox(height: 20),

                _WorkbookSummaryCard(
                  fileName: _fileName ?? 'BOQ.xlsx',

                  sheetCount: _sheetNames.length,

                  rowCount: _dataRowCount,
                ),

                const SizedBox(height: 20),

                _SectionCard(
                  number: '1',

                  title: 'Select worksheet',

                  subtitle:
                      'Choose the worksheet that contains the BOQ you want to import.',

                  child: DropdownButtonFormField<String>(
                    value: _selectedSheet,

                    isExpanded: true,

                    items:
                        _sheetNames
                            .map(
                              (sheet) => DropdownMenuItem<String>(
                                value: sheet,

                                child: Text(sheet),
                              ),
                            )
                            .toList(),

                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedSheet = value;
                      });

                      _loadSelectedSheet();
                    },

                    decoration: const InputDecoration(
                      labelText: 'Worksheet',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                _ColumnMappingCard(
                  rows: _rows,

                  headerRowIndex: _headerRowIndex,

                  columnItems: _columnItems(),

                  itemNoColumn: _itemNoColumn,

                  descriptionColumn: _descriptionColumn,

                  unitColumn: _unitColumn,

                  quantityColumn: _quantityColumn,

                  rateColumn: _rateColumn,

                  amountColumn: _amountColumn,

                  onHeaderRowChanged: (value) {
                    setState(() {
                      _headerRowIndex = value;
                    });

                    _detectColumns();
                  },

                  onItemNoChanged: (value) {
                    setState(() {
                      _itemNoColumn = value;
                    });
                  },

                  onDescriptionChanged: (value) {
                    setState(() {
                      _descriptionColumn = value;
                    });
                  },

                  onUnitChanged: (value) {
                    setState(() {
                      _unitColumn = value;
                    });
                  },

                  onQuantityChanged: (value) {
                    setState(() {
                      _quantityColumn = value;
                    });
                  },

                  onRateChanged: (value) {
                    setState(() {
                      _rateColumn = value;
                    });
                  },

                  onAmountChanged: (value) {
                    setState(() {
                      _amountColumn = value;
                    });
                  },
                ),

                const SizedBox(height: 20),

                _PreviewCard(
                  rows: _previewRows,

                  itemNoColumn: _itemNoColumn,

                  descriptionColumn: _descriptionColumn,

                  unitColumn: _unitColumn,

                  quantityColumn: _quantityColumn,

                  rateColumn: _rateColumn,

                  amountColumn: _amountColumn,
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(18),

                  decoration: BoxDecoration(
                    color: Colors.white,

                    borderRadius: BorderRadius.circular(20),

                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),

                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ready to create your AQS BOQ',
                              style: TextStyle(
                                color: AqsColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),

                            SizedBox(height: 3),

                            Text(
                              'The imported items will become available for direct linking to drawing measurements.',
                              style: TextStyle(
                                color: AqsColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 18),

                      FilledButton.icon(
                        onPressed: _canImport ? _continueImport : null,

                        icon:
                            _importing
                                ? const SizedBox.square(
                                  dimension: 18,

                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.arrow_forward_rounded),

                        label: Text(_importing ? 'Importing...' : 'Import BOQ'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.fileName,
    required this.loading,
    required this.onPick,
  });

  final String? fileName;
  final bool loading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasFile = (fileName ?? '').trim().isNotEmpty;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(30),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),

      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,

            decoration: BoxDecoration(
              color: AqsColors.primary.withOpacity(0.08),

              borderRadius: BorderRadius.circular(22),
            ),

            child: const Icon(
              Icons.table_view_rounded,

              color: AqsColors.primary,

              size: 34,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            hasFile ? fileName! : 'Upload BOQ Excel file',

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: AqsColors.ink,

              fontSize: 19,

              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            hasFile
                ? 'The workbook is loaded. Review the worksheet and column mapping before importing.'
                : 'Select an .xlsx or .xls BOQ file. AQS will analyse the workbook before anything is saved.',

            textAlign: TextAlign.center,

            style: const TextStyle(color: AqsColors.muted, height: 1.45),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: loading ? null : onPick,

            icon:
                loading
                    ? const SizedBox.square(
                      dimension: 18,

                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.upload_file_rounded),

            label: Text(hasFile ? 'Choose another file' : 'Browse Excel file'),
          ),
        ],
      ),
    );
  }
}

class _WorkbookSummaryCard extends StatelessWidget {
  const _WorkbookSummaryCard({
    required this.fileName,
    required this.sheetCount,
    required this.rowCount,
  });

  final String fileName;
  final int sheetCount;
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),

      child: Wrap(
        spacing: 28,

        runSpacing: 14,

        children: [
          _SummaryMetric(
            icon: Icons.description_outlined,

            label: 'File',

            value: fileName,
          ),

          _SummaryMetric(
            icon: Icons.tab_outlined,

            label: 'Worksheets',

            value: '$sheetCount',
          ),

          _SummaryMetric(
            icon: Icons.format_list_numbered_rounded,

            label: 'Detected rows',

            value: '$rowCount',
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
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
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icon, size: 20, color: AqsColors.primary),

        const SizedBox(width: 9),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              label,
              style: const TextStyle(
                color: AqsColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 2),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),

              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColumnMappingCard extends StatelessWidget {
  const _ColumnMappingCard({
    required this.rows,
    required this.headerRowIndex,
    required this.columnItems,
    required this.itemNoColumn,
    required this.descriptionColumn,
    required this.unitColumn,
    required this.quantityColumn,
    required this.rateColumn,
    required this.amountColumn,
    required this.onHeaderRowChanged,
    required this.onItemNoChanged,
    required this.onDescriptionChanged,
    required this.onUnitChanged,
    required this.onQuantityChanged,
    required this.onRateChanged,
    required this.onAmountChanged,
  });

  final List<List<String>> rows;

  final int headerRowIndex;

  final List<DropdownMenuItem<int?>> columnItems;

  final int? itemNoColumn;
  final int? descriptionColumn;
  final int? unitColumn;
  final int? quantityColumn;
  final int? rateColumn;
  final int? amountColumn;

  final ValueChanged<int> onHeaderRowChanged;

  final ValueChanged<int?> onItemNoChanged;

  final ValueChanged<int?> onDescriptionChanged;

  final ValueChanged<int?> onUnitChanged;

  final ValueChanged<int?> onQuantityChanged;

  final ValueChanged<int?> onRateChanged;

  final ValueChanged<int?> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final maxHeader =
        rows.isEmpty ? 0 : (rows.length > 20 ? 19 : rows.length - 1);

    Widget mappingField({
      required String label,
      required int? value,
      required ValueChanged<int?> onChanged,
      bool requiredField = false,
    }) {
      return DropdownButtonFormField<int?>(
        value: value,

        isExpanded: true,

        items: columnItems,

        onChanged: onChanged,

        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,

          border: const OutlineInputBorder(),
        ),
      );
    }

    return _SectionCard(
      number: '2',

      title: 'Map BOQ columns',

      subtitle:
          'Confirm where AQS should read each BOQ field. Description is required.',

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Header row',

                  style: TextStyle(
                    color: AqsColors.ink,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              DropdownButton<int>(
                value: headerRowIndex,

                items: List.generate(maxHeader + 1, (index) {
                  return DropdownMenuItem<int>(
                    value: index,

                    child: Text('Row ${index + 1}'),
                  );
                }),

                onChanged: (value) {
                  if (value != null) {
                    onHeaderRowChanged(value);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 760;

              final fields = <Widget>[
                mappingField(
                  label: 'Item No.',
                  value: itemNoColumn,
                  onChanged: onItemNoChanged,
                ),

                mappingField(
                  label: 'Description',
                  value: descriptionColumn,
                  onChanged: onDescriptionChanged,
                  requiredField: true,
                ),

                mappingField(
                  label: 'Unit',
                  value: unitColumn,
                  onChanged: onUnitChanged,
                ),

                mappingField(
                  label: 'Quantity',
                  value: quantityColumn,
                  onChanged: onQuantityChanged,
                ),

                mappingField(
                  label: 'Rate',
                  value: rateColumn,
                  onChanged: onRateChanged,
                ),

                mappingField(
                  label: 'Amount',
                  value: amountColumn,
                  onChanged: onAmountChanged,
                ),
              ];

              if (!desktop) {
                return Column(
                  children:
                      fields
                          .map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),

                              child: field,
                            ),
                          )
                          .toList(),
                );
              }

              final width = (constraints.maxWidth - 24) / 3;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    fields
                        .map((field) => SizedBox(width: width, child: field))
                        .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.rows,
    required this.itemNoColumn,
    required this.descriptionColumn,
    required this.unitColumn,
    required this.quantityColumn,
    required this.rateColumn,
    required this.amountColumn,
  });

  final List<List<String>> rows;

  final int? itemNoColumn;
  final int? descriptionColumn;
  final int? unitColumn;
  final int? quantityColumn;
  final int? rateColumn;
  final int? amountColumn;

  String _valueAt(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) {
      return '';
    }

    return row[index];
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      number: '3',

      title: 'Preview BOQ',

      subtitle:
          'Check the mapped data before AQS creates the project BOQ template.',

      child:
          rows.isEmpty
              ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),

                child: Center(child: Text('No data rows found.')),
              )
              : Scrollbar(
                thumbVisibility: true,

                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,

                  child: DataTable(
                    headingRowHeight: 48,

                    dataRowMinHeight: 52,

                    dataRowMaxHeight: 72,

                    columns: const [
                      DataColumn(label: Text('Item')),

                      DataColumn(label: Text('Description')),

                      DataColumn(label: Text('Unit')),

                      DataColumn(label: Text('Quantity')),

                      DataColumn(label: Text('Rate')),

                      DataColumn(label: Text('Amount')),
                    ],

                    rows:
                        rows.map((row) {
                          return DataRow(
                            cells: [
                              DataCell(Text(_valueAt(row, itemNoColumn))),

                              DataCell(
                                SizedBox(
                                  width: 380,

                                  child: Text(
                                    _valueAt(row, descriptionColumn),

                                    maxLines: 2,

                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              DataCell(Text(_valueAt(row, unitColumn))),

                              DataCell(Text(_valueAt(row, quantityColumn))),

                              DataCell(Text(_valueAt(row, rateColumn))),

                              DataCell(Text(_valueAt(row, amountColumn))),
                            ],
                          );
                        }).toList(),
                  ),
                ),
              ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 34,
                height: 34,

                alignment: Alignment.center,

                decoration: BoxDecoration(
                  color: AqsColors.primary.withOpacity(0.10),

                  borderRadius: BorderRadius.circular(11),
                ),

                child: Text(
                  number,

                  style: const TextStyle(
                    color: AqsColors.primary,

                    fontWeight: FontWeight.w900,
                  ),
                ),
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

                        fontSize: 18,

                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,

                      style: const TextStyle(
                        color: AqsColors.muted,

                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }
}

class _ImportResultRow extends StatelessWidget {
  const _ImportResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AqsColors.muted)),
        ),

        Text(
          value,

          style: const TextStyle(
            color: AqsColors.ink,

            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
