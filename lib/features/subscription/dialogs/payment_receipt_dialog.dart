import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:aqs/features/subscription/services/aqs_payment_service.dart';
import 'package:flutter/material.dart';

class PaymentReceiptDialog extends StatelessWidget {
  const PaymentReceiptDialog({
    super.key,
    required this.result,
    required this.plan,
    required this.yearly,
  });

  final AqsPaymentResult result;
  final PricingPlan plan;
  final bool yearly;

  String _text(String? value, {String fallback = '-'}) {
    final text = (value ?? '').trim();

    return text.isEmpty ? fallback : text;
  }

  String _formatAmount(dynamic value) {
    if (value == null) {
      return '-';
    }

    final number = num.tryParse(value.toString());

    if (number == null) {
      return value.toString();
    }

    final string = number.toStringAsFixed(0);

    final formatted = string.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );

    return formatted;
  }

  String _providerLabel(String provider) {
    switch (provider.trim().toLowerCase()) {
      case 'airtel':
        return 'Airtel Money';

      case 'tigo':
        return 'Mixx by Yas';

      case 'halopesa':
        return 'HaloPesa';

      case 'mpesa':
        return 'M-Pesa';

      case 'azampesa':
        return 'AzamPesa';

      default:
        return provider.isEmpty ? '-' : provider;
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentId = _text(result.paymentId);

    final externalId = _text(result.externalId);

    final currency = _text(result.currency, fallback: 'TZS');

    final provider = _providerLabel(_text(result.provider, fallback: ''));

    final providerReference = _text(result.providerReference);

    final amount = _formatAmount(result.amount);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
        child: Material(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(28),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),

                /*
                 * AQS branding
                 */
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'AQS ',
                        style: TextStyle(
                          color: AqsColors.primary,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: 'AutoBOQ',
                        style: TextStyle(
                          color: AqsColors.ink,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Smart BOQ. Faster Estimation.',
                  style: TextStyle(
                    color: AqsColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 20),

                /*
                 * Receipt card
                 */
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                        child: Column(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF8EE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 38,
                                color: Color(0xFF22A447),
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'Payment Successful',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AqsColors.ink,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),

                            const SizedBox(height: 14),

                            _ReceiptInfoText(
                              label: 'Payment number',
                              value: externalId != '-' ? externalId : paymentId,
                              highlight: true,
                            ),

                            const SizedBox(height: 7),

                            _ReceiptInfoText(
                              label: 'Payment ID',
                              value: paymentId,
                            ),
                          ],
                        ),
                      ),

                      /*
                       * Ticket divider
                       */
                      const _ReceiptDivider(),

                      /*
                       * Items
                       */
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    'No',
                                    style: TextStyle(
                                      color: AqsColors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Description',
                                    style: TextStyle(
                                      color: AqsColors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Amount',
                                  style: TextStyle(
                                    color: AqsColors.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 22),

                            _ReceiptLineItem(
                              number: '1',
                              title: 'AQS AutoBOQ ${plan.name}',
                              subtitle:
                                  '1 x ${yearly ? 'Yearly' : 'Monthly'} subscription',
                              amount: '$currency $amount',
                            ),

                            const SizedBox(height: 18),

                            const Divider(height: 1, color: Color(0xFFE5E7EB)),

                            const SizedBox(height: 18),

                            _ReceiptLineItem(
                              number: '2',
                              title: 'QuickLipa Processing',
                              subtitle: 'Payment completed',
                              amount: '$currency 0',
                            ),

                            const SizedBox(height: 20),

                            /*
                             * Total panel
                             */
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F5FF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE8E2FF),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Total',
                                        style: TextStyle(
                                          color: AqsColors.ink,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$currency $amount',
                                        style: const TextStyle(
                                          color: AqsColors.primary,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 14),

                                  Container(
                                    height: 1,
                                    color: AqsColors.primary.withOpacity(0.35),
                                  ),

                                  const SizedBox(height: 14),

                                  const _ReceiptSummaryRow(
                                    label: 'Payment method',
                                    value: 'Mobile Money',
                                  ),

                                  const SizedBox(height: 10),

                                  _ReceiptSummaryRow(
                                    label: 'Provider',
                                    value: provider,
                                  ),

                                  const SizedBox(height: 10),

                                  const _ReceiptSummaryRow(
                                    label: 'Tax',
                                    value: 'TZS 0',
                                  ),

                                  if (providerReference != '-') ...[
                                    const SizedBox(height: 10),
                                    _ReceiptSummaryRow(
                                      label: 'Provider ref.',
                                      value: providerReference,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                /*
                 * Close / back
                 */
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('OK'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AqsColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                /*
                 * Download receipt
                 */
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      /*
                       * We'll connect this
                       * to PDF generation next.
                       */
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'PDF receipt generation will be added next.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download Receipt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AqsColors.primary,
                      side: const BorderSide(color: AqsColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Secured and powered by QuickLipa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AqsColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptInfoText extends StatelessWidget {
  const _ReceiptInfoText({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: AqsColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        SelectableText(
          value,
          style: TextStyle(
            color: highlight ? AqsColors.primary : AqsColors.ink,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8FA),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
          ),
        ),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dashWidth = 8.0;

              const dashGap = 7.0;

              final dashCount =
                  (constraints.maxWidth / (dashWidth + dashGap)).floor();

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  dashCount,
                  (_) => Container(
                    width: dashWidth,
                    height: 1,
                    color: const Color(0xFFD0D5DD),
                  ),
                ),
              );
            },
          ),
        ),

        Container(
          width: 14,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8FA),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
          ),
        ),
      ],
    );
  }
}

class _ReceiptLineItem extends StatelessWidget {
  const _ReceiptLineItem({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final String number;
  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Text(
            number,
            style: const TextStyle(
              color: AqsColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                subtitle,
                style: const TextStyle(
                  color: AqsColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        Text(
          amount,
          style: const TextStyle(
            color: AqsColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReceiptSummaryRow extends StatelessWidget {
  const _ReceiptSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AqsColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(width: 12),

        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AqsColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
