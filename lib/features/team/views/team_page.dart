import 'dart:math';

import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/billing/services/subscription_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in to manage your team.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('projects')
              .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Team error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final projects =
            snap.data!.docs.where((project) {
              final data = project.data();
              final ownerId = _s(data['ownerId']);
              final members = (data['members'] as List?) ?? const [];
              return ownerId == user.uid ||
                  members.map((e) => e.toString()).contains(user.uid);
            }).toList();
        final memberProjectMap = <String, List<String>>{};
        for (final project in projects) {
          final data = project.data();
          final projectName =
              _s(data['name']).isEmpty ? 'Project' : _s(data['name']);
          final ownerId = _s(data['ownerId']);
          if (ownerId.isNotEmpty) {
            memberProjectMap.putIfAbsent(ownerId, () => []).add(projectName);
          }
          final members = (data['members'] as List?) ?? const [];
          for (final uid
              in members.map((e) => e.toString()).where((e) => e.isNotEmpty)) {
            memberProjectMap.putIfAbsent(uid, () => []).add(projectName);
          }
        }

        return FutureBuilder<_TeamData>(
          future: _loadTeamData(memberProjectMap, user.uid),
          builder: (context, teamSnap) {
            if (!teamSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = teamSnap.data!;
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 16 : 22,
                    compact ? 16 : 24,
                    32,
                  ),
                  children: [
                    _TeamHero(
                      memberCount: data.members.length,
                      projectCount: projects.length,
                      pendingCount: data.invites.length,
                      onInvite:
                          () => showDialog<void>(
                            context: context,
                            builder: (_) => _InviteMemberDialog(ownerUid: user.uid),
                          ),
                    ),
                    const SizedBox(height: 18),
                    if (data.members.isEmpty)
                      const _EmptyTeamState()
                    else
                      for (final member in data.members) ...[
                        _MemberCard(member: member, currentUid: user.uid),
                        const SizedBox(height: 12),
                      ],
                    if (data.invites.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const _SectionTitle(
                        title: 'Pending invites',
                        subtitle: 'Invitations created but not yet accepted.',
                      ),
                      const SizedBox(height: 10),
                      for (final invite in data.invites) ...[
                        _InviteCard(invite: invite),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<_TeamData> _loadTeamData(
    Map<String, List<String>> memberProjectMap,
    String ownerUid,
  ) async {
    final fs = FirebaseFirestore.instance;
    final members = <_TeamMember>[];
    final memberIds = memberProjectMap.keys.toList();

    for (var i = 0; i < memberIds.length; i += 10) {
      final chunk = memberIds.skip(i).take(10).toList();
      if (chunk.isEmpty) continue;
      final users = await fs
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      final usersById = {for (final doc in users.docs) doc.id: doc.data()};

      final roles = await fs
          .collection('workspaceMembers')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      final rolesById = {for (final doc in roles.docs) doc.id: doc.data()};

      for (final uid in chunk) {
        final userData = usersById[uid] ?? const <String, dynamic>{};
        final roleData = rolesById[uid] ?? const <String, dynamic>{};
        final projects = (memberProjectMap[uid] ?? const <String>[])
            .toSet()
            .toList()
          ..sort();
        members.add(
          _TeamMember(
            uid: uid,
            name: _bestName(userData, uid),
            email: (userData['email'] ?? '').toString(),
            role: (roleData['role'] ?? userData['role'] ?? 'member').toString(),
            status: (roleData['status'] ?? userData['status'] ?? 'active').toString(),
            projects: projects,
          ),
        );
      }
    }

    final invitesSnap = await fs
        .collection('teamInvites')
        .where('invitedBy', isEqualTo: ownerUid)
        .limit(20)
        .get();
    final invites = invitesSnap.docs
        .map((doc) => _TeamInvite.fromDoc(doc))
        .where((invite) => invite.status == 'pending')
        .toList();
    invites.sort((a, b) => b.id.compareTo(a.id));

    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _TeamData(members: members, invites: invites);
  }

  String _bestName(Map<String, dynamic> data, String uid) {
    final name = (data['name'] ?? data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Member ${uid.substring(0, uid.length < 6 ? uid.length : 6)}';
  }
}

class _TeamHero extends StatelessWidget {
  const _TeamHero({
    required this.memberCount,
    required this.projectCount,
    required this.pendingCount,
    required this.onInvite,
  });

  final int memberCount;
  final int projectCount;
  final int pendingCount;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AqsColors.primaryDark, Color(0xFF155EEF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22155EEF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Team workspace',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage people who can access projects, drawings, BOQs, and measurements.',
                style: TextStyle(color: Color(0xFFD6E4FF), height: 1.45),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroPill(label: '$memberCount members', icon: Icons.group_outlined),
                  _HeroPill(label: '$projectCount projects', icon: Icons.folder_outlined),
                  _HeroPill(label: '$pendingCount pending', icon: Icons.mark_email_unread_outlined),
                ],
              ),
            ],
          );

          final button = FilledButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Invite member'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AqsColors.primary,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 18),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 18),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD6E4FF)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD6E4FF),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.currentUid});

  final _TeamMember member;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final isYou = member.uid == currentUid;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFEFF4FF),
            child: Text(
              member.initials,
              style: const TextStyle(
                color: AqsColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isYou ? '${member.name} (You)' : member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AqsColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(status: member.status),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (member.email.trim().isNotEmpty) member.email,
                    '${member.projects.length} project${member.projects.length == 1 ? '' : 's'}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AqsColors.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: member.projects.take(4).map((project) {
                    return Chip(
                      label: Text(project),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: const Color(0xFFF2F4F7),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _RoleDropdown(member: member, disabled: isYou),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.member, required this.disabled});

  final _TeamMember member;
  final bool disabled;

  static const roles = ['owner', 'manager', 'quantity_surveyor', 'viewer'];

  String _label(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      case 'quantity_surveyor':
        return 'QS / Estimator';
      case 'viewer':
        return 'Viewer';
      default:
        return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = roles.contains(member.role) ? member.role : 'quantity_surveyor';
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        onChanged: disabled
            ? null
            : (role) async {
                if (role == null) return;
                await FirebaseFirestore.instance
                    .collection('workspaceMembers')
                    .doc(member.uid)
                    .set({
                  'uid': member.uid,
                  'email': member.email,
                  'name': member.name,
                  'role': role,
                  'status': 'active',
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              },
        items: [
          for (final role in roles)
            DropdownMenuItem(value: role, child: Text(_label(role))),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFECFDF3) : const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : status,
        style: TextStyle(
          color: active ? const Color(0xFF047857) : const Color(0xFFB54708),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

Future<void> _openWhatsAppInvite(
  BuildContext context,
  String message,
) async {
  final uri = Uri.https('wa.me', '/', {'text': message});
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp.')),
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({required this.ownerUid});

  final String ownerUid;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _role = 'quantity_surveyor';
  bool _allProjects = true;
  final Set<String> _selectedProjectIds = {};
  bool _saving = false;

  String _token() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _inviteLink(String token) {
    const hostedBase = 'https://aqssite-6aa5c.web.app';
    return '$hostedBase/#/invite/$token';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (_saving || !email.contains('@')) return;
    setState(() => _saving = true);

    final fs = FirebaseFirestore.instance;
    try {
      final canInvite =
          await SubscriptionService.instance.canInviteTeamMember();
      if (!canInvite) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Free plan allows 1 user only. Please subscribe to invite team members.',
              ),
            ),
          );
        }
        return;
      }

      final ownedProjects = await fs
          .collection('projects')
          .where('ownerId', isEqualTo: widget.ownerUid)
          .get();
      final selectedProjects = _allProjects
          ? ownedProjects.docs
          : ownedProjects.docs
              .where((project) => _selectedProjectIds.contains(project.id))
              .toList();
      if (selectedProjects.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one project.')),
          );
        }
        return;
      }

      final userMatch = await fs
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      final existingUid = userMatch.docs.isEmpty ? null : userMatch.docs.first.id;
      final name = _nameCtrl.text.trim();
      final token = _token();
      final link = _inviteLink(token);
      final projectIds = selectedProjects.map((project) => project.id).toList();
      final projectNames = selectedProjects
          .map((project) => (project.data()['name'] ?? 'Project').toString())
          .toList();

      await fs.collection('teamInvites').add({
        'name': name,
        'email': email,
        'role': _role,
        'status': existingUid == null ? 'pending' : 'accepted',
        'invitedBy': widget.ownerUid,
        'existingUid': existingUid,
        'projectScope': _allProjects ? 'all_owned_projects' : 'selected_projects',
        'projectIds': projectIds,
        'projectNames': projectNames,
        'inviteToken': token,
        'inviteLink': link,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (existingUid != null) {
        await fs.collection('workspaceMembers').doc(existingUid).set({
          'uid': existingUid,
          'name': name.isEmpty ? (userMatch.docs.first.data()['name'] ?? '') : name,
          'email': email,
          'role': _role,
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final batch = fs.batch();
        for (final project in selectedProjects) {
          batch.update(project.reference, {
            'members': FieldValue.arrayUnion([existingUid]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _InviteCreatedDialog(
          email: email,
          existingUser: existingUid != null,
          inviteLink: link,
          inviteCode: token,
          projectNames: projectNames,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite team member'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(
                    value: 'quantity_surveyor',
                    child: Text('QS / Estimator'),
                  ),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              const SizedBox(height: 16),
              _ProjectAccessSelector(
                ownerUid: widget.ownerUid,
                allProjects: _allProjects,
                selectedProjectIds: _selectedProjectIds,
                onAllChanged:
                    (value) => setState(() => _allProjects = value),
                onToggleProject:
                    (projectId, selected) => setState(() {
                      if (selected) {
                        _selectedProjectIds.add(projectId);
                      } else {
                        _selectedProjectIds.remove(projectId);
                      }
                    }),
              ),
              const SizedBox(height: 10),
              const Text(
                'Existing users get access immediately. New users receive an invite link/code record; account creation should be completed through the invite acceptance flow.',
                style: TextStyle(color: AqsColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _invite,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Invite'),
        ),
      ],
    );
  }
}

class _ProjectAccessSelector extends StatelessWidget {
  const _ProjectAccessSelector({
    required this.ownerUid,
    required this.allProjects,
    required this.selectedProjectIds,
    required this.onAllChanged,
    required this.onToggleProject,
  });

  final String ownerUid;
  final bool allProjects;
  final Set<String> selectedProjectIds;
  final ValueChanged<bool> onAllChanged;
  final void Function(String projectId, bool selected) onToggleProject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('projects')
                .where('ownerId', isEqualTo: ownerUid)
                .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final projects = snap.data!.docs;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Project access',
                style: TextStyle(
                  color: AqsColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose whether this member can access all your projects or selected projects only.',
                style: TextStyle(color: AqsColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: allProjects,
                onChanged: onAllChanged,
                title: const Text(
                  'All my projects',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${projects.length} project(s)'),
              ),
              if (!allProjects) ...[
                const Divider(height: 18),
                if (projects.isEmpty)
                  const Text(
                    'No owned projects found.',
                    style: TextStyle(color: AqsColors.muted),
                  )
                else
                  for (final project in projects)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selectedProjectIds.contains(project.id),
                      onChanged:
                          (value) =>
                              onToggleProject(project.id, value == true),
                      title: Text(
                        (project.data()['name'] ?? 'Project').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        (project.data()['clientName'] ??
                                project.data()['client'] ??
                                '')
                            .toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InviteCreatedDialog extends StatelessWidget {
  const _InviteCreatedDialog({
    required this.email,
    required this.existingUser,
    required this.inviteLink,
    required this.inviteCode,
    required this.projectNames,
  });

  final String email;
  final bool existingUser;
  final String inviteLink;
  final String inviteCode;
  final List<String> projectNames;

  @override
  Widget build(BuildContext context) {
    final message =
        existingUser
            ? 'This user already has an account. Project access has been granted.'
            : 'Send this invite link/code to the user so they can join the selected project workspace.';
    final shareText = [
      'AQS AUTOboq team invitation',
      'Email: $email',
      'Invite link: $inviteLink',
      'Invite code: $inviteCode',
      'Projects: ${projectNames.join(', ')}',
    ].join('\n');

    return AlertDialog(
      title: Text(existingUser ? 'Access granted' : 'Invite created'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(color: AqsColors.muted)),
            const SizedBox(height: 14),
            if (!existingUser) ...[
              const Text(
                'Invite link',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              SelectableText(inviteLink),
              const SizedBox(height: 12),
              const Text(
                'Invite code',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              SelectableText(inviteCode),
              const SizedBox(height: 14),
            ],
            const Text(
              'Project access',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              projectNames.join(', '),
              style: const TextStyle(color: AqsColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        if (!existingUser)
          OutlinedButton.icon(
            onPressed: () => _openWhatsAppInvite(context, shareText),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
        if (!existingUser)
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy invite'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite});

  final _TeamInvite invite;

  @override
  Widget build(BuildContext context) {
    final shareText = [
      'AQS AUTOboq team invitation',
      'Email: ${invite.email}',
      if (invite.inviteLink.isNotEmpty) 'Invite link: ${invite.inviteLink}',
      if (invite.inviteCode.isNotEmpty) 'Invite code: ${invite.inviteCode}',
      if (invite.projectNames.isNotEmpty)
        'Projects: ${invite.projectNames.join(', ')}',
    ].join('\n');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AqsColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: AqsColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.name.isEmpty ? invite.email : invite.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${invite.email} • ${invite.roleLabel}',
                  style: const TextStyle(color: AqsColors.muted, fontSize: 12),
                ),
                if (invite.projectNames.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Projects: ${invite.projectNames.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AqsColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (invite.inviteCode.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Code: ${invite.inviteCode}',
                    style: const TextStyle(
                      color: AqsColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (invite.inviteLink.isNotEmpty)
            IconButton(
              tooltip: 'Share via WhatsApp',
              onPressed: () => _openWhatsAppInvite(context, shareText),
              icon: const Icon(Icons.chat_outlined),
            ),
          if (invite.inviteLink.isNotEmpty)
            IconButton(
              tooltip: 'Copy invite link',
              onPressed:
                  () => Clipboard.setData(
                    ClipboardData(text: invite.inviteLink),
                  ),
              icon: const Icon(Icons.copy_rounded),
            ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('teamInvites')
                  .doc(invite.id)
                  .set({
                'status': 'cancelled',
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AqsColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: AqsColors.muted)),
      ],
    );
  }
}

class _EmptyTeamState extends StatelessWidget {
  const _EmptyTeamState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AqsColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.groups_outlined, size: 38, color: AqsColors.muted),
          SizedBox(height: 10),
          Text(
            'No team members yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 4),
          Text(
            'Invite members to collaborate on project measurements and BOQs.',
            style: TextStyle(color: AqsColors.muted),
          ),
        ],
      ),
    );
  }
}

class _TeamData {
  const _TeamData({required this.members, required this.invites});

  final List<_TeamMember> members;
  final List<_TeamInvite> invites;
}

class _TeamMember {
  const _TeamMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.projects,
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final String status;
  final List<String> projects;

  String get initials {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source[0].toUpperCase();
  }
}

class _TeamInvite {
  const _TeamInvite({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.projectNames,
    required this.inviteCode,
    required this.inviteLink,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String status;
  final List<String> projectNames;
  final String inviteCode;
  final String inviteLink;

  factory _TeamInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return _TeamInvite(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      role: (data['role'] ?? 'quantity_surveyor').toString(),
      status: (data['status'] ?? 'pending').toString(),
      projectNames:
          ((data['projectNames'] as List?) ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(),
      inviteCode: (data['inviteToken'] ?? '').toString(),
      inviteLink: (data['inviteLink'] ?? '').toString(),
    );
  }

  String get roleLabel {
    switch (role) {
      case 'manager':
        return 'Manager';
      case 'viewer':
        return 'Viewer';
      case 'quantity_surveyor':
        return 'QS / Estimator';
      default:
        return 'Member';
    }
  }
}
