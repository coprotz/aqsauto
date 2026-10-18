import 'package:aqs/features/utils/helpers/helpers.dart';

class AdminUserRow {
  const AdminUserRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.provider,
    required this.plan,
    required this.storageBytes,
    required this.ownedProjects,
    required this.sharedProjects,
    required this.buildings,
    required this.drawings,
    required this.measurements,
    required this.boqItems,
    required this.createdAt,
    required this.lastLoginAt,
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final String status;
  final String provider;
  final String plan;
  final int? storageBytes;
  final int ownedProjects;
  final int sharedProjects;
  final int buildings;
  final int drawings;
  final int measurements;
  final int boqItems;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  int get totalProjects => ownedProjects + sharedProjects;

  String get normalizedStatus => status.trim().toLowerCase();

  bool get isActive => normalizedStatus == 'active';

  bool get isSuspended => normalizedStatus == 'suspended';

  bool get isDeleted => normalizedStatus == 'deleted';

  bool get isSubscribed {
    final p = plan.trim().toLowerCase();
    return p.isNotEmpty &&
        p != 'free' &&
        p != 'none' &&
        p != 'not subscribed' &&
        p != 'trial';
  }

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    return 'Unnamed user';
  }

  String get initials {
    final text = displayName.trim();
    if (text.isEmpty) return 'U';
    final parts =
        text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return text.substring(0, 1).toUpperCase();
  }

  String get storageLabel =>
      storageBytes == null || storageBytes == 0
          ? '—'
          : formatBytes(storageBytes!);

  String get lastLoginLabel => formatDate(lastLoginAt ?? createdAt);

  AdminUserRow copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? status,
    String? provider,
    String? plan,
    int? storageBytes,
    int? ownedProjects,
    int? sharedProjects,
    int? buildings,
    int? drawings,
    int? measurements,
    int? boqItems,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return AdminUserRow(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      provider: provider ?? this.provider,
      plan: plan ?? this.plan,
      storageBytes: storageBytes ?? this.storageBytes,
      ownedProjects: ownedProjects ?? this.ownedProjects,
      sharedProjects: sharedProjects ?? this.sharedProjects,
      buildings: buildings ?? this.buildings,
      drawings: drawings ?? this.drawings,
      measurements: measurements ?? this.measurements,
      boqItems: boqItems ?? this.boqItems,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}
