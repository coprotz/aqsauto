import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/dashboards/components/user_avatar_button.dart';
import 'package:aqs/features/profiles/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TopBar extends StatelessWidget {
  final TextEditingController search;
  final VoidCallback onChanged;
  final String title;
  final String subtitle;
  final VoidCallback? onMenuPressed;
  final bool showSearch;

  const TopBar({
    super.key,
    required this.search,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    this.onMenuPressed,
    this.showSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(bottom: const BorderSide(color: AqsColors.border)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onMenuPressed != null) ...[
            IconButton(
              tooltip: 'Open navigation',
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Go to home',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Get.toNamed('/'),
                        child: const AqsLogoMark(size: 30),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          if (showSearch) ...[
            SizedBox(
              width: 320,
              height: 42,
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search projects',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: AqsColors.canvas,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AqsColors.border),
                  ),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Stack(
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          UserAvatarButtonLive(
            radius: 17,
            goToProfile: () => const ProfilePage(),
          ),
        ],
      ),
    );
  }
}
