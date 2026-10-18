import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserAvatarButtonLive extends StatelessWidget {
  final double radius;
  final Widget Function() goToProfile;

  const UserAvatarButtonLive({
    super.key,
    this.radius = 16,
    required this.goToProfile,
  });

  String _initials(User? u) {
    final name = (u?.displayName ?? '').trim();
    if (name.isNotEmpty) {
      final parts =
          name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
          .toUpperCase();
    }
    final email = (u?.email ?? '').trim();
    if (email.isNotEmpty) return email.substring(0, 1).toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(), // ✅ live updates
      builder: (context, snap) {
        final u = snap.data ?? FirebaseAuth.instance.currentUser;
        final photo = (u?.photoURL ?? '').trim();

        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => goToProfile()),
            );
          },
          child: CircleAvatar(
            radius: radius,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child:
                photo.isNotEmpty
                    ? null
                    : Text(
                      _initials(u),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: radius,
                      ),
                    ),
          ),
        );
      },
    );
  }
}
