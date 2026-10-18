import 'package:flutter/material.dart';
import 'package:aqs/core/theme/aqs_theme.dart';

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? badgeText;
  final VoidCallback onTap;
  final bool collapsed;
  final bool onDark;

  const NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeText,
    this.collapsed = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: collapsed ? label : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color:
                  selected
                      ? (onDark
                          ? Colors.white.withOpacity(0.12)
                          : cs.primary.withOpacity(0.10))
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: selected ? cs.primary : Colors.transparent,
                ),
              ),
            ),
            child:
                collapsed
                    ? Center(
                      child: Icon(
                        icon,
                        size: 22,
                        color:
                            selected
                                ? (onDark ? Colors.white : cs.primary)
                                : onDark
                                ? const Color(0xFFBFD2FA)
                                : Colors.black.withOpacity(0.62),
                      ),
                    )
                    : Row(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color:
                              selected
                                  ? (onDark ? Colors.white : cs.primary)
                                  : onDark
                                  ? const Color(0xFFBFD2FA)
                                  : Colors.black.withOpacity(0.62),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              color:
                                  selected
                                      ? (onDark
                                          ? Colors.white
                                          : const Color(0xFF172033))
                                      : onDark
                                      ? const Color(0xFFD7E4FC)
                                      : Colors.black.withOpacity(0.68),
                              shadows:
                                  selected && onDark
                                      ? const [
                                        Shadow(
                                          color: AqsColors.primaryDark,
                                          blurRadius: 2,
                                        ),
                                      ]
                                      : null,
                            ),
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  onDark
                                      ? Colors.white.withOpacity(0.12)
                                      : cs.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: onDark ? Colors.white : cs.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}
