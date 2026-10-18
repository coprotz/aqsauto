import 'dart:convert';
import 'dart:typed_data';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/app_routes.dart';
import 'package:aqs/features/material_prices/models/material_catalog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

const _collectionName = 'materialPrices';
const _suppliersCollectionName = 'suppliers';

class _Supplier {
  const _Supplier({
    required this.id,
    required this.name,
    required this.location,
    required this.district,
    required this.region,
    required this.website,
    required this.socialMedia,
    required this.contactName,
    required this.contactDetails,
    required this.logoUrl,
  });

  factory _Supplier.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return _Supplier(
      id: document.id,
      name: (data['name'] ?? '').toString().trim(),
      location: (data['location'] ?? '').toString().trim(),
      district: (data['district'] ?? '').toString().trim(),
      region: (data['region'] ?? '').toString().trim(),
      website: (data['website'] ?? '').toString().trim(),
      socialMedia: (data['socialMedia'] ?? '').toString().trim(),
      contactName: (data['contactName'] ?? '').toString().trim(),
      contactDetails: (data['contactDetails'] ?? '').toString().trim(),
      logoUrl: (data['logoUrl'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String name;
  final String location;
  final String district;
  final String region;
  final String website;
  final String socialMedia;
  final String contactName;
  final String contactDetails;
  final String logoUrl;

  String get dropdownLabel {
    final area = [district, region].where((value) => value.isNotEmpty).join(', ');
    return [name, area, contactName]
        .where((value) => value.isNotEmpty)
        .join(' • ');
  }

  String get displayLocation =>
      [location, district, region].where((value) => value.isNotEmpty).join(', ');
}

class _MaterialPrice {
  const _MaterialPrice({
    required this.id,
    required this.material,
    required this.category,
    required this.subcategory,
    required this.size,
    required this.quantity,
    required this.unit,
    required this.supplier,
    required this.supplierId,
    required this.price,
    required this.currency,
    required this.location,
    required this.effectiveDate,
    required this.notes,
  });

  factory _MaterialPrice.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawDate = data['effectiveDate'];
    return _MaterialPrice(
      id: document.id,
      material: (data['material'] ?? data['name'] ?? '').toString().trim(),
      category: (data['category'] ?? 'Other').toString().trim(),
      subcategory: (data['subcategory'] ?? '').toString().trim(),
      size: (data['size'] ?? '').toString().trim(),
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
      unit: (data['unit'] ?? '').toString().trim(),
      supplier: (data['supplier'] ?? '').toString().trim(),
      supplierId: (data['supplierId'] ?? '').toString().trim(),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      currency: (data['currency'] ?? 'TZS').toString().trim(),
      location: (data['location'] ?? '').toString().trim(),
      effectiveDate:
          rawDate is Timestamp ? rawDate.toDate() : DateTime.tryParse('$rawDate'),
      notes: (data['notes'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String material;
  final String category;
  final String subcategory;
  final String size;
  final double quantity;
  final String unit;
  final String supplier;
  final String supplierId;
  final double price;
  final String currency;
  final String location;
  final DateTime? effectiveDate;
  final String notes;
}

class MaterialPricesPage extends StatefulWidget {
  const MaterialPricesPage({super.key});

  @override
  State<MaterialPricesPage> createState() => _MaterialPricesPageState();
}

class _MaterialPricesPageState extends State<MaterialPricesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All categories';
  String _subcategory = 'All sub-categories';
  String _size = 'All sizes';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AqsColors.canvas,
      appBar: AppBar(
        title: const AqsAppBarTitle(
          title: 'Materials Price List',
          subtitle: 'Compare supplier prices',
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width < 700)
            IconButton(
              tooltip: "Can't find a product? Contact AQS",
              onPressed: () => Get.toNamed(AppRoutes.contact),
              icon: const Icon(Icons.contact_support_outlined),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: () => Get.toNamed(AppRoutes.contact),
                icon: const Icon(Icons.contact_support_outlined),
                label: const Text("Can't find a product? Contact AQS"),
              ),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection(_collectionName)
                .orderBy('material')
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load material prices',
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!.docs.map(_MaterialPrice.fromDocument).toList();
          final categories = all
              .map((item) => item.category)
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final subcategories = all
              .where((item) =>
                  _category == 'All categories' || item.category == _category)
              .map((item) => item.subcategory)
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final sizes = all
              .where((item) =>
                  (_category == 'All categories' || item.category == _category) &&
                  (_subcategory == 'All sub-categories' ||
                      item.subcategory == _subcategory))
              .map((item) => item.size)
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final filtered = all.where((item) {
            final matchesCategory =
                _category == 'All categories' || item.category == _category;
            final matchesSubcategory = _subcategory == 'All sub-categories' ||
                item.subcategory == _subcategory;
            final matchesSize = _size == 'All sizes' || item.size == _size;
            final haystack = '${item.material} ${item.category} '
                    '${item.subcategory} ${item.size} ${item.supplier} '
                    '${item.location} ${item.unit}'
                .toLowerCase();
            return matchesCategory &&
                matchesSubcategory &&
                matchesSize &&
                haystack.contains(_query);
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 28,
                  20,
                  compact ? 16 : 28,
                  40,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PriceHero(itemCount: all.length),
                          const SizedBox(height: 18),
                          if (compact) ...[
                            _searchField(),
                            const SizedBox(height: 12),
                            _categoryField(categories),
                            const SizedBox(height: 12),
                            _subcategoryField(subcategories),
                            const SizedBox(height: 12),
                            _sizeField(sizes),
                          ] else
                            Column(
                              children: [
                                _searchField(),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _categoryField(categories)),
                                    const SizedBox(width: 12),
                                    Expanded(child: _subcategoryField(subcategories)),
                                    const SizedBox(width: 12),
                                    Expanded(child: _sizeField(sizes)),
                                  ],
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          if (filtered.isEmpty)
                            const _MessageCard(
                              title: 'No prices found',
                              message: 'Try another search or category.',
                            )
                          else if (compact)
                            ...filtered.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _PriceCard(
                                  item: item,
                                  onSupplier: () => _showSupplier(item),
                                ),
                              ),
                            )
                          else
                            _PriceTable(
                              items: filtered,
                              onSupplier: _showSupplier,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _searchField() => TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Search material, supplier, unit or location',
        ),
      );

  Widget _categoryField(List<String> categories) {
    final values = ['All categories', ...categories];
    final selected = values.contains(_category) ? _category : values.first;
    return DropdownButtonFormField<String>(
      value: selected,
      decoration: const InputDecoration(labelText: 'Category'),
      items: values
          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
          .toList(),
      onChanged: (value) => setState(() {
        _category = value ?? values.first;
        _subcategory = 'All sub-categories';
        _size = 'All sizes';
      }),
    );
  }

  Widget _subcategoryField(List<String> subcategories) {
    final values = ['All sub-categories', ...subcategories];
    final selected = values.contains(_subcategory) ? _subcategory : values.first;
    return DropdownButtonFormField<String>(
      value: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Sub-category'),
      items: values
          .map((value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) => setState(() {
        _subcategory = value ?? values.first;
        _size = 'All sizes';
      }),
    );
  }

  Widget _sizeField(List<String> sizes) {
    final values = ['All sizes', ...sizes];
    final selected = values.contains(_size) ? _size : values.first;
    return DropdownButtonFormField<String>(
      value: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Size'),
      items: values
          .map((value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) => setState(() => _size = value ?? values.first),
    );
  }

  Future<void> _showSupplier(_MaterialPrice item) async {
    if (item.supplierId.isEmpty) {
      _showLegacySupplier(item);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _SupplierDetailsDialog(
        supplierId: item.supplierId,
        fallbackName: item.supplier,
      ),
    );
  }

  void _showLegacySupplier(_MaterialPrice item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.supplier),
        content: Text(item.location.isEmpty
            ? 'No additional supplier details are available for this older price.'
            : item.location),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class AdminMaterialPricesPage extends StatefulWidget {
  const AdminMaterialPricesPage({super.key});

  @override
  State<AdminMaterialPricesPage> createState() =>
      _AdminMaterialPricesPageState();
}

class _AdminMaterialPricesPageState extends State<AdminMaterialPricesPage> {
  late final Future<bool> _adminAccess;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _adminAccess = _hasAdminAccess();
  }

  Future<bool> _hasAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult();
    return token.claims?['admin'] == true;
  }

  Future<void> _openEditor([_MaterialPrice? item]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaterialPriceEditor(item: item),
    );
  }

  Future<void> _delete(_MaterialPrice item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete material price?'),
        content: Text('${item.material} from ${item.supplier} will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(item.id)
          .delete();
    }
  }

  Future<void> _editSupplier(_MaterialPrice price) async {
    if (price.supplierId.isEmpty) {
      _snack('This older price is not linked to a supplier record yet.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _SupplierDetailsDialog(
        supplierId: price.supplierId,
        fallbackName: price.supplier,
        onEdit: (supplier) async {
          await showDialog<_Supplier>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _SupplierEditor(item: supplier),
          );
        },
      ),
    );
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _snack('Could not read that CSV file.');
      return;
    }
    setState(() => _importing = true);
    try {
      final rows = const LineSplitter().convert(utf8.decode(bytes));
      if (rows.isEmpty) throw const FormatException('The CSV is empty.');
      final header = _parseCsvRow(rows.first)
          .map((value) => value.replaceFirst('\ufeff', '').trim().toLowerCase())
          .toList();
      int column(String name) => header.indexOf(name);
      final required = ['category', 'unit', 'supplier', 'price'];
      if (required.any((name) => column(name) < 0)) {
        throw const FormatException(
          'Required columns: category, subcategory, unit, supplier, price.',
        );
      }
      if (column('subcategory') < 0 && column('sub-category') < 0) {
        throw const FormatException(
          'The CSV must include a subcategory or sub-category column.',
        );
      }
      final collection = FirebaseFirestore.instance.collection(_collectionName);
      var imported = 0;
      WriteBatch batch = FirebaseFirestore.instance.batch();
      var batchSize = 0;
      for (final line in rows.skip(1)) {
        if (line.trim().isEmpty) continue;
        final cells = _parseCsvRow(line);
        String read(String name) {
          final index = column(name);
          return index >= 0 && index < cells.length ? cells[index].trim() : '';
        }
        final price = double.tryParse(read('price').replaceAll(',', ''));
        final subcategory = read('subcategory').isEmpty
            ? read('sub-category')
            : read('subcategory');
        if (subcategory.isEmpty || read('supplier').isEmpty || price == null) {
          continue;
        }
        final date = DateTime.tryParse(read('effective date')) ??
            DateTime.tryParse(read('effectivedate')) ??
            DateTime.now();
        batch.set(collection.doc(), {
          'material': subcategory,
          'category': read('category').isEmpty ? 'Other' : read('category'),
          'subcategory': subcategory,
          'size': read('size'),
          'quantity': double.tryParse(read('quantity')) ?? 1,
          'unit': read('unit'),
          'supplier': read('supplier'),
          'price': price,
          'currency': read('currency').isEmpty ? 'TZS' : read('currency'),
          'location': read('location'),
          'effectiveDate': Timestamp.fromDate(date),
          'notes': read('notes'),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid,
        });
        imported++;
        batchSize++;
        if (batchSize == 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          batchSize = 0;
        }
      }
      if (batchSize > 0) await batch.commit();
      _snack('$imported material prices imported.');
    } on FormatException catch (error) {
      _snack(error.message);
    } catch (error) {
      _snack('Import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminAccess,
      builder: (context, access) {
        if (!access.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (access.data != true) {
          return const Scaffold(
            body: _MessageState(
              icon: Icons.lock_outline_rounded,
              title: 'Admin access required',
              message: 'Only an administrator can manage material prices.',
            ),
          );
        }
        return Scaffold(
          backgroundColor: AqsColors.canvas,
          appBar: AppBar(title: const Text('Manage Material Prices')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add price'),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection(_collectionName)
                .orderBy('material')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MessageState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load prices',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!.docs.map(_MaterialPrice.fromDocument).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AdminHeader(
                            count: items.length,
                            importing: _importing,
                            onImport: _importCsv,
                            onAdd: () => _openEditor(),
                          ),
                          const SizedBox(height: 16),
                          if (items.isEmpty)
                            const _MessageCard(
                              title: 'No material prices yet',
                              message: 'Add one price or import a CSV price list.',
                            )
                          else
                            ...items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _AdminPriceCard(
                                  item: item,
                                  onSupplier: () => _editSupplier(item),
                                  onEdit: () => _openEditor(item),
                                  onDelete: () => _delete(item),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _MaterialPriceEditor extends StatefulWidget {
  const _MaterialPriceEditor({this.item});
  final _MaterialPrice? item;

  @override
  State<_MaterialPriceEditor> createState() => _MaterialPriceEditorState();
}

class _MaterialPriceEditorState extends State<_MaterialPriceEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _customSize;
  late final TextEditingController _price;
  late final TextEditingController _currency;
  late final TextEditingController _notes;
  late DateTime _effectiveDate;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String? _selectedSize;
  String? _selectedUnit;
  List<_Supplier> _suppliers = const [];
  String? _selectedSupplierId;
  bool _loadingSuppliers = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _quantity = TextEditingController(text: '${item?.quantity ?? 1}');
    _customSize = TextEditingController();
    _selectedCategory = materialCatalog.containsKey(item?.category)
        ? item?.category
        : null;
    final initialSubcategories = materialCatalog[_selectedCategory]?.keys;
    _selectedSubcategory = initialSubcategories?.contains(item?.subcategory) == true
        ? item?.subcategory
        : null;
    final initialSizes =
        materialCatalog[_selectedCategory]?[_selectedSubcategory] ?? const [];
    if (initialSizes.contains(item?.size)) {
      _selectedSize = item?.size;
    } else if ((item?.size ?? '').isNotEmpty) {
      _selectedSize = 'Custom / other';
      _customSize.text = item!.size;
    }
    _selectedUnit = materialUnits.contains(item?.unit) ? item?.unit : null;
    _price = TextEditingController(text: item == null ? '' : '${item.price}');
    _currency = TextEditingController(text: item?.currency ?? 'TZS');
    _notes = TextEditingController(text: item?.notes);
    _effectiveDate = item?.effectiveDate ?? DateTime.now();
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (final controller in [
      _quantity, _customSize, _price, _currency, _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_suppliersCollectionName)
          .orderBy('name')
          .get();
      final suppliers = snapshot.docs.map(_Supplier.fromDocument).toList();
      var selectedId = widget.item?.supplierId;
      if ((selectedId ?? '').isEmpty && widget.item != null) {
        for (final supplier in suppliers) {
          if (supplier.name.toLowerCase() ==
              widget.item!.supplier.toLowerCase()) {
            selectedId = supplier.id;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _selectedSupplierId = suppliers.any((item) => item.id == selectedId)
            ? selectedId
            : null;
        _loadingSuppliers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingSuppliers = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load suppliers: $error')),
      );
    }
  }

  Future<void> _addSupplier() async {
    final supplier = await showDialog<_Supplier>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SupplierEditor(),
    );
    if (supplier == null || !mounted) return;
    setState(() {
      _suppliers = [..._suppliers, supplier]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedSupplierId = supplier.id;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _Supplier? supplier;
    for (final item in _suppliers) {
      if (item.id == _selectedSupplierId) {
        supplier = item;
        break;
      }
    }
    if (supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a supplier before saving.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'material': _selectedSubcategory,
        'category': _selectedCategory,
        'subcategory': _selectedSubcategory,
        'size': _selectedSize == 'Custom / other'
            ? _customSize.text.trim()
            : _selectedSize,
        'quantity': double.parse(_quantity.text.trim()),
        'unit': _selectedUnit,
        'supplierId': supplier.id,
        'supplier': supplier.name,
        'supplierDistrict': supplier.district,
        'supplierRegion': supplier.region,
        'supplierContactName': supplier.contactName,
        'supplierLogoUrl': supplier.logoUrl,
        'price': double.parse(_price.text.trim().replaceAll(',', '')),
        'currency': _currency.text.trim().isEmpty ? 'TZS' : _currency.text.trim(),
        'location': supplier.displayLocation,
        'effectiveDate': Timestamp.fromDate(_effectiveDate),
        'notes': _notes.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      };
      final collection = FirebaseFirestore.instance.collection(_collectionName);
      if (widget.item == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['createdBy'] = FirebaseAuth.instance.currentUser?.uid;
        await collection.add(data);
      } else {
        await collection.doc(widget.item!.id).update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save price: $error')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height - (compact ? 24 : 64),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item == null ? 'Add material price' : 'Edit material price',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _catalogDropdowns(compact),
                      const SizedBox(height: 12),
                      _responsivePair(
                        compact,
                        TextFormField(
                          controller: _quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(labelText: 'Quantity'),
                          validator: (value) {
                            final quantity = double.tryParse((value ?? '').trim());
                            return quantity == null || quantity <= 0
                                ? 'Enter a quantity greater than zero'
                                : null;
                          },
                        ),
                        DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          isExpanded: true,
                          menuMaxHeight: 360,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: materialUnits
                              .map((unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedUnit = value),
                          validator: (value) => value == null ? 'Select a unit' : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _supplierSelector(),
                      const SizedBox(height: 12),
                      _responsivePair(
                        compact,
                        TextFormField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Price'),
                          validator: (value) {
                            final number = double.tryParse((value ?? '').replaceAll(',', ''));
                            return number == null || number < 0 ? 'Enter a valid price' : null;
                          },
                        ),
                        _requiredField(_currency, 'Currency'),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              initialDate: _effectiveDate,
                            );
                            if (picked != null) setState(() => _effectiveDate = picked);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Effective date',
                              suffixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            child: Text(DateFormat('dd MMM yyyy').format(_effectiveDate)),
                          ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save price'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requiredField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _supplierSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedSupplierId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Supplier',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          hint: Text(
            _loadingSuppliers
                ? 'Loading suppliers...'
                : _suppliers.isEmpty
                    ? 'No suppliers available'
                    : 'Select supplier',
          ),
          items: _suppliers
              .map(
                (supplier) => DropdownMenuItem(
                  value: supplier.id,
                  child: Text(
                    supplier.dropdownLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _loadingSuppliers
              ? null
              : (value) => setState(() => _selectedSupplierId = value),
          validator: (value) => value == null ? 'Select a supplier' : null,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addSupplier,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Supplier not listed? Add new supplier'),
          ),
        ),
      ],
    );
  }

  Widget _catalogDropdowns(bool compact) {
    final categories = materialCatalog.keys.toList();
    final subcategories =
        materialCatalog[_selectedCategory]?.keys.toList() ?? const <String>[];
    final sizes = materialCatalog[_selectedCategory]?[_selectedSubcategory] ??
        const <String>[];
    final fields = <Widget>[
      DropdownButtonFormField<String>(
        value: _selectedCategory,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items: categories
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (value) => setState(() {
          _selectedCategory = value;
          _selectedSubcategory = null;
          _selectedSize = null;
          _customSize.clear();
        }),
        validator: (value) => value == null ? 'Select a category' : null,
      ),
      DropdownButtonFormField<String>(
        value: _selectedSubcategory,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sub-category'),
        items: subcategories
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: _selectedCategory == null
            ? null
            : (value) => setState(() {
                  _selectedSubcategory = value;
                  _selectedSize = null;
                  _customSize.clear();
                }),
        validator: (value) => value == null ? 'Select a sub-category' : null,
      ),
      DropdownButtonFormField<String>(
        value: _selectedSize,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Size / specification'),
        items: sizes
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: _selectedSubcategory == null
            ? null
            : (value) => setState(() {
                  _selectedSize = value;
                  if (value != 'Custom / other') _customSize.clear();
                }),
        validator: (value) => value == null ? 'Select a size' : null,
      ),
    ];
    final dropdowns = compact
        ? Column(
            children: [
              fields[0],
              const SizedBox(height: 12),
              fields[1],
              const SizedBox(height: 12),
              fields[2],
            ],
          )
        : Row(
            children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 12),
              Expanded(child: fields[1]),
              const SizedBox(width: 12),
              Expanded(child: fields[2]),
            ],
          );
    return Column(
      children: [
        dropdowns,
        if (_selectedSize == 'Custom / other') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customSize,
            decoration: const InputDecoration(
              labelText: 'Custom size / specification',
            ),
            validator: (value) => _selectedSize == 'Custom / other' &&
                    (value ?? '').trim().isEmpty
                ? 'Enter the custom size'
                : null,
          ),
        ],
      ],
    );
  }

  Widget _responsivePair(bool compact, Widget first, Widget second) {
    if (compact) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(children: [Expanded(child: first), const SizedBox(width: 12), Expanded(child: second)]);
  }
}

class _SupplierEditor extends StatefulWidget {
  const _SupplierEditor({this.item});

  final _Supplier? item;

  @override
  State<_SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends State<_SupplierEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _district = TextEditingController();
  final _region = TextEditingController();
  final _website = TextEditingController();
  final _socialMedia = TextEditingController();
  final _contactName = TextEditingController();
  final _contactDetails = TextEditingController();
  Uint8List? _logoBytes;
  String _logoFileName = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) return;
    _name.text = item.name;
    _location.text = item.location;
    _district.text = item.district;
    _region.text = item.region;
    _website.text = item.website;
    _socialMedia.text = item.socialMedia;
    _contactName.text = item.contactName;
    _contactDetails.text = item.contactDetails;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _location,
      _district,
      _region,
      _website,
      _socialMedia,
      _contactName,
      _contactDetails,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.bytes == null) {
      _showMessage('Could not read the selected logo.');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      _showMessage('Please select a logo smaller than 5 MB.');
      return;
    }
    setState(() {
      _logoBytes = file.bytes;
      _logoFileName = file.name;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final collection =
          FirebaseFirestore.instance.collection(_suppliersCollectionName);
      final document = widget.item == null
          ? collection.doc()
          : collection.doc(widget.item!.id);
      var logoUrl = widget.item?.logoUrl ?? '';
      if (_logoBytes != null) {
        final extension = _logoFileName.contains('.')
            ? _logoFileName.split('.').last.toLowerCase()
            : 'png';
        final reference = FirebaseStorage.instance
            .ref()
            .child('suppliers/${document.id}/logo.$extension');
        await reference.putData(
          _logoBytes!,
          SettableMetadata(contentType: _logoContentType(extension)),
        );
        logoUrl = await reference.getDownloadURL();
      }
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'location': _location.text.trim(),
        'district': _district.text.trim(),
        'region': _region.text.trim(),
        'website': _website.text.trim(),
        'socialMedia': _socialMedia.text.trim(),
        'contactName': _contactName.text.trim(),
        'contactDetails': _contactDetails.text.trim(),
        'logoUrl': logoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      };
      if (widget.item == null) {
        await document.set(data);
      } else {
        data.remove('createdAt');
        data.remove('createdBy');
        await document.update(data);
        await _updateLinkedPrices(document.id, data);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        _Supplier(
          id: document.id,
          name: _name.text.trim(),
          location: _location.text.trim(),
          district: _district.text.trim(),
          region: _region.text.trim(),
          website: _website.text.trim(),
          socialMedia: _socialMedia.text.trim(),
          contactName: _contactName.text.trim(),
          contactDetails: _contactDetails.text.trim(),
          logoUrl: logoUrl,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Could not add supplier: $error');
    }
  }

  Future<void> _updateLinkedPrices(
    String supplierId,
    Map<String, dynamic> supplierData,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionName)
        .where('supplierId', isEqualTo: supplierId)
        .get();
    var batch = FirebaseFirestore.instance.batch();
    var count = 0;
    for (final price in snapshot.docs) {
      batch.update(price.reference, {
        'supplier': supplierData['name'],
        'supplierDistrict': supplierData['district'],
        'supplierRegion': supplierData['region'],
        'supplierContactName': supplierData['contactName'],
        'supplierLogoUrl': supplierData['logoUrl'],
        'location': [
          supplierData['location'],
          supplierData['district'],
          supplierData['region'],
        ].where((value) => (value ?? '').toString().trim().isNotEmpty).join(', '),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count == 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 10 : 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height - (compact ? 20 : 64),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          widget.item == null
                              ? 'Add new supplier'
                              : 'Edit supplier',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.item == null
                              ? 'This supplier will be available for all material prices.'
                              : 'Changes will update every linked material price.',
                          style: TextStyle(color: AqsColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _supplierField(_name, 'Supplier name'),
                      const SizedBox(height: 12),
                      _supplierField(
                        _location,
                        'Location / physical address',
                      ),
                      const SizedBox(height: 12),
                      _supplierPair(
                        compact,
                        _supplierField(_district, 'District'),
                        _supplierField(_region, 'Region'),
                      ),
                      const SizedBox(height: 12),
                      _supplierPair(
                        compact,
                        TextFormField(
                          controller: _website,
                          decoration: const InputDecoration(
                            labelText: 'Website (optional)',
                            prefixIcon: Icon(Icons.language_outlined),
                          ),
                        ),
                        TextFormField(
                          controller: _socialMedia,
                          decoration: const InputDecoration(
                            labelText: 'Social media (optional)',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _supplierField(_contactName, 'Contact person name'),
                      const SizedBox(height: 12),
                      _supplierField(
                        _contactDetails,
                        'Contact person phone / email',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickLogo,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _logoFileName.isEmpty
                              ? 'Select supplier logo (optional)'
                              : 'Logo: $_logoFileName',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_business_outlined),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : widget.item == null
                              ? 'Add supplier'
                              : 'Save supplier',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _supplierPair(bool compact, Widget first, Widget second) {
    if (compact) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

String _logoContentType(String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    default:
      return 'image/png';
  }
}

class _PriceHero extends StatelessWidget {
  const _PriceHero({required this.itemCount});
  final int itemCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B2B67), Color(0xFF155EEF)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 42),
            const Text(
              'Current construction material prices',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              '$itemCount supplier price${itemCount == 1 ? '' : 's'} available',
              style: const TextStyle(color: Color(0xFFD6E4FF), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.item, required this.onSupplier});
  final _MaterialPrice item;
  final VoidCallback onSupplier;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.material, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                [item.category, item.subcategory, item.size]
                    .where((value) => value.isNotEmpty)
                    .join(' • '),
                style: const TextStyle(color: AqsColors.muted),
              ),
              const SizedBox(height: 14),
              Text(_priceText(item), style: const TextStyle(color: AqsColors.primary, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(_detailText(item), style: const TextStyle(color: AqsColors.muted)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onSupplier,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text('View ${item.supplier} details'),
              ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      );
}

class _PriceTable extends StatelessWidget {
  const _PriceTable({required this.items, required this.onSupplier});
  final List<_MaterialPrice> items;
  final ValueChanged<_MaterialPrice> onSupplier;

  @override
  Widget build(BuildContext context) => Card(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AqsColors.primarySoft),
              columns: const [
                DataColumn(label: Text('Material')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Sub-category')),
                DataColumn(label: Text('Size')),
                DataColumn(label: Text('Supplier')),
                DataColumn(label: Text('Location')),
                DataColumn(label: Text('Unit price')),
                DataColumn(label: Text('Updated')),
              ],
              rows: items
                  .map((item) => DataRow(cells: [
                        DataCell(Text(item.material, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(item.category)),
                        DataCell(Text(item.subcategory.isEmpty ? '—' : item.subcategory)),
                        DataCell(Text(item.size.isEmpty ? '—' : item.size)),
                        DataCell(TextButton(
                          onPressed: () => onSupplier(item),
                          child: Text(item.supplier),
                        )),
                        DataCell(Text(item.location)),
                        DataCell(Text(_priceText(item), style: const TextStyle(fontWeight: FontWeight.w800))),
                        DataCell(Text(item.effectiveDate == null ? '—' : DateFormat('dd MMM yyyy').format(item.effectiveDate!))),
                      ]))
                  .toList(),
            ),
          ),
        ),
      );
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.count, required this.importing, required this.onImport, required this.onAdd});
  final int count;
  final bool importing;
  final VoidCallback onImport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 430,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Supplier material catalogue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('$count prices • changes appear immediately on the public price list', style: const TextStyle(color: AqsColors.muted)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: importing ? null : onImport,
                icon: importing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(importing ? 'Importing...' : 'Import CSV'),
              ),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add price')),
            ],
          ),
        ),
      );
}

class _AdminPriceCard extends StatelessWidget {
  const _AdminPriceCard({
    required this.item,
    required this.onSupplier,
    required this.onEdit,
    required this.onDelete,
  });
  final _MaterialPrice item;
  final VoidCallback onSupplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: const CircleAvatar(
            backgroundColor: AqsColors.primarySoft,
            child: Icon(Icons.inventory_2_outlined, color: AqsColors.primary),
          ),
          title: Text(item.material, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                [item.category, item.subcategory, item.size]
                    .where((value) => value.isNotEmpty)
                    .join(' • '),
              ),
              Text('${_priceText(item)} • ${_detailText(item)}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onSupplier,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: const Size(48, 40),
                  ),
                  icon: const Icon(Icons.storefront_outlined, size: 17),
                  label: Text('${item.supplier} • View or edit supplier'),
                ),
              ),
            ],
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(tooltip: 'Edit', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Delete', onPressed: onDelete, color: Colors.red, icon: const Icon(Icons.delete_outline_rounded)),
            ],
          ),
        ),
      );
}

class _SupplierDetailsDialog extends StatelessWidget {
  const _SupplierDetailsDialog({
    required this.supplierId,
    required this.fallbackName,
    this.onEdit,
  });

  final String supplierId;
  final String fallbackName;
  final ValueChanged<_Supplier>? onEdit;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection(_suppliersCollectionName)
              .doc(supplierId)
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.data!.exists) {
              return _supplierDialogShell(
                context,
                title: fallbackName,
                child: const Text(
                  'This supplier record is no longer available.',
                  style: TextStyle(color: AqsColors.muted),
                ),
              );
            }
            final supplier = _Supplier.fromDocument(snapshot.data!);
            return _supplierDialogShell(
              context,
              title: supplier.name,
              logoUrl: supplier.logoUrl,
              onEdit: onEdit == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      Future<void>.microtask(() => onEdit!(supplier));
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SupplierDetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: supplier.displayLocation,
                  ),
                  _SupplierDetailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Contact person',
                    value: supplier.contactName,
                  ),
                  _SupplierDetailRow(
                    icon: Icons.contact_phone_outlined,
                    label: 'Contact details',
                    value: supplier.contactDetails,
                  ),
                  if (supplier.website.isNotEmpty)
                    _SupplierDetailRow(
                      icon: Icons.language_outlined,
                      label: 'Website',
                      value: supplier.website,
                    ),
                  if (supplier.socialMedia.isNotEmpty)
                    _SupplierDetailRow(
                      icon: Icons.alternate_email_rounded,
                      label: 'Social media',
                      value: supplier.socialMedia,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _supplierDialogShell(
    BuildContext context, {
    required String title,
    required Widget child,
    String logoUrl = '',
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AqsColors.primarySoft,
                backgroundImage:
                    logoUrl.isEmpty ? null : NetworkImage(logoUrl),
                child: logoUrl.isEmpty
                    ? const Icon(
                        Icons.storefront_outlined,
                        color: AqsColors.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(height: 30),
          child,
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                if (onEdit != null)
                  FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit supplier'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierDetailRow extends StatelessWidget {
  const _SupplierDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AqsColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AqsColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value.isEmpty ? 'Not provided' : value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AqsColors.subtle),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AqsColors.muted)),
            ],
          ),
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 42, color: AqsColors.subtle),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(message, style: const TextStyle(color: AqsColors.muted)),
            ],
          ),
        ),
      );
}

String _priceText(_MaterialPrice item) {
  final price = NumberFormat('#,##0.##').format(item.price);
  final quantity = NumberFormat('#,##0.##').format(item.quantity);
  return '${item.currency} $price / $quantity ${item.unit.isEmpty ? 'unit' : item.unit}';
}

String _detailText(_MaterialPrice item) {
  final parts = <String>[
    if (item.supplier.isNotEmpty) item.supplier,
    if (item.location.isNotEmpty) item.location,
    if (item.effectiveDate != null) DateFormat('dd MMM yyyy').format(item.effectiveDate!),
  ];
  return parts.isEmpty ? 'Effective date not specified' : parts.join(' • ');
}

List<String> _parseCsvRow(String row) {
  final values = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (var index = 0; index < row.length; index++) {
    final character = row[index];
    if (character == '"') {
      if (quoted && index + 1 < row.length && row[index + 1] == '"') {
        current.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      values.add(current.toString());
      current.clear();
    } else {
      current.write(character);
    }
  }
  values.add(current.toString());
  return values;
}
