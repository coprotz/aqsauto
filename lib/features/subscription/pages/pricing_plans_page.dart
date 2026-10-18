// import 'package:aqs/features/pricing/data/pricing_plans.dart';
// import 'package:aqs/features/pricing/models/pricing_plan.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';

// class PricingPlansPage extends StatefulWidget {
//   const PricingPlansPage({super.key});

//   @override
//   State<PricingPlansPage> createState() => _PricingPlansPageState();
// }

// class _PricingPlansPageState extends State<PricingPlansPage> {
//   bool yearly = false;

//   String _formatMoney(num value) {
//     if (value == 0) {
//       return 'Free';
//     }

//     final raw = value.round().toString();
//     final buffer = StringBuffer();

//     for (var i = 0; i < raw.length; i++) {
//       final position = raw.length - i;

//       buffer.write(raw[i]);

//       if (position > 1 && position % 3 == 1) {
//         buffer.write(',');
//       }
//     }

//     return 'TZS ${buffer.toString()}';
//   }

//   Future<void> _selectPlan(PricingPlan plan) async {
//     if (plan.id == 'free') {
//       Get.back();
//       return;
//     }

//     final productCode =
//         yearly ? plan.yearlyProductCode : plan.monthlyProductCode;

//     if (productCode == null || productCode.isEmpty) {
//       Get.snackbar(
//         'Plan unavailable',
//         'This subscription option is not currently available.',
//         snackPosition: SnackPosition.BOTTOM,
//       );

//       return;
//     }

//     // =====================================================
//     // KEEP YOUR EXISTING QUICKLIPA / SUBSCRIPTION LOGIC HERE
//     // =====================================================
//     //
//     // Example:
//     //
//     // await controller.subscribe(
//     //   planId: plan.id,
//     //   productCode: productCode,
//     //   billingCycle: yearly ? 'yearly' : 'monthly',
//     // );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF7F8FA),

//       appBar: AppBar(
//         backgroundColor: Colors.white,
//         surfaceTintColor: Colors.white,
//         elevation: 0,
//         title: const Text(
//           'Pricing Plans',
//           style: TextStyle(
//             color: Color(0xFF101828),
//             fontWeight: FontWeight.w900,
//           ),
//         ),
//       ),

//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.fromLTRB(22, 28, 22, 50),
//           child: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 1240),
//               child: Column(
//                 children: [
//                   // =================================================
//                   // HEADER
//                   // =================================================
//                   const Text(
//                     'Choose the plan that fits your work',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(
//                       color: Color(0xFF101828),
//                       fontSize: 34,
//                       fontWeight: FontWeight.w900,
//                       letterSpacing: -1,
//                     ),
//                   ),

//                   const SizedBox(height: 12),

//                   ConstrainedBox(
//                     constraints: BoxConstraints(maxWidth: 700),
//                     child: Text(
//                       'Start free and upgrade when you need more projects, '
//                       'drawings, measurement tools, build-up rates and '
//                       'collaboration features.',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(
//                         color: Color(0xFF667085),
//                         fontSize: 15,
//                         height: 1.5,
//                       ),
//                     ),
//                   ),

//                   const SizedBox(height: 26),

//                   // =================================================
//                   // MONTHLY / YEARLY SWITCH
//                   // =================================================
//                   Container(
//                     padding: const EdgeInsets.all(4),
//                     decoration: BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: const Color(0xFFEAECF0)),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         _BillingPeriodButton(
//                           label: 'Monthly',
//                           selected: !yearly,
//                           onTap: () {
//                             setState(() {
//                               yearly = false;
//                             });
//                           },
//                         ),

//                         _BillingPeriodButton(
//                           label: 'Yearly',
//                           selected: yearly,
//                           badge: 'Save 2 months',
//                           onTap: () {
//                             setState(() {
//                               yearly = true;
//                             });
//                           },
//                         ),
//                       ],
//                     ),
//                   ),

//                   const SizedBox(height: 34),

//                   // =================================================
//                   // PRICING CARDS
//                   // =================================================
//                   LayoutBuilder(
//                     builder: (context, constraints) {
//                       final columns =
//                           constraints.maxWidth < 700
//                               ? 1
//                               : constraints.maxWidth < 1100
//                               ? 2
//                               : 4;

//                       final cardWidth =
//                           (constraints.maxWidth - ((columns - 1) * 16)) /
//                           columns;

//                       return Wrap(
//                         spacing: 16,
//                         runSpacing: 16,
//                         alignment: WrapAlignment.center,
//                         children: [
//                           for (final plan in pricingPlans)
//                             SizedBox(
//                               width: cardWidth,
//                               child: _PricingPlanCard(
//                                 plan: plan,
//                                 yearly: yearly,
//                                 priceText: _formatMoney(
//                                   yearly ? plan.yearlyPrice : plan.monthlyPrice,
//                                 ),
//                                 onSelect: () {
//                                   _selectPlan(plan);
//                                 },
//                               ),
//                             ),
//                         ],
//                       );
//                     },
//                   ),

//                   const SizedBox(height: 26),

//                   const Text(
//                     'Prices are shown in Tanzanian Shillings (TZS).',
//                     style: TextStyle(color: Color(0xFF667085), fontSize: 12),
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

// class _PricingPlanCard extends StatelessWidget {
//   const _PricingPlanCard({
//     required this.plan,
//     required this.yearly,
//     required this.priceText,
//     required this.onSelect,
//   });

//   final PricingPlan plan;
//   final bool yearly;
//   final String priceText;
//   final VoidCallback onSelect;

//   @override
//   Widget build(BuildContext context) {
//     final highlighted = plan.highlight;

//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(
//           color:
//               highlighted ? const Color(0xFF155EEF) : const Color(0xFFEAECF0),
//           width: highlighted ? 2 : 1,
//         ),
//         boxShadow:
//             highlighted
//                 ? const [
//                   BoxShadow(
//                     color: Color(0x18155EEF),
//                     blurRadius: 30,
//                     offset: Offset(0, 14),
//                   ),
//                 ]
//                 : null,
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // =================================================
//           // PLAN NAME + BADGE
//           // =================================================
//           Row(
//             children: [
//               Expanded(
//                 child: Text(
//                   plan.name,
//                   style: const TextStyle(
//                     color: Color(0xFF101828),
//                     fontSize: 22,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),
//               ),

//               if (plan.badge.isNotEmpty)
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 8,
//                     vertical: 4,
//                   ),
//                   decoration: BoxDecoration(
//                     color:
//                         highlighted
//                             ? const Color(0xFFEFF4FF)
//                             : const Color(0xFFF2F4F7),
//                     borderRadius: BorderRadius.circular(999),
//                   ),
//                   child: Text(
//                     plan.badge,
//                     style: TextStyle(
//                       color:
//                           highlighted
//                               ? const Color(0xFF155EEF)
//                               : const Color(0xFF475467),
//                       fontSize: 9,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ),
//             ],
//           ),

//           const SizedBox(height: 18),

//           // =================================================
//           // PRICE
//           // =================================================
//           Text(
//             priceText,
//             style: const TextStyle(
//               color: Color(0xFF101828),
//               fontSize: 27,
//               fontWeight: FontWeight.w900,
//               letterSpacing: -0.7,
//             ),
//           ),

//           if (plan.id != 'free')
//             Text(
//               yearly ? '/ year' : '/ month',
//               style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
//             ),

//           const SizedBox(height: 16),

//           Text(
//             plan.description,
//             style: const TextStyle(
//               color: Color(0xFF667085),
//               fontSize: 13,
//               height: 1.5,
//             ),
//           ),

//           const SizedBox(height: 20),

//           // =================================================
//           // PLAN LIMITS
//           // =================================================
//           _PlanMeta(icon: Icons.folder_outlined, text: plan.projects),

//           _PlanMeta(icon: Icons.image_outlined, text: plan.drawings),

//           _PlanMeta(icon: Icons.person_outline, text: plan.users),

//           // NEW
//           _PlanMeta(icon: Icons.calculate_outlined, text: plan.buildUpRates),

//           const SizedBox(height: 16),

//           const Divider(),

//           const SizedBox(height: 14),

//           // =================================================
//           // FEATURES
//           // =================================================
//           for (final feature in plan.features)
//             Padding(
//               padding: const EdgeInsets.only(bottom: 9),
//               child: Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Icon(
//                     Icons.check_circle_rounded,
//                     size: 17,
//                     color: Color(0xFF12B76A),
//                   ),

//                   const SizedBox(width: 8),

//                   Expanded(
//                     child: Text(
//                       feature,
//                       style: const TextStyle(
//                         color: Color(0xFF475467),
//                         fontSize: 12,
//                         height: 1.4,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//           const SizedBox(height: 18),

//           // =================================================
//           // PLAN BUTTON
//           // =================================================
//           SizedBox(
//             width: double.infinity,
//             child:
//                 highlighted
//                     ? FilledButton(
//                       onPressed: onSelect,
//                       style: FilledButton.styleFrom(
//                         backgroundColor: const Color(0xFF155EEF),
//                         foregroundColor: Colors.white,
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                       ),
//                       child: Text(
//                         plan.id == 'free'
//                             ? 'Start free'
//                             : 'Choose ${plan.name}',
//                       ),
//                     )
//                     : OutlinedButton(
//                       onPressed: onSelect,
//                       style: OutlinedButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                       ),
//                       child: Text(
//                         plan.id == 'free'
//                             ? 'Start free'
//                             : 'Choose ${plan.name}',
//                       ),
//                     ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _PlanMeta extends StatelessWidget {
//   const _PlanMeta({required this.icon, required this.text});

//   final IconData icon;
//   final String text;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 9),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.center,
//         children: [
//           Container(
//             width: 30,
//             height: 30,
//             alignment: Alignment.center,
//             decoration: BoxDecoration(
//               color: const Color(0xFFEFF4FF),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Icon(icon, size: 16, color: const Color(0xFF155EEF)),
//           ),

//           const SizedBox(width: 10),

//           Expanded(
//             child: Text(
//               text,
//               style: const TextStyle(
//                 color: Color(0xFF344054),
//                 fontSize: 12,
//                 fontWeight: FontWeight.w700,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
