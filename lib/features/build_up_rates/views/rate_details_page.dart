import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/build_up_rates/controllers/build_up_rates_controller.dart';
import 'package:aqs/features/build_up_rates/models/build_up_rate.dart';
import 'package:aqs/features/build_up_rates/repositories/build_up_rate_repository.dart';
import 'package:aqs/features/build_up_rates/services/rate_pdf_service.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class RateDetailsPage extends StatelessWidget {
  const RateDetailsPage({super.key, required this.rateId});
  final String rateId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Build-Up Rates',
          onPressed: () => Get.offNamed(AppRoutes.buildUpRates),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Rate Details'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton.icon(
              onPressed: () => Get.offNamed(AppRoutes.buildUpRates),
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('All Build-Up Rates'),
            ),
          ),
        ],
      ),
      body:
          uid == null
              ? const Center(child: Text('Sign in to view this rate.'))
              : FutureBuilder<BuildUpRate?>(
                future: BuildUpRateRepository().get(uid, rateId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rate = snapshot.data;
                  if (rate == null) {
                    return const Center(child: Text('Rate not found.'));
                  }
                  return _RateDetailsContent(rate: rate);
                },
              ),
    );
  }
}

class _RateDetailsContent extends StatelessWidget {
  const _RateDetailsContent({required this.rate});
  final BuildUpRate rate;

  String get _pdfName {
    final safeName = rate.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'AQS_Build_Up_Rate_${safeName.isEmpty ? 'Rate' : safeName}';
  }

  Future<void> _sharePdf(BuildContext context) async {
    var progressIsOpen = true;
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: SizedBox(
                width: 340,
                child: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Creating PDF document',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Preparing the branded AQS rate for WhatsApp…',
                            style: TextStyle(color: AqsColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    Future<void> closeProgress() async {
      if (!progressIsOpen || !context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressIsOpen = false;
      await progressDialog;
    }

    try {
      final bytes = await const RatePdfService().build(rate);
      await closeProgress();
      if (!context.mounted) return;

      // A browser that cannot share PDF files must report an error instead of
      // silently downloading the document.
      Share.downloadFallbackEnabled = false;
      final box = context.findRenderObject() as RenderBox?;
      final result = await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: '$_pdfName.pdf',
          ),
        ],
        subject: 'AQS Build-Up Rate — ${rate.name}',
        text:
            'AQS build-up rate for ${rate.name}. Learn more at ${RatePdfService.website}',
        fileNameOverrides: ['$_pdfName.pdf'],
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
      if (result.status == ShareResultStatus.unavailable && context.mounted) {
        await _showShareError(context);
      }
    } catch (_) {
      await closeProgress();
      if (context.mounted) await _showShareError(context);
    }
  }

  Future<void> _showShareError(BuildContext context) => showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          icon: const Icon(Icons.info_outline_rounded),
          title: const Text('WhatsApp sharing is unavailable'),
          content: const Text(
            'This browser cannot share PDF files directly. Open AQS on a device or browser that supports file sharing, then choose WhatsApp.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
  );

  Future<void> _downloadPdf(BuildContext context) async {
    var progressIsOpen = true;
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: SizedBox(
                width: 340,
                child: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Creating rate document',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Preparing the detailed AQS PDF for download…',
                            style: TextStyle(color: AqsColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    Future<void> closeProgress() async {
      if (!progressIsOpen || !context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressIsOpen = false;
      await progressDialog;
    }

    try {
      final bytes = await const RatePdfService().build(rate);
      await FileSaver.instance.saveFile(
        name: _pdfName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      await closeProgress();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
              title: const Text('Rate PDF downloaded'),
              content: const Text(
                'The detailed branded AQS rate document is ready.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
      );
    } catch (_) {
      await closeProgress();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Download failed'),
              content: const Text(
                'The rate PDF could not be downloaded. Please try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rate.name,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rate.description,
                style: const TextStyle(color: AqsColors.muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(label: Text(rate.category.label)),
                  if (rate.activity.isNotEmpty)
                    Chip(label: Text(rate.activity)),
                  Chip(label: Text(rate.unit)),
                  Chip(
                    label: Text(
                      '${rate.currency} ${money.format(rate.finalRate)} / ${rate.unit}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        () => Get.toNamed(
                          AppRoutes.buildUpRateEditPath(rate.rateId),
                        ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Rate'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        () => Get.snackbar(
                          'Coming soon',
                          'BOQ rate assignment is the next extension point.',
                        ),
                    icon: const Icon(Icons.link),
                    label: const Text('Use in BOQ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _downloadPdf(context),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download Rate PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final controller =
                          Get.isRegistered<BuildUpRatesController>()
                              ? Get.find<BuildUpRatesController>()
                              : Get.put(BuildUpRatesController());
                      await controller.load();
                      final id = await controller.duplicate(rate);
                      if (id != null) {
                        Get.offNamed(AppRoutes.buildUpRateDetailsPath(id));
                      }
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Duplicate Rate'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _sharePdf(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Share PDF to WhatsApp'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AqsColors.border),
                ),
                child: Column(
                  children: [
                    for (final component in rate.components)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          component.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${NumberFormat('#,##0.####').format(component.quantity)} ${component.unit} × ${rate.currency} ${money.format(component.unitRate)}${component.wastePercent > 0 ? ' + ${NumberFormat('#,##0.##').format(component.wastePercent)}% waste' : ''}',
                        ),
                        trailing: Text(
                          '${rate.currency} ${money.format(component.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    const Divider(),
                    _line('Direct Cost', rate.directCost, money),
                    _line(
                      'Overheads (${rate.overheadsPercent}%)',
                      rate.overheadsAmount,
                      money,
                    ),
                    _line(
                      'Profit (${rate.profitPercent}%)',
                      rate.profitAmount,
                      money,
                    ),
                    const Divider(),
                    _line(
                      'FINAL RATE / ${rate.unit}',
                      rate.finalRate,
                      money,
                      strong: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(
    String label,
    double amount,
    NumberFormat format, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${rate.currency} ${format.format(amount)}',
            style: TextStyle(
              fontSize: strong ? 18 : 14,
              color: strong ? AqsColors.primary : AqsColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
