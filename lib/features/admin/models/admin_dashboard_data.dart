import 'package:aqs/features/admin/models/admin_models.dart';
import 'package:aqs/features/admin/models/admin_user_row.dart';
import 'package:aqs/features/admin/models/contact_message_row.dart';

class AdminDashboardData {
  const AdminDashboardData({
    required this.users,
    required this.projectCount,
    required this.clientCount,
    required this.inviteCount,
    required this.workspaceMemberCount,
    required this.totalStorageBytes,
    required this.contactMessages,
    required this.subscriptionPayments,
  });

  factory AdminDashboardData.empty() => const AdminDashboardData(
    users: [],
    projectCount: 0,
    clientCount: 0,
    inviteCount: 0,
    workspaceMemberCount: 0,
    totalStorageBytes: 0,
    contactMessages: [],
    subscriptionPayments: [],
  );

  final List<AdminUserRow> users;
  final int projectCount;
  final int clientCount;
  final int inviteCount;
  final int workspaceMemberCount;
  final int totalStorageBytes;
  final List<ContactMessageRow> contactMessages;
  final List<SubscriptionPaymentRow> subscriptionPayments;

  int get activeUsers =>
      users.where((user) => user.status.toLowerCase() == 'active').length;

  int get subscribedUsers => users.where((user) => user.isSubscribed).length;

  int get adminUsers =>
      users.where((user) {
        final role = user.role.toLowerCase();
        return role == 'admin' || role == 'owner';
      }).length;

  int get newContactMessages =>
      contactMessages
          .where((message) => message.status.toLowerCase() == 'new')
          .length;

  int get successfulSubscriptionPayments =>
      subscriptionPayments.where((payment) => payment.isSuccessful).length;

  int get failedSubscriptionPayments =>
      subscriptionPayments.where((payment) => payment.isFailed).length;

  int get pendingSubscriptionPayments =>
      subscriptionPayments.where((payment) => payment.isPending).length;

  int get delayedSubscriptionPayments =>
      subscriptionPayments.where((payment) => payment.isDelayed).length;

  int get subscriptionAttempts => subscriptionPayments.fold<int>(
    0,
    (sum, payment) => sum + payment.attemptCount,
  );

  int get successfulSubscriptionAttempts => subscriptionPayments.fold<int>(
    0,
    (sum, payment) => sum + payment.successAttempts,
  );

  int get failedSubscriptionAttempts => subscriptionPayments.fold<int>(
    0,
    (sum, payment) => sum + payment.failedAttempts,
  );

  double get subscriptionSuccessRate =>
      subscriptionPayments.isEmpty
          ? 0
          : successfulSubscriptionPayments / subscriptionPayments.length * 100;

  double get subscriptionFailureRate =>
      subscriptionPayments.isEmpty
          ? 0
          : failedSubscriptionPayments / subscriptionPayments.length * 100;

  double get subscriptionDelayRate =>
      subscriptionPayments.isEmpty
          ? 0
          : delayedSubscriptionPayments / subscriptionPayments.length * 100;

  num get subscriptionRevenue => subscriptionPayments.fold<num>(
    0,
    (sum, payment) => payment.isSuccessful ? sum + (payment.amount ?? 0) : sum,
  );

  Duration? get averagePaymentDelay {
    final delays =
        subscriptionPayments
            .map((payment) => payment.delay)
            .whereType<Duration>()
            .toList();
    if (delays.isEmpty) return null;
    final totalMilliseconds = delays.fold<int>(
      0,
      (sum, delay) => sum + delay.inMilliseconds,
    );
    return Duration(milliseconds: totalMilliseconds ~/ delays.length);
  }

  List<AdminUserRow> filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return users;
    return users.where((user) {
      return user.name.toLowerCase().contains(q) ||
          user.email.toLowerCase().contains(q) ||
          user.role.toLowerCase().contains(q) ||
          user.status.toLowerCase().contains(q) ||
          user.plan.toLowerCase().contains(q) ||
          user.provider.toLowerCase().contains(q) ||
          user.totalProjects.toString().contains(q) ||
          user.buildings.toString().contains(q) ||
          user.drawings.toString().contains(q) ||
          user.measurements.toString().contains(q) ||
          user.boqItems.toString().contains(q);
    }).toList();
  }
}
