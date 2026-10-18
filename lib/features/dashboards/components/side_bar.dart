import 'package:aqs/app_routes.dart';
import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/core/widgets/aqs_brand.dart';
import 'package:aqs/features/dashboards/components/nav_item.dart';
import 'package:aqs/features/profiles/profile_page.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Sidebar extends StatelessWidget {
  final User user;
  final bool collapsed;
  final VoidCallback? onNavigate;

  const Sidebar({
    super.key,
    required this.user,
    this.collapsed = false,
    this.onNavigate,
  });

  void _select(int index) {
    selectedNav.value = index;
    onNavigate?.call();
  }

  String get _displayName {
    final name = (user.displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    final email = (user.email ?? '').trim();
    return email.isEmpty ? 'QS Smart user' : email.split('@').first;
  }

  Future<bool> _isClaimAdmin() async {
    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? {};
      return claims['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 88 : 252,
      decoration: BoxDecoration(
        color: AqsColors.primaryDark,
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            collapsed ? 14 : 16,
            16,
            collapsed ? 14 : 16,
            14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Get.offAllNamed(AppRoutes.landing),
                child: SizedBox(
                  child: Align(
                    alignment:
                        collapsed ? Alignment.center : Alignment.centerLeft,
                    child: AqsBrand(
                      compact: collapsed,
                      onDark: true,
                      markSize: 38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (!collapsed) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'WORKSPACE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF84ADFF),
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: selectedNav,
                  builder: (context, idx, _) {
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        NavItem(
                          icon: Icons.dashboard_outlined,
                          label: 'Dashboard',
                          selected: idx == 0,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(0),
                        ),
                        NavItem(
                          icon: Icons.folder_outlined,
                          label: 'Projects',
                          selected: idx == 1,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(1),
                        ),
                        NavItem(
                          icon: Icons.business_outlined,
                          label: 'Clients',
                          selected: idx == 2,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(2),
                        ),
                        NavItem(
                          icon: Icons.groups_outlined,
                          label: 'Team',
                          selected: idx == 3,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(3),
                        ),
                        NavItem(
                          icon: Icons.view_quilt_outlined,
                          label: 'BOQ Templates',
                          selected: idx == 4,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(4),
                        ),
                        NavItem(
                          icon: Icons.bar_chart_outlined,
                          label: 'Reports',
                          selected: idx == 5,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(5),
                        ),
                        NavItem(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & support',
                          selected: idx == 6,
                          collapsed: collapsed,
                          onDark: true,
                          onTap: () => _select(6),
                        ),
                        FutureBuilder<bool>(
                          future: _isClaimAdmin(),
                          builder: (context, snapshot) {
                            final isAdmin = snapshot.data == true;
                            if (!isAdmin) {
                              if (idx == 7 || idx == 8) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (selectedNav.value == 7 ||
                                      selectedNav.value == 8) {
                                    selectedNav.value = 0;
                                  }
                                });
                              }
                              return const SizedBox.shrink();
                            }

                            return NavItem(
                              icon: Icons.admin_panel_settings_outlined,
                              label: 'Admin',
                              selected: idx == 7,
                              collapsed: collapsed,
                              onDark: true,
                              onTap: () => _select(7),
                            );
                          },
                        ),
                        FutureBuilder<bool>(
                          future: _isClaimAdmin(),
                          builder: (context, snapshot) {
                            final isAdmin = snapshot.data == true;
                            if (!isAdmin) return const SizedBox.shrink();

                            return NavItem(
                              icon: Icons.video_library_outlined,
                              label: 'Tutorial videos',
                              selected: idx == 8,
                              collapsed: collapsed,
                              onDark: true,
                              onTap: () => _select(8),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              NavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                selected: false,
                collapsed: collapsed,
                onDark: true,
                onTap: () {},
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.white.withOpacity(0.10)),
              const SizedBox(height: 8),
              if (collapsed)
                Tooltip(
                  message: 'Sign out',
                  child: IconButton(
                    onPressed: FirebaseAuth.instance.signOut,
                    color: const Color(0xFFBFD2FA),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                )
              else
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfilePage()),
                      ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white.withOpacity(0.12),
                          child: Text(
                            _displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                user.email ?? 'Quantity surveyor',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFBFD2FA),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: Colors.white,
                          tooltip: 'Account',
                          onSelected: (value) {
                            if (value == 'sign-out') {
                              FirebaseAuth.instance.signOut();
                            }
                          },
                          itemBuilder:
                              (_) => const [
                                PopupMenuItem(
                                  value: 'sign-out',
                                  child: Row(
                                    children: [
                                      Icon(Icons.logout_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('Sign out'),
                                    ],
                                  ),
                                ),
                              ],
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: Color(0xFFBFD2FA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
