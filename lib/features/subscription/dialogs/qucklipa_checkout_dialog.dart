import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/pricing/models/pricing_plan.dart';
import 'package:aqs/features/subscription/widgets/inline_payment.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class QuickLipaCheckoutDialog extends StatefulWidget {
  const QuickLipaCheckoutDialog({
    super.key,
    required this.plan,
    required this.yearly,
  });

  final PricingPlan plan;
  final bool yearly;

  @override
  State<QuickLipaCheckoutDialog> createState() =>
      _QuickLipaCheckoutDialogState();
}

class _QuickLipaCheckoutDialogState extends State<QuickLipaCheckoutDialog> {
  final _phoneCtrl = TextEditingController();

  String _provider = 'Airtel';
  String? _errorText;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.plan.priceFor(yearly: widget.yearly);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: Colors.white,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /*
                   * HEADER
                   */
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AqsColors.primaryDark, Color(0xFF155EEF)],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pay ${widget.plan.name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text(
                                widget.yearly
                                    ? 'Yearly subscription via QuickLipa'
                                    : 'Monthly subscription via QuickLipa',
                                style: const TextStyle(
                                  color: Color(0xFFD6E4FF),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        /*
                         * PLAN SUMMARY
                         */
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F7FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD6E4FF)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.workspace_premium_outlined,
                                color: AqsColors.primary,
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatCheckoutPrice(amount),
                                      style: const TextStyle(
                                        color: AqsColors.ink,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),

                                    const SizedBox(height: 2),

                                    Text(
                                      widget.yearly
                                          ? 'Yearly billing'
                                          : 'Monthly billing',
                                      style: const TextStyle(
                                        color: AqsColors.muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.plan.badge,
                                  style: const TextStyle(
                                    color: AqsColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        DropdownButtonFormField<String>(
                          value: _provider,
                          decoration: _checkoutInputDecoration(
                            label: 'Mobile money provider',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Airtel',
                              child: Text('Airtel Money'),
                            ),
                            DropdownMenuItem(
                              value: 'Tigo',
                              child: Text('Mixx by Yas / Tigo'),
                            ),
                            DropdownMenuItem(
                              value: 'Halopesa',
                              child: Text('HaloPesa'),
                            ),
                            DropdownMenuItem(
                              value: 'Mpesa',
                              child: Text('M-Pesa'),
                            ),
                            DropdownMenuItem(
                              value: 'Azampesa',
                              child: Text('AzamPesa'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _provider = value;
                              });
                            }
                          },
                        ),

                        const SizedBox(height: 14),

                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() {
                                _errorText = null;
                              });
                            }
                          },
                          decoration: _checkoutInputDecoration(
                            label: 'Phone number',
                            hint: '0746575399 or 255746575399',
                            icon: Icons.call_outlined,
                          ),
                        ),

                        if (_errorText != null) ...[
                          const SizedBox(height: 10),
                          InlinePaymentNotice(
                            tone: PaymentNoticeTone.error,
                            title: 'Check phone number',
                            message: _errorText!,
                          ),
                        ],

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFEAECF0)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                color: Color(0xFF039855),
                                size: 20,
                              ),

                              SizedBox(width: 10),

                              Expanded(
                                child: Text(
                                  'QuickLipa will securely initiate the mobile money payment. '
                                  'Your AQS subscription activates only after payment confirmation.',
                                  style: TextStyle(
                                    color: AqsColors.muted,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  final phone = _phoneCtrl.text.trim();

                                  if (phone.isEmpty) {
                                    setState(() {
                                      _errorText = 'Enter phone number.';
                                    });
                                    return;
                                  }

                                  Navigator.of(context).pop(
                                    CheckoutInput(
                                      phone: phone,
                                      provider: _provider,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: const Text('Send prompt'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _checkoutInputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFFCFCFD),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AqsColors.primary, width: 1.6),
      ),
    );
  }

  String _formatCheckoutPrice(int amount) {
    if (amount == 0) {
      return 'TZS 0';
    }

    final value = amount.toString();
    final buffer = StringBuffer();

    for (var i = 0; i < value.length; i++) {
      buffer.write(value[i]);

      final remaining = value.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write(',');
      }
    }

    return 'TZS ${buffer.toString()}';
  }
}
