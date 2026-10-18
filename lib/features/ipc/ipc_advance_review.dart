import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'ipc_dashboard.dart';

class IpcAdvanceReview extends StatelessWidget {
  const IpcAdvanceReview({
    super.key,
    required this.data,
    required this.terms,
    required this.submitButton,
  });
  final Map<String, dynamic> data, terms;
  final Widget submitButton;
  static const navy = Color(0xFF142544);
  static const muted = Color(0xFF6B7A90);
  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE3E9F2)),
    ),
    child: child,
  );
  Widget metric(
    String title,
    String value,
    IconData icon, {
    bool primary = false,
  }) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: primary ? const Color(0xFF1457E8) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: primary ? const Color(0xFF1457E8) : const Color(0xFFE3E9F2),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: primary ? Colors.white : const Color(0xFF1457E8)),
        const SizedBox(height: 20),
        Text(title, style: TextStyle(color: primary ? Colors.white70 : muted)),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              color: primary ? Colors.white : navy,
            ),
          ),
        ),
      ],
    ),
  );
  Widget setting(IconData icon, String title, String value, String detail) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF1457E8), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: const TextStyle(color: muted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    final date = data['ipcDate'];
    final recovery = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recovery & retention',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Applied automatically to future work IPCs',
            style: TextStyle(color: muted),
          ),
          setting(
            Icons.currency_exchange,
            'Advance recovery',
            '${terms['recoveryPercent'] ?? 0}%',
            'Of current-period work, until the advance is fully recovered.',
          ),
          const Divider(height: 1),
          setting(
            Icons.shield_outlined,
            'Retention',
            '${terms['retentionPercent'] ?? 0}%',
            'Of current-period work before deductions.',
          ),
          const Divider(height: 1),
          setting(
            Icons.lock_outline,
            'Retention limit',
            '${terms['retentionLimitPercent'] ?? 0}%',
            'Maximum retention as a percentage of the contract price.',
          ),
        ],
      ),
    );
    final summary = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Payment summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Advance payment rate', style: TextStyle(color: muted)),
          Text(
            '${terms['advancePercent'] ?? 0}%',
            style: const TextStyle(
              fontSize: 30,
              color: navy,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          const Text('Deductions on this IPC', style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          Text(
            ipcMoney(0),
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: Color(0xFF078450),
            ),
          ),
          const Divider(height: 40),
          const Text('Net amount applied', style: TextStyle(color: muted)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ipcMoney(data['amountApplied']),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: navy,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No retention or advance recovery is deducted from this advance payment.',
            style: TextStyle(color: muted, height: 1.5),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PAYMENT CERTIFICATES / PREPARATION',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(
                    'IPC No. ${data['number'] ?? 1} · Advance payment',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.edit_note, size: 18),
                    label: Text('${data['status'] ?? 'draft'}'.toUpperCase()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Review the payment and contract settings before submitting.${date is Timestamp ? '  •  ${DateFormat('dd MMM yyyy').format(date.toDate())}' : ''}',
                style: const TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, c) {
                  final cards = [
                    metric(
                      'Contract price',
                      ipcMoney(terms['contractPrice']),
                      Icons.business_outlined,
                    ),
                    metric(
                      'Advance payment',
                      '${terms['advancePercent'] ?? 0}%',
                      Icons.percent,
                    ),
                    metric(
                      'Amount applied',
                      ipcMoney(data['amountApplied']),
                      Icons.account_balance_wallet_outlined,
                      primary: true,
                    ),
                  ];
                  final columns = c.maxWidth >= 800 ? 3 : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children:
                        cards
                            .map(
                              (card) => SizedBox(
                                width:
                                    (c.maxWidth - (columns - 1) * 16) / columns,
                                child: card,
                              ),
                            )
                            .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder:
                    (context, c) =>
                        c.maxWidth >= 800
                            ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: recovery),
                                const SizedBox(width: 24),
                                Expanded(flex: 2, child: summary),
                              ],
                            )
                            : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                recovery,
                                const SizedBox(height: 20),
                                summary,
                              ],
                            ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF1457E8)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your BOQs and these settings carry forward to the next work IPC. This advance payment does not count as work executed.',
                        style: TextStyle(color: Color(0xFF425C80), height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              panel(
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    const Text(
                      'Ready to submit? Review the figures above.',
                      style: TextStyle(color: muted),
                    ),
                    submitButton,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
