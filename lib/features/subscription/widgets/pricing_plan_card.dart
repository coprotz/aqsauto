// import 'package:aqs/core/theme/aqs_theme.dart';
// import 'package:aqs/features/billing/services/subscription_service.dart';
// import 'package:aqs/features/subscription/dialogs/payment_receipt_dialog.dart';
// import 'package:aqs/features/subscription/dialogs/qucklipa_checkout_dialog.dart';
// import 'package:aqs/features/pricing/models/pricing_plan.dart';
// import 'package:aqs/features/subscription/services/aqs_payment_service.dart';
// import 'package:aqs/features/subscription/widgets/inline_payment.dart';
// import 'package:aqs/features/utils/helpers/helpers.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:cloud_functions/cloud_functions.dart';
// // import 'package:cloud_functions/cloud_functions.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';

// class PricingPlanCard extends StatefulWidget {
//   const PricingPlanCard({
//     super.key,
//     required this.plan,
//     required this.yearly,
//     required this.subscription,
//   });

//   final PricingPlan plan;
//   final bool yearly;
//   final AqsSubscription subscription;

//   @override
//   State<PricingPlanCard> createState() => _PricingPlanCardState();
// }

// class _PricingPlanCardState extends State<PricingPlanCard> {
//   bool _startingCheckout = false;

//   @override
//   Widget build(BuildContext context) {
//     final plan = widget.plan;
//     final subscription = widget.subscription;

//     final displayedProductCode = plan.productCodeFor(yearly: widget.yearly);

//     final displayedCycle = widget.yearly ? 'yearly' : 'monthly';

//     /*
//      * Exact active product.
//      *
//      * Example:
//      * Current = AQS_PRO_MONTHLY
//      * Displayed = AQS_PRO_MONTHLY
//      */
//     final active =
//         plan.id == 'free'
//             ? subscription.isFree
//             : subscription.isActivePaid &&
//                 subscription.productCode.trim().toUpperCase() ==
//                     displayedProductCode.trim().toUpperCase();

//     /*
//      * Same plan, different billing cycle.
//      *
//      * Example:
//      * Current = Pro Monthly
//      * Displayed = Pro Yearly
//      */
//     final samePlanDifferentCycle =
//         plan.id != 'free' &&
//         subscription.isActivePaid &&
//         subscription.plan.name == plan.id.toLowerCase() &&
//         !active;

//     /*
//      * Current user has another paid plan.
//      *
//      * Example:
//      * User currently has Basic
//      * Card displayed = Pro
//      */
//     final differentPaidPlan =
//         plan.id != 'free' &&
//         subscription.isActivePaid &&
//         subscription.plan.name != plan.id.toLowerCase();

//     final currentCycle = subscription.billingCycleLabel.trim().toLowerCase();

//     final amount = plan.priceFor(yearly: widget.yearly);

//     final badgeText = _badgeText(
//       plan: plan,
//       active: active,
//       samePlanDifferentCycle: samePlanDifferentCycle,
//       differentPaidPlan: differentPaidPlan,
//     );

//     final borderColor =
//         active
//             ? const Color(0xFF12B76A)
//             : plan.highlight
//             ? AqsColors.primary
//             : const Color(0xFFE4E7EC);

//     final borderWidth = active || plan.highlight ? 1.6 : 1.0;

//     final cardBackground = active ? const Color(0xFFF6FEF9) : Colors.white;

//     final buttonLabel = _buttonLabel(
//       plan: plan,
//       active: active,
//       samePlanDifferentCycle: samePlanDifferentCycle,
//       differentPaidPlan: differentPaidPlan,
//     );

//     return AnimatedContainer(
//       duration: const Duration(milliseconds: 180),
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: cardBackground,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: borderColor, width: borderWidth),
//         boxShadow: [
//           BoxShadow(
//             color:
//                 active
//                     ? const Color(0x1712B76A)
//                     : plan.highlight
//                     ? const Color(0x1C155EEF)
//                     : const Color(0x08101828),
//             blurRadius: active || plan.highlight ? 24 : 16,
//             offset: const Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           /*
//            * PLAN NAME + BADGE
//            */
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       plan.name,
//                       style: const TextStyle(
//                         color: AqsColors.ink,
//                         fontSize: 21,
//                         fontWeight: FontWeight.w900,
//                       ),
//                     ),

//                     const SizedBox(height: 4),

//                     Text(
//                       plan.id == 'free'
//                           ? 'Free access'
//                           : widget.yearly
//                           ? 'Yearly billing'
//                           : 'Monthly billing',
//                       style: const TextStyle(
//                         color: AqsColors.muted,
//                         fontSize: 11,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(width: 10),

//               _PlanStatusBadge(
//                 plan: plan,
//                 active: active,
//                 samePlanDifferentCycle: samePlanDifferentCycle,
//                 differentPaidPlan: differentPaidPlan,
//                 label: badgeText,
//               ),
//             ],
//           ),

//           const SizedBox(height: 12),

//           /*
//            * DESCRIPTION
//            */
//           Text(
//             plan.description,
//             style: const TextStyle(color: AqsColors.muted, height: 1.45),
//           ),

//           const SizedBox(height: 18),

//           /*
//            * PRICE
//            */
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.end,
//             children: [
//               Expanded(
//                 child: Text(
//                   _formatPrice(amount),
//                   style: const TextStyle(
//                     color: AqsColors.ink,
//                     fontSize: 28,
//                     fontWeight: FontWeight.w900,
//                     letterSpacing: -0.8,
//                   ),
//                 ),
//               ),

//               if (widget.yearly && plan.id != 'free')
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 8,
//                     vertical: 5,
//                   ),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFFECFDF3),
//                     borderRadius: BorderRadius.circular(999),
//                   ),
//                   child: const Text(
//                     '2 months free',
//                     style: TextStyle(
//                       color: Color(0xFF027A48),
//                       fontSize: 9,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ),
//             ],
//           ),

//           const SizedBox(height: 3),

//           Text(
//             plan.id == 'free'
//                 ? 'Free forever'
//                 : widget.yearly
//                 ? 'per year'
//                 : 'per month',
//             style: const TextStyle(
//               color: AqsColors.muted,
//               fontSize: 12,
//               fontWeight: FontWeight.w600,
//             ),
//           ),

//           /*
//            * ACTIVE PLAN INFORMATION
//            */
//           if (active && !subscription.isFree) ...[
//             const SizedBox(height: 12),

//             _CurrentPlanNotice(subscription: subscription),
//           ],

//           /*
//            * SAME PLAN / DIFFERENT CYCLE
//            */
//           if (samePlanDifferentCycle && currentCycle.isNotEmpty) ...[
//             const SizedBox(height: 12),

//             _SwitchBillingNotice(
//               planName: plan.name,
//               currentCycle: currentCycle,
//               displayedCycle: displayedCycle,
//             ),
//           ],

//           /*
//            * OTHER CURRENT PAID PLAN
//            */
//           if (differentPaidPlan) ...[
//             const SizedBox(height: 12),

//             _UpgradePlanNotice(
//               currentPlan: subscription.displayName,
//               targetPlan: plan.name,
//             ),
//           ],

//           const SizedBox(height: 20),

//           /*
//            * LIMITS
//            */
//           _LimitRow(icon: Icons.folder_outlined, text: plan.projects),

//           _LimitRow(icon: Icons.description_outlined, text: plan.drawings),

//           _LimitRow(icon: Icons.group_outlined, text: plan.users),

//           const SizedBox(height: 14),

//           const Divider(height: 1),

//           const SizedBox(height: 14),

//           /*
//            * FEATURES
//            */
//           for (final feature in plan.features)
//             Padding(
//               padding: const EdgeInsets.only(bottom: 9),
//               child: Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Icon(
//                     Icons.check_circle_rounded,
//                     color: Color(0xFF039855),
//                     size: 18,
//                   ),

//                   const SizedBox(width: 8),

//                   Expanded(
//                     child: Text(
//                       feature,
//                       style: const TextStyle(
//                         color: Color(0xFF344054),
//                         fontWeight: FontWeight.w600,
//                         height: 1.35,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//           const SizedBox(height: 10),

//           /*
//            * ACTION BUTTON
//            */
//           SizedBox(
//             width: double.infinity,
//             child: _buildActionButton(
//               context: context,
//               plan: plan,
//               active: active,
//               samePlanDifferentCycle: samePlanDifferentCycle,
//               buttonLabel: buttonLabel,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   String _badgeText({
//     required PricingPlan plan,
//     required bool active,
//     required bool samePlanDifferentCycle,
//     required bool differentPaidPlan,
//   }) {
//     if (active) {
//       return 'Current plan';
//     }

//     if (samePlanDifferentCycle) {
//       return 'Switch billing';
//     }

//     if (differentPaidPlan) {
//       return 'Available';
//     }

//     return plan.badge;
//   }

//   Widget _buildActionButton({
//     required BuildContext context,
//     required PricingPlan plan,
//     required bool active,
//     required bool samePlanDifferentCycle,
//     required String buttonLabel,
//   }) {
//     /*
//      * FREE
//      */
//     if (plan.id == 'free') {
//       return OutlinedButton.icon(
//         onPressed: active ? null : () => _showFreePlan(context),
//         icon: const Icon(Icons.account_circle_outlined),
//         label: Text(active ? 'Current plan' : 'Free plan'),
//       );
//     }

//     /*
//      * EXACT ACTIVE PRODUCT
//      */
//     if (active) {
//       return OutlinedButton.icon(
//         onPressed: null,
//         icon: const Icon(Icons.check_circle_outline_rounded),
//         label: const Text('Current plan'),
//       );
//     }

//     final onPressed =
//         _startingCheckout ? null : () => _startQuickLipaCheckout(context, plan);

//     /*
//      * PRO / HIGHLIGHTED PLAN
//      */
//     if (plan.highlight) {
//       return FilledButton.icon(
//         onPressed: onPressed,
//         icon:
//             _startingCheckout
//                 ? const SizedBox.square(
//                   dimension: 16,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2,
//                     color: Colors.white,
//                   ),
//                 )
//                 : Icon(
//                   samePlanDifferentCycle
//                       ? Icons.swap_horiz_rounded
//                       : Icons.workspace_premium_outlined,
//                 ),
//         label: Text(_startingCheckout ? 'Starting…' : buttonLabel),
//       );
//     }

//     return OutlinedButton.icon(
//       onPressed: onPressed,
//       icon:
//           _startingCheckout
//               ? const SizedBox.square(
//                 dimension: 16,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               )
//               : Icon(
//                 samePlanDifferentCycle
//                     ? Icons.swap_horiz_rounded
//                     : Icons.arrow_forward_rounded,
//               ),
//       label: Text(_startingCheckout ? 'Starting…' : buttonLabel),
//     );
//   }

//   String _buttonLabel({
//     required PricingPlan plan,
//     required bool active,
//     required bool samePlanDifferentCycle,
//     required bool differentPaidPlan,
//   }) {
//     if (active) {
//       return 'Current plan';
//     }

//     if (samePlanDifferentCycle) {
//       return widget.yearly ? 'Switch to yearly' : 'Switch to monthly';
//     }

//     /*
//      * Later, when we implement proper
//      * upgrade/downgrade proration, we can
//      * make this more specific.
//      */
//     if (differentPaidPlan) {
//       return 'Choose ${plan.name}';
//     }

//     return 'Choose ${plan.name}';
//   }

//   String _formatPrice(int amount) {
//     if (amount == 0) {
//       return 'TZS 0';
//     }

//     final value = amount.toString();

//     final buffer = StringBuffer();

//     for (var i = 0; i < value.length; i++) {
//       buffer.write(value[i]);

//       final remaining = value.length - i - 1;

//       if (remaining > 0 && remaining % 3 == 0) {
//         buffer.write(',');
//       }
//     }

//     return 'TZS ${buffer.toString()}';
//   }

//   void _showFreePlan(BuildContext context) {
//     final subscription = widget.subscription;

//     if (subscription.isActivePaid) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(
//             'Your ${subscription.displayName} plan is currently active. '
//             'Free access will apply when there is no active paid subscription.',
//           ),
//         ),
//       );

//       return;
//     }

//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Free access is active automatically.')),
//     );
//   }

//   Future<void> _startQuickLipaCheckout(
//     BuildContext context,
//     PricingPlan plan,
//   ) async {
//     final productCode = plan.productCodeFor(yearly: widget.yearly);

//     if (productCode.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('This plan does not have a valid QuickLipa product.'),
//         ),
//       );

//       return;
//     }

//     final checkout = await showDialog<CheckoutInput>(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (_) => QuickLipaCheckoutDialog(plan: plan, yearly: widget.yearly),
//     );

//     if (checkout == null || !mounted) {
//       return;
//     }

//     setState(() {
//       _startingCheckout = true;
//     });

//     AqsPaymentResult? paymentResult;
//     String? startError;
//     String? startErrorDetails;

//     try {
//       final service = AqsPaymentService();

//       paymentResult = await service.initiatePayment(
//         productCode: productCode,
//         provider: checkout.provider,
//         customerPhone: checkout.phone,
//       );
//     } on FirebaseFunctionsException catch (error) {
//       startError = error.message ?? 'Could not start the QuickLipa payment.';

//       if (error.details is Map) {
//         final details = Map<String, dynamic>.from(error.details as Map);

//         final code = (details['code'] ?? '').toString();

//         final attemptId = (details['attemptId'] ?? '').toString();

//         final applicationReference =
//             (details['applicationReference'] ?? '').toString();

//         final parts = <String>[
//           if (code.isNotEmpty) 'Code: $code',

//           if (attemptId.isNotEmpty) 'Attempt: $attemptId',

//           if (applicationReference.isNotEmpty)
//             'Reference: $applicationReference',
//         ];

//         if (parts.isNotEmpty) {
//           startErrorDetails = parts.join(' • ');
//         }
//       }
//     } catch (error) {
//       debugPrint('QuickLipa checkout error: $error');

//       startError = 'Could not start the payment. Please try again.';
//     } finally {
//       if (mounted) {
//         setState(() {
//           _startingCheckout = false;
//         });
//       }
//     }

//     if (!mounted) {
//       return;
//     }

//     await showDialog<void>(
//       context: context,
//       barrierDismissible: startError != null,
//       builder:
//           (_) => _QuickLipaPaymentStatusDialog(
//             plan: plan,
//             yearly: widget.yearly,
//             paymentResult: paymentResult,
//             startError: startError,
//             startErrorDetails: startErrorDetails,
//           ),
//     );

//     /*
//      * No _loadCurrentPlan() here anymore.
//      *
//      * PricingPlansPage already watches
//      * users/{uid}. Once the backend activates
//      * the subscription, widget.subscription
//      * changes automatically.
//      */
//   }
// }

// class _CurrentPlanNotice extends StatelessWidget {
//   const _CurrentPlanNotice({required this.subscription});

//   final AqsSubscription subscription;

//   @override
//   Widget build(BuildContext context) {
//     final expiry = subscription.expiresAt;

//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(11),
//       decoration: BoxDecoration(
//         color: const Color(0xFFECFDF3),
//         borderRadius: BorderRadius.circular(11),
//         border: Border.all(color: const Color(0xFFA6F4C5)),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(
//             Icons.verified_rounded,
//             size: 18,
//             color: Color(0xFF039855),
//           ),

//           const SizedBox(width: 8),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   '${subscription.displayName} ${subscription.billingCycleLabel} is active',
//                   style: const TextStyle(
//                     color: Color(0xFF027A48),
//                     fontSize: 11,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),

//                 if (expiry != null) ...[
//                   const SizedBox(height: 3),

//                   Text(
//                     'Valid until ${_formatSubscriptionDate(expiry)}',
//                     style: const TextStyle(
//                       color: Color(0xFF05603A),
//                       fontSize: 10,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SwitchBillingNotice extends StatelessWidget {
//   const _SwitchBillingNotice({
//     required this.planName,
//     required this.currentCycle,
//     required this.displayedCycle,
//   });

//   final String planName;
//   final String currentCycle;
//   final String displayedCycle;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(10),
//       decoration: BoxDecoration(
//         color: const Color(0xFFFFFAEB),
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: const Color(0xFFFEDF89)),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(
//             Icons.info_outline_rounded,
//             color: Color(0xFFB54708),
//             size: 17,
//           ),

//           const SizedBox(width: 7),

//           Expanded(
//             child: Text(
//               'Your current $planName plan is billed '
//               '${currentCycle == 'yearly' ? 'yearly' : 'monthly'}. '
//               'Choose this option to switch to '
//               '${displayedCycle == 'yearly' ? 'yearly' : 'monthly'} billing.',
//               style: const TextStyle(
//                 color: Color(0xFF7A2E0E),
//                 fontSize: 11,
//                 height: 1.35,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _UpgradePlanNotice extends StatelessWidget {
//   const _UpgradePlanNotice({
//     required this.currentPlan,
//     required this.targetPlan,
//   });

//   final String currentPlan;
//   final String targetPlan;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(10),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF2F7FF),
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: const Color(0xFFD6E4FF)),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Icon(Icons.upgrade_rounded, color: AqsColors.primary, size: 18),

//           const SizedBox(width: 7),

//           Expanded(
//             child: Text(
//               'Your current plan is $currentPlan. '
//               '$targetPlan is available if you want to change your subscription.',
//               style: const TextStyle(
//                 color: AqsColors.muted,
//                 fontSize: 11,
//                 height: 1.35,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// String _formatSubscriptionDate(DateTime value) {
//   final day = value.day.toString().padLeft(2, '0');

//   final month = value.month.toString().padLeft(2, '0');

//   return '$day/$month/${value.year}';
// }

// class _PlanStatusBadge extends StatelessWidget {
//   const _PlanStatusBadge({
//     required this.plan,
//     required this.active,
//     required this.samePlanDifferentCycle,
//     required this.differentPaidPlan,
//     required this.label,
//   });

//   final PricingPlan plan;
//   final bool active;
//   final bool samePlanDifferentCycle;
//   final bool differentPaidPlan;
//   final String label;

//   @override
//   Widget build(BuildContext context) {
//     Color background;
//     Color foreground;
//     IconData? icon;

//     if (active) {
//       background = const Color(0xFFECFDF3);
//       foreground = const Color(0xFF027A48);
//       icon = Icons.check_circle_rounded;
//     } else if (samePlanDifferentCycle) {
//       background = const Color(0xFFFFF7E6);
//       foreground = const Color(0xFFB54708);
//       icon = Icons.swap_horiz_rounded;
//     } else if (plan.highlight) {
//       background = const Color(0xFFEFF4FF);
//       foreground = AqsColors.primary;
//     } else {
//       background = const Color(0xFFF2F4F7);
//       foreground = const Color(0xFF475467);
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//       decoration: BoxDecoration(
//         color: background,
//         borderRadius: BorderRadius.circular(999),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           if (icon != null) ...[
//             Icon(icon, size: 14, color: foreground),

//             const SizedBox(width: 4),
//           ],

//           Text(
//             label,
//             style: TextStyle(
//               color: foreground,
//               fontSize: 10,
//               fontWeight: FontWeight.w900,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // class PricingPlanCard extends StatefulWidget {
// //   const PricingPlanCard({super.key, required this.plan, required this.yearly});

// //   final PricingPlan plan;
// //   final bool yearly;

// //   @override
// //   State<PricingPlanCard> createState() => _PricingPlanCardState();
// // }

// // class _PricingPlanCardState extends State<PricingPlanCard> {
// //   bool _startingCheckout = false;

// //   String? _currentPlanId;
// //   String? _currentProductCode;
// //   String? _currentBillingCycle;
// //   String? _currentPlanStatus;

// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadCurrentPlan();
// //   }

// //   @override
// //   void didUpdateWidget(covariant PricingPlanCard oldWidget) {
// //     super.didUpdateWidget(oldWidget);

// //     if (oldWidget.yearly != widget.yearly ||
// //         oldWidget.plan.id != widget.plan.id) {
// //       _loadCurrentPlan();
// //     }
// //   }

// //   Future<void> _loadCurrentPlan() async {
// //     final user = FirebaseAuth.instance.currentUser;

// //     if (user == null) {
// //       return;
// //     }

// //     try {
// //       final snap =
// //           await FirebaseFirestore.instance
// //               .collection('users')
// //               .doc(user.uid)
// //               .get();

// //       final data = snap.data() ?? const <String, dynamic>{};

// //       if (!mounted) {
// //         return;
// //       }

// //       setState(() {
// //         _currentPlanId =
// //             (data['subscriptionPlanId'] ?? '').toString().trim().toLowerCase();

// //         _currentProductCode =
// //             (data['subscriptionProductCode'] ?? '')
// //                 .toString()
// //                 .trim()
// //                 .toUpperCase();

// //         _currentBillingCycle =
// //             (data['subscriptionBillingCycle'] ?? '')
// //                 .toString()
// //                 .trim()
// //                 .toLowerCase();

// //         _currentPlanStatus =
// //             (data['subscriptionStatus'] ?? '').toString().trim().toLowerCase();
// //       });
// //     } catch (error) {
// //       debugPrint('Could not load subscription: $error');
// //     }
// //   }

// //   Future<void> _startQuickLipaCheckout(
// //     BuildContext context,
// //     PricingPlan plan,
// //   ) async {
// //     final productCode = plan.productCodeFor(yearly: widget.yearly);

// //     if (productCode.isEmpty) {
// //       ScaffoldMessenger.of(context).showSnackBar(
// //         const SnackBar(
// //           content: Text('This plan does not have a valid QuickLipa product.'),
// //         ),
// //       );
// //       return;
// //     }

// //     final checkout = await showDialog<CheckoutInput>(
// //       context: context,
// //       barrierDismissible: false,
// //       builder:
// //           (_) => QuickLipaCheckoutDialog(plan: plan, yearly: widget.yearly),
// //     );

// //     if (checkout == null || !mounted) {
// //       return;
// //     }

// //     setState(() {
// //       _startingCheckout = true;
// //     });

// //     AqsPaymentResult? paymentResult;
// //     String? startError;
// //     String? startErrorDetails;

// //     try {
// //       final service = AqsPaymentService();

// //       paymentResult = await service.initiatePayment(
// //         productCode: productCode,
// //         provider: checkout.provider,
// //         customerPhone: checkout.phone,
// //       );
// //     } on FirebaseFunctionsException catch (error) {
// //       startError = error.message ?? 'Could not start the QuickLipa payment.';

// //       if (error.details is Map) {
// //         final details = Map<String, dynamic>.from(error.details as Map);

// //         final code = (details['code'] ?? '').toString();

// //         final attemptId = (details['attemptId'] ?? '').toString();

// //         final applicationReference =
// //             (details['applicationReference'] ?? '').toString();

// //         final parts = <String>[
// //           if (code.isNotEmpty) 'Code: $code',
// //           if (attemptId.isNotEmpty) 'Attempt: $attemptId',
// //           if (applicationReference.isNotEmpty)
// //             'Reference: $applicationReference',
// //         ];

// //         if (parts.isNotEmpty) {
// //           startErrorDetails = parts.join(' • ');
// //         }
// //       }
// //     } catch (error) {
// //       debugPrint('QuickLipa checkout error: $error');

// //       startError = 'Could not start the payment. Please try again.';
// //     } finally {
// //       if (mounted) {
// //         setState(() {
// //           _startingCheckout = false;
// //         });
// //       }
// //     }

// //     if (!mounted) {
// //       return;
// //     }

// //     await showDialog<void>(
// //       context: context,
// //       barrierDismissible: startError != null,
// //       builder:
// //           (_) => _QuickLipaPaymentStatusDialog(
// //             plan: plan,
// //             yearly: widget.yearly,
// //             paymentResult: paymentResult,
// //             startError: startError,
// //             startErrorDetails: startErrorDetails,
// //           ),
// //     );

// //     await _loadCurrentPlan();
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     final plan = widget.plan;

// //     final displayedProductCode = plan.productCodeFor(yearly: widget.yearly);

// //     final displayedCycle = widget.yearly ? 'yearly' : 'monthly';

// //     /*
// //      * Exact product match.
// //      *
// //      * Example:
// //      * current = AQS_PRO_MONTHLY
// //      * displayed = AQS_PRO_MONTHLY
// //      * => active = true
// //      */
// //     final active =
// //         plan.id == 'free'
// //             ? _currentPlanStatus != 'active' || (_currentPlanId ?? '').isEmpty
// //             : _currentPlanStatus == 'active' &&
// //                 (_currentProductCode ?? '') == displayedProductCode;

// //     /*
// //      * Same plan, but user is viewing a
// //      * different billing cycle.
// //      *
// //      * Example:
// //      * current plan = Pro Monthly
// //      * displayed = Pro Yearly
// //      */
// //     final samePlanDifferentCycle =
// //         plan.id != 'free' &&
// //         _currentPlanStatus == 'active' &&
// //         _currentPlanId == plan.id &&
// //         !active;

// //     final currentCycle = (_currentBillingCycle ?? '').trim();

// //     final badgeText =
// //         active
// //             ? 'Current plan'
// //             : samePlanDifferentCycle
// //             ? 'Switch billing'
// //             : plan.badge;

// //     final borderColor =
// //         active
// //             ? const Color(0xFF12B76A)
// //             : plan.highlight
// //             ? AqsColors.primary
// //             : const Color(0xFFE4E7EC);

// //     final borderWidth = active || plan.highlight ? 1.6 : 1.0;

// //     final cardBackground = active ? const Color(0xFFF6FEF9) : Colors.white;

// //     final amount = plan.priceFor(yearly: widget.yearly);

// //     final buttonLabel = _buttonLabel(
// //       plan: plan,
// //       active: active,
// //       samePlanDifferentCycle: samePlanDifferentCycle,
// //       currentCycle: currentCycle,
// //     );

// //     return AnimatedContainer(
// //       duration: const Duration(milliseconds: 180),
// //       padding: const EdgeInsets.all(18),
// //       decoration: BoxDecoration(
// //         color: cardBackground,
// //         borderRadius: BorderRadius.circular(18),
// //         border: Border.all(color: borderColor, width: borderWidth),
// //         boxShadow: [
// //           BoxShadow(
// //             color:
// //                 active
// //                     ? const Color(0x1712B76A)
// //                     : plan.highlight
// //                     ? const Color(0x1C155EEF)
// //                     : const Color(0x08101828),
// //             blurRadius: active || plan.highlight ? 24 : 16,
// //             offset: const Offset(0, 10),
// //           ),
// //         ],
// //       ),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.start,
// //         children: [
// //           /*
// //            * PLAN NAME + BADGE
// //            */
// //           Row(
// //             crossAxisAlignment: CrossAxisAlignment.start,
// //             children: [
// //               Expanded(
// //                 child: Column(
// //                   crossAxisAlignment: CrossAxisAlignment.start,
// //                   children: [
// //                     Text(
// //                       plan.name,
// //                       style: const TextStyle(
// //                         color: AqsColors.ink,
// //                         fontSize: 21,
// //                         fontWeight: FontWeight.w900,
// //                       ),
// //                     ),

// //                     const SizedBox(height: 4),

// //                     Text(
// //                       widget.yearly ? 'Yearly billing' : 'Monthly billing',
// //                       style: const TextStyle(
// //                         color: AqsColors.muted,
// //                         fontSize: 11,
// //                         fontWeight: FontWeight.w700,
// //                       ),
// //                     ),
// //                   ],
// //                 ),
// //               ),

// //               const SizedBox(width: 10),

// //               Container(
// //                 padding: const EdgeInsets.symmetric(
// //                   horizontal: 10,
// //                   vertical: 6,
// //                 ),
// //                 decoration: BoxDecoration(
// //                   color:
// //                       active
// //                           ? const Color(0xFFECFDF3)
// //                           : samePlanDifferentCycle
// //                           ? const Color(0xFFFFF7E6)
// //                           : plan.highlight
// //                           ? const Color(0xFFEFF4FF)
// //                           : const Color(0xFFF2F4F7),
// //                   borderRadius: BorderRadius.circular(999),
// //                 ),
// //                 child: Row(
// //                   mainAxisSize: MainAxisSize.min,
// //                   children: [
// //                     if (active) ...[
// //                       const Icon(
// //                         Icons.check_circle_rounded,
// //                         color: Color(0xFF027A48),
// //                         size: 14,
// //                       ),
// //                       const SizedBox(width: 4),
// //                     ],

// //                     Text(
// //                       badgeText,
// //                       style: TextStyle(
// //                         color:
// //                             active
// //                                 ? const Color(0xFF027A48)
// //                                 : samePlanDifferentCycle
// //                                 ? const Color(0xFFB54708)
// //                                 : plan.highlight
// //                                 ? AqsColors.primary
// //                                 : const Color(0xFF475467),
// //                         fontSize: 10,
// //                         fontWeight: FontWeight.w900,
// //                       ),
// //                     ),
// //                   ],
// //                 ),
// //               ),
// //             ],
// //           ),

// //           const SizedBox(height: 12),

// //           Text(
// //             plan.description,
// //             style: const TextStyle(color: AqsColors.muted, height: 1.45),
// //           ),

// //           const SizedBox(height: 18),

// //           /*
// //            * PRICE
// //            */
// //           Row(
// //             crossAxisAlignment: CrossAxisAlignment.end,
// //             children: [
// //               Expanded(
// //                 child: Text(
// //                   _formatPrice(amount),
// //                   style: const TextStyle(
// //                     color: AqsColors.ink,
// //                     fontSize: 28,
// //                     fontWeight: FontWeight.w900,
// //                     letterSpacing: -0.8,
// //                   ),
// //                 ),
// //               ),

// //               if (widget.yearly && plan.id != 'free')
// //                 Container(
// //                   padding: const EdgeInsets.symmetric(
// //                     horizontal: 8,
// //                     vertical: 5,
// //                   ),
// //                   decoration: BoxDecoration(
// //                     color: const Color(0xFFECFDF3),
// //                     borderRadius: BorderRadius.circular(999),
// //                   ),
// //                   child: const Text(
// //                     '2 months free',
// //                     style: TextStyle(
// //                       color: Color(0xFF027A48),
// //                       fontSize: 9,
// //                       fontWeight: FontWeight.w900,
// //                     ),
// //                   ),
// //                 ),
// //             ],
// //           ),

// //           const SizedBox(height: 3),

// //           Text(
// //             plan.id == 'free'
// //                 ? 'Free forever'
// //                 : widget.yearly
// //                 ? 'per year'
// //                 : 'per month',
// //             style: const TextStyle(
// //               color: AqsColors.muted,
// //               fontSize: 12,
// //               fontWeight: FontWeight.w600,
// //             ),
// //           ),

// //           if (samePlanDifferentCycle && currentCycle.isNotEmpty) ...[
// //             const SizedBox(height: 10),

// //             Container(
// //               width: double.infinity,
// //               padding: const EdgeInsets.all(10),
// //               decoration: BoxDecoration(
// //                 color: const Color(0xFFFFFAEB),
// //                 borderRadius: BorderRadius.circular(10),
// //                 border: Border.all(color: const Color(0xFFFEDF89)),
// //               ),
// //               child: Row(
// //                 crossAxisAlignment: CrossAxisAlignment.start,
// //                 children: [
// //                   const Icon(
// //                     Icons.info_outline_rounded,
// //                     color: Color(0xFFB54708),
// //                     size: 17,
// //                   ),

// //                   const SizedBox(width: 7),

// //                   Expanded(
// //                     child: Text(
// //                       'Your current ${plan.name} plan is billed '
// //                       '${currentCycle == 'yearly' ? 'yearly' : 'monthly'}. '
// //                       'You can switch to ${displayedCycle == 'yearly' ? 'yearly' : 'monthly'} billing.',
// //                       style: const TextStyle(
// //                         color: Color(0xFF7A2E0E),
// //                         fontSize: 11,
// //                         height: 1.35,
// //                         fontWeight: FontWeight.w600,
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ],

// //           const SizedBox(height: 20),

// //           /*
// //            * LIMITS
// //            */
// //           _LimitRow(icon: Icons.folder_outlined, text: plan.projects),

// //           _LimitRow(icon: Icons.description_outlined, text: plan.drawings),

// //           _LimitRow(icon: Icons.group_outlined, text: plan.users),

// //           const SizedBox(height: 14),

// //           const Divider(height: 1),

// //           const SizedBox(height: 14),

// //           /*
// //            * FEATURES
// //            */
// //           for (final feature in plan.features)
// //             Padding(
// //               padding: const EdgeInsets.only(bottom: 9),
// //               child: Row(
// //                 crossAxisAlignment: CrossAxisAlignment.start,
// //                 children: [
// //                   const Icon(
// //                     Icons.check_circle_rounded,
// //                     color: Color(0xFF039855),
// //                     size: 18,
// //                   ),

// //                   const SizedBox(width: 8),

// //                   Expanded(
// //                     child: Text(
// //                       feature,
// //                       style: const TextStyle(
// //                         color: Color(0xFF344054),
// //                         fontWeight: FontWeight.w600,
// //                         height: 1.35,
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),

// //           const SizedBox(height: 10),

// //           /*
// //            * ACTION
// //            */
// //           SizedBox(
// //             width: double.infinity,
// //             child: _buildActionButton(
// //               context: context,
// //               plan: plan,
// //               active: active,
// //               samePlanDifferentCycle: samePlanDifferentCycle,
// //               buttonLabel: buttonLabel,
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }

// //   Widget _buildActionButton({
// //     required BuildContext context,
// //     required PricingPlan plan,
// //     required bool active,
// //     required bool samePlanDifferentCycle,
// //     required String buttonLabel,
// //   }) {
// //     /*
// //      * FREE
// //      */
// //     if (plan.id == 'free') {
// //       return OutlinedButton.icon(
// //         onPressed: active ? null : () => _showFreePlan(context),
// //         icon: const Icon(Icons.account_circle_outlined),
// //         label: Text(active ? 'Current plan' : 'Free plan'),
// //       );
// //     }

// //     /*
// //      * ACTIVE EXACT PRODUCT
// //      */
// //     if (active) {
// //       return OutlinedButton.icon(
// //         onPressed: null,
// //         icon: const Icon(Icons.check_circle_outline_rounded),
// //         label: const Text('Current plan'),
// //       );
// //     }

// //     final onPressed =
// //         _startingCheckout ? null : () => _startQuickLipaCheckout(context, plan);

// //     /*
// //      * Highlight Pro / preferred plan.
// //      */
// //     if (plan.highlight) {
// //       return FilledButton.icon(
// //         onPressed: onPressed,
// //         icon:
// //             _startingCheckout
// //                 ? const SizedBox.square(
// //                   dimension: 16,
// //                   child: CircularProgressIndicator(
// //                     strokeWidth: 2,
// //                     color: Colors.white,
// //                   ),
// //                 )
// //                 : Icon(
// //                   samePlanDifferentCycle
// //                       ? Icons.swap_horiz_rounded
// //                       : Icons.workspace_premium_outlined,
// //                 ),
// //         label: Text(_startingCheckout ? 'Starting…' : buttonLabel),
// //       );
// //     }

// //     return OutlinedButton.icon(
// //       onPressed: onPressed,
// //       icon:
// //           _startingCheckout
// //               ? const SizedBox.square(
// //                 dimension: 16,
// //                 child: CircularProgressIndicator(strokeWidth: 2),
// //               )
// //               : Icon(
// //                 samePlanDifferentCycle
// //                     ? Icons.swap_horiz_rounded
// //                     : Icons.arrow_forward_rounded,
// //               ),
// //       label: Text(_startingCheckout ? 'Starting…' : buttonLabel),
// //     );
// //   }

// //   String _buttonLabel({
// //     required PricingPlan plan,
// //     required bool active,
// //     required bool samePlanDifferentCycle,
// //     required String currentCycle,
// //   }) {
// //     if (active) {
// //       return 'Current plan';
// //     }

// //     if (samePlanDifferentCycle) {
// //       return widget.yearly ? 'Switch to yearly' : 'Switch to monthly';
// //     }

// //     return 'Choose ${plan.name}';
// //   }

// //   String _formatPrice(int amount) {
// //     if (amount == 0) {
// //       return 'TZS 0';
// //     }

// //     final value = amount.toString();

// //     final buffer = StringBuffer();

// //     for (var i = 0; i < value.length; i++) {
// //       buffer.write(value[i]);

// //       final remaining = value.length - i - 1;

// //       if (remaining > 0 && remaining % 3 == 0) {
// //         buffer.write(',');
// //       }
// //     }

// //     return 'TZS ${buffer.toString()}';
// //   }

// //   void _showFreePlan(BuildContext context) {
// //     ScaffoldMessenger.of(context).showSnackBar(
// //       const SnackBar(
// //         content: Text(
// //           'Free access is available automatically when there is no active paid subscription.',
// //         ),
// //       ),
// //     );
// //   }
// // }

// class _QuickLipaPaymentStatusDialog extends StatelessWidget {
//   const _QuickLipaPaymentStatusDialog({
//     required this.plan,
//     required this.yearly,
//     required this.paymentResult,
//     required this.startError,
//     required this.startErrorDetails,
//   });

//   final PricingPlan plan;
//   final bool yearly;

//   final AqsPaymentResult? paymentResult;

//   final String? startError;
//   final String? startErrorDetails;

//   @override
//   Widget build(BuildContext context) {
//     Future<void> _openReceipt(
//       BuildContext context,
//       AqsPaymentResult result,
//     ) async {
//       if (!context.mounted) {
//         return;
//       }

//       await showDialog<void>(
//         context: context,
//         barrierDismissible: true,
//         builder: (dialogContext) {
//           return PaymentReceiptDialog(
//             result: result,
//             plan: plan,
//             yearly: yearly,
//           );
//         },
//       );
//     }

//     if (startError != null || paymentResult == null) {
//       return _PaymentStatusShell(
//         plan: plan,
//         yearly: yearly,
//         icon: Icons.error_outline_rounded,
//         iconColor: const Color(0xFFD92D20),
//         title: 'Payment request failed',
//         subtitle: startError ?? 'The payment could not be started.',
//         primaryLabel: 'Close',
//         child: InlinePaymentNotice(
//           tone: PaymentNoticeTone.error,
//           title: 'QuickLipa error',
//           message: [
//             startError ?? 'Try again or use another phone/provider.',
//             if ((startErrorDetails ?? '').isNotEmpty) startErrorDetails!,
//           ].join('\n'),
//         ),
//       );
//     }

//     final result = paymentResult!;

//     /*
//      * QuickLipa may already return success
//      * synchronously.
//      */
//     if (result.isSuccessful) {
//       return _PaymentStatusShell(
//         plan: plan,
//         yearly: yearly,
//         icon: Icons.check_circle_outline_rounded,
//         iconColor: const Color(0xFF039855),
//         title: 'Payment successful',
//         subtitle: '${plan.name} is now active on your AQS account.',
//         primaryLabel: 'OK',
//         primaryIcon: Icons.check_rounded,
//         onPrimaryPressed: () {
//           Navigator.of(context).pop();
//         },
//         secondaryLabel: 'View / Print receipt',
//         secondaryIcon: Icons.receipt_long_outlined,
//         onSecondaryPressed: () {
//           _openReceipt(context, result);
//         },
//         child: Container(
//           padding: const EdgeInsets.all(16),
//           decoration: BoxDecoration(
//             color: const Color(0xFFECFDF3),
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(color: const Color(0xFFA6F4C5)),
//           ),
//           child: const Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Icon(
//                 Icons.check_circle_outline_rounded,
//                 color: Color(0xFF039855),
//               ),
//               SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Payment confirmed',
//                       style: TextStyle(
//                         color: Color(0xFF039855),
//                         fontWeight: FontWeight.w900,
//                       ),
//                     ),
//                     SizedBox(height: 4),
//                     Text(
//                       'QuickLipa confirmed the payment successfully.',
//                       style: TextStyle(
//                         color: AqsColors.muted,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     /*
//      * Otherwise watch the AQS user document.
//      *
//      * The backend webhook activates the subscription
//      * and writes subscriptionProductCode here.
//      */
//     final user = FirebaseAuth.instance.currentUser;

//     if (user == null) {
//       return _PaymentStatusShell(
//         plan: plan,
//         yearly: yearly,
//         icon: Icons.error_outline_rounded,
//         iconColor: const Color(0xFFD92D20),
//         title: 'Session unavailable',
//         subtitle: 'Please sign in again to continue.',
//         child: const SizedBox.shrink(),
//         primaryLabel: 'Close',
//       );
//     }

//     final expectedProductCode = plan.productCodeFor(yearly: yearly);

//     return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
//       stream:
//           FirebaseFirestore.instance
//               .collection('users')
//               .doc(user.uid)
//               .snapshots(),

//       builder: (context, snapshot) {
//         final data = snapshot.data?.data() ?? const <String, dynamic>{};

//         final status =
//             (data['subscriptionStatus'] ?? '').toString().trim().toLowerCase();

//         final productCode =
//             (data['subscriptionProductCode'] ?? '')
//                 .toString()
//                 .trim()
//                 .toUpperCase();

//         final activated =
//             status == 'active' && productCode == expectedProductCode;

//         if (activated) {
//           return _PaymentStatusShell(
//             plan: plan,
//             yearly: yearly,
//             icon: Icons.check_circle_outline_rounded,
//             iconColor: const Color(0xFF039855),
//             title: 'Subscription active',
//             subtitle:
//                 '${plan.name} ${yearly ? 'Yearly' : 'Monthly'} is now active.',
//             primaryLabel: 'Done',
//             child: InlinePaymentNotice(
//               tone: PaymentNoticeTone.success,
//               title: 'AQS upgraded',
//               message: 'Your paid tools and plan limits are now available.',
//             ),
//           );
//         }

//         return _PaymentStatusShell(
//           plan: plan,
//           yearly: yearly,
//           icon: Icons.phone_android_rounded,
//           iconColor: AqsColors.primary,
//           title: 'Waiting for payment confirmation',
//           subtitle:
//               'Approve the mobile money prompt on your phone. '
//               'This window will update automatically after QuickLipa confirms the payment.',
//           primaryLabel: 'Close',
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const LinearProgressIndicator(minHeight: 6),

//               const SizedBox(height: 14),

//               InlinePaymentNotice(
//                 tone: PaymentNoticeTone.info,
//                 title: 'Payment request sent',
//                 message: _paymentWaitingMessage(result),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   String _paymentWaitingMessage(AqsPaymentResult result) {
//     final parts = <String>[
//       if (result.applicationReference.isNotEmpty)
//         'Reference ${result.applicationReference}',
//       if (result.status.isNotEmpty) 'Status ${result.status}',
//       if (result.provider.isNotEmpty) 'Provider ${result.provider}',
//     ];

//     if (parts.isEmpty) {
//       return 'Waiting for QuickLipa payment confirmation.';
//     }

//     return '${parts.join(' • ')}. Keep this window open while we wait for confirmation.';
//   }
// }

// class _LimitRow extends StatelessWidget {
//   const _LimitRow({required this.icon, required this.text});

//   final IconData icon;
//   final String text;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 9),
//       child: Row(
//         children: [
//           Icon(icon, size: 18, color: AqsColors.primary),
//           const SizedBox(width: 8),
//           Expanded(
//             child: Text(
//               text,
//               style: const TextStyle(
//                 color: AqsColors.ink,
//                 fontWeight: FontWeight.w800,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _PaymentStatusShell extends StatelessWidget {
//   const _PaymentStatusShell({
//     required this.plan,
//     required this.yearly,
//     required this.icon,
//     required this.iconColor,
//     required this.title,
//     required this.subtitle,
//     required this.child,
//     required this.primaryLabel,
//     this.onPrimaryPressed,
//     this.secondaryLabel,
//     this.onSecondaryPressed,
//     this.primaryIcon,
//     this.secondaryIcon,
//   });

//   final PricingPlan plan;

//   final bool yearly;

//   final IconData icon;
//   final Color iconColor;

//   final String title;
//   final String subtitle;

//   final Widget child;

//   final String primaryLabel;
//   final VoidCallback? onPrimaryPressed;

//   final String? secondaryLabel;
//   final VoidCallback? onSecondaryPressed;

//   final IconData? primaryIcon;
//   final IconData? secondaryIcon;

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
//       backgroundColor: Colors.transparent,
//       child: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 500),
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(26),
//           child: Material(
//             color: Colors.white,
//             child: Padding(
//               padding: const EdgeInsets.all(24),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 crossAxisAlignment: CrossAxisAlignment.stretch,
//                 children: [
//                   Row(
//                     children: [
//                       Container(
//                         width: 52,
//                         height: 52,
//                         decoration: BoxDecoration(
//                           color: iconColor.withOpacity(0.10),
//                           borderRadius: BorderRadius.circular(18),
//                         ),
//                         child: Icon(icon, color: iconColor, size: 28),
//                       ),
//                       const SizedBox(width: 14),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               title,
//                               style: const TextStyle(
//                                 color: AqsColors.ink,
//                                 fontSize: 22,
//                                 fontWeight: FontWeight.w900,
//                                 letterSpacing: -0.4,
//                               ),
//                             ),
//                             const SizedBox(height: 4),
//                             Text(
//                               '${plan.name} • ${yearly ? 'Yearly' : 'Monthly'}',
//                               style: const TextStyle(
//                                 color: AqsColors.primary,
//                                 fontWeight: FontWeight.w800,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),

//                   const SizedBox(height: 16),

//                   Text(
//                     subtitle,
//                     style: const TextStyle(
//                       color: AqsColors.muted,
//                       height: 1.45,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),

//                   const SizedBox(height: 18),

//                   child,

//                   const SizedBox(height: 22),

//                   LayoutBuilder(
//                     builder: (context, constraints) {
//                       final hasSecondary =
//                           secondaryLabel != null &&
//                           secondaryLabel!.trim().isNotEmpty &&
//                           onSecondaryPressed != null;

//                       final compact = constraints.maxWidth < 420;

//                       if (hasSecondary && compact) {
//                         return Column(
//                           crossAxisAlignment: CrossAxisAlignment.stretch,
//                           children: [
//                             FilledButton.icon(
//                               onPressed: onSecondaryPressed,
//                               icon: Icon(
//                                 secondaryIcon ?? Icons.receipt_long_outlined,
//                               ),
//                               label: Text(secondaryLabel!),
//                               style: FilledButton.styleFrom(
//                                 minimumSize: const Size.fromHeight(50),
//                                 backgroundColor: AqsColors.primary,
//                                 foregroundColor: Colors.white,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(14),
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(height: 10),
//                             OutlinedButton.icon(
//                               onPressed:
//                                   onPrimaryPressed ??
//                                   () {
//                                     Navigator.of(context).pop();
//                                   },
//                               icon: Icon(primaryIcon ?? Icons.check_rounded),
//                               label: Text(primaryLabel),
//                               style: OutlinedButton.styleFrom(
//                                 minimumSize: const Size.fromHeight(50),
//                                 foregroundColor: AqsColors.ink,
//                                 side: const BorderSide(
//                                   color: Color(0xFFD0D5DD),
//                                 ),
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(14),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         );
//                       }

//                       if (hasSecondary) {
//                         return Row(
//                           children: [
//                             Expanded(
//                               child: OutlinedButton.icon(
//                                 onPressed:
//                                     onPrimaryPressed ??
//                                     () {
//                                       Navigator.of(context).pop();
//                                     },
//                                 icon: Icon(primaryIcon ?? Icons.check_rounded),
//                                 label: Text(primaryLabel),
//                                 style: OutlinedButton.styleFrom(
//                                   minimumSize: const Size.fromHeight(50),
//                                   foregroundColor: AqsColors.ink,
//                                   side: const BorderSide(
//                                     color: Color(0xFFD0D5DD),
//                                   ),
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(14),
//                                   ),
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: FilledButton.icon(
//                                 onPressed: onSecondaryPressed,
//                                 icon: Icon(
//                                   secondaryIcon ?? Icons.receipt_long_outlined,
//                                 ),
//                                 label: Text(secondaryLabel!),
//                                 style: FilledButton.styleFrom(
//                                   minimumSize: const Size.fromHeight(50),
//                                   backgroundColor: AqsColors.primary,
//                                   foregroundColor: Colors.white,
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(14),
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         );
//                       }

//                       return FilledButton.icon(
//                         onPressed:
//                             onPrimaryPressed ??
//                             () {
//                               Navigator.of(context).pop();
//                             },
//                         icon: Icon(primaryIcon ?? Icons.check_rounded),
//                         label: Text(primaryLabel),
//                         style: FilledButton.styleFrom(
//                           minimumSize: const Size.fromHeight(50),
//                           backgroundColor: AqsColors.primary,
//                           foregroundColor: Colors.white,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(14),
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
