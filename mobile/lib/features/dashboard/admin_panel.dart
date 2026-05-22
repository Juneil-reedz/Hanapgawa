import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/utils.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/status_chip.dart';
import 'admin_ai_section.dart';

const _categoryIcons = <String, IconData>{
  'briefcase': Icons.work,
  'build': Icons.build,
  'electrical': Icons.electrical_services,
  'plumbing': Icons.plumbing,
  'cleaning': Icons.cleaning_services,
  'home-repair': Icons.home_repair_service,
  'paint': Icons.format_paint,
  'yard': Icons.yard,
  'school': Icons.school,
  'beauty': Icons.face,
  'security': Icons.security,
  'delivery': Icons.local_shipping,
  'food': Icons.restaurant,
  'fitness': Icons.fitness_center,
  'computer': Icons.computer,
  'car-repair': Icons.car_repair,
  'pets': Icons.pets,
  'medical': Icons.medical_services,
  'category': Icons.category,
};

IconData _resolveIcon(String name) =>
    _categoryIcons[name] ?? Icons.category;

// ─── Section tabs ─────────────────────────────────────────────────────────────

enum _Tab {
  overview,
  users,
  reports,
  categories,
  monitoring,
  analytics,
  feedback,
  ai;

  String get label => switch (this) {
        overview => 'Overview',
        users => 'Users',
        reports => 'Reports',
        categories => 'Categories',
        monitoring => 'Monitoring',
        analytics => 'Analytics',
        feedback => 'Feedback',
        ai => 'AI',
      };

  IconData get icon => switch (this) {
        overview => Icons.dashboard_outlined,
        users => Icons.people_outline,
        reports => Icons.flag_outlined,
        categories => Icons.category_outlined,
        monitoring => Icons.show_chart,
        analytics => Icons.bar_chart,
        feedback => Icons.star_rate_outlined,
        ai => Icons.psychology,
      };
}

// ─── Admin panel ──────────────────────────────────────────────────────────────

class AdminPanel extends StatefulWidget {
  const AdminPanel({
    super.key,
    required this.api,
    required this.summary,
    required this.users,
    required this.reports,
    required this.categories,
    required this.bookings,
    required this.jobs,
    required this.isOffline,
    required this.reload,
  });

  final MarketplaceApi api;
  final AdminSummary summary;
  final List<SessionUser> users;
  final List<ReportItem> reports;
  final List<ServiceCategory> categories;
  final List<Booking> bookings;
  final List<JobPost> jobs;
  final bool isOffline;
  final Future<void> Function() reload;

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  _Tab _tab = _Tab.overview;
  final _categoryName = TextEditingController();
  final _categoryIcon = TextEditingController(text: 'briefcase-outline');
  final _categoryDescription = TextEditingController();
  var _savingCategory = false;
  var _query = '';
  var _userFilter = 'all';
  var _reportFilter = 'all';
  var _togglingCategoryId = '';

  @override
  void dispose() {
    _categoryName.dispose();
    _categoryIcon.dispose();
    _categoryDescription.dispose();
    super.dispose();
  }

  // ─── Filtered getters ─────────────────────────────────────────────────────

  List<SessionUser> get _filteredUsers {
    var list = widget.users.where((u) => u.role != 'admin').toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((u) =>
              (u.fullName ?? '').toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.role.toLowerCase().contains(q) ||
              (u.status ?? '').toLowerCase().contains(q))
          .toList();
    }
    if (_userFilter != 'all') {
      list = list.where((u) => (u.status ?? '') == _userFilter).toList();
    }
    return list;
  }

  List<ReportItem> get _filteredReports => _reportFilter == 'all'
      ? widget.reports
      : widget.reports.where((r) => r.status == _reportFilter).toList();

  int get _pendingReportCount =>
      widget.reports.where((r) => r.status == 'pending').length;

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<bool> _confirm(
    String title,
    String body, {
    String confirmLabel = 'Confirm',
    Color confirmColor = appPrimary,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  bool get _offline => widget.isOffline || !SyncService.instance.isOnline;

  Future<void> _deleteUser(SessionUser user) async {
    final ok = await _confirm(
      'Delete user?',
      'This will permanently delete ${user.fullName ?? user.email} and all their data. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: Colors.red.shade700,
    );
    if (!ok) return;
    try {
      if (_offline) {
        _show('User deletion requires a connection.');
        return;
      }
      await widget.api.deleteAdminUser(user.id);
      await widget.reload();
      _show('User deleted.');
    } catch (e) {
      _show(friendlyError(e));
    }
  }

  Future<void> _updateUser(String userId, String status) async {
    if (status == 'suspended' || status == 'banned') {
      final ok = await _confirm(
        status == 'banned' ? 'Ban user?' : 'Suspend user?',
        status == 'banned'
            ? 'This will permanently ban the user from the platform.'
            : 'This will suspend the user account temporarily.',
        confirmLabel: status == 'banned' ? 'Ban' : 'Suspend',
        confirmColor: Colors.red.shade700,
      );
      if (!ok) return;
    }
    try {
      if (_offline) {
        await LocalDb.instance.queueAction('admin_update_user', {'userId': userId, 'status': status});
        _show('Queued — will sync when online.');
        return;
      }
      await widget.api.updateAdminUserStatus(userId, status);
      await widget.reload();
      _show('User marked as $status.');
    } catch (e) {
      _show(friendlyError(e));
    }
  }

  Future<void> _resolveReport(String reportId, String status) async {
    try {
      if (_offline) {
        await LocalDb.instance.queueAction('admin_resolve_report', {'reportId': reportId, 'status': status});
        _show('Queued — will sync when online.');
        return;
      }
      await widget.api.updateReportStatus(reportId, status);
      await widget.reload();
      _show('Report marked as $status.');
    } catch (e) {
      _show(friendlyError(e));
    }
  }

  Future<void> _deleteReportedPost(ReportItem report) async {
    final postId = report.contentId;
    if (postId == null || postId.isEmpty) return;
    const reason = 'Removed by admin after review of a user report.';
    final ok = await _confirm(
      'Delete reported post?',
      'This reported post will be permanently removed. Reason: $reason',
      confirmLabel: 'Delete',
      confirmColor: Colors.red.shade700,
    );
    if (!ok) return;
    try {
      if (_offline) {
        _show('Admin post deletion requires a connection.');
        return;
      }
      await widget.api.deleteAdminPost(postId, reason: reason);
      await widget.reload();
      _show('Reported post deleted.');
    } catch (e) {
      _show(friendlyError(e));
    }
  }

  Future<void> _toggleCategory(String categoryId, bool currentlyActive) async {
    setState(() => _togglingCategoryId = categoryId);
    try {
      if (_offline) {
        await LocalDb.instance.queueAction('admin_toggle_category', {'categoryId': categoryId, 'active': !currentlyActive});
        _show('Queued — will sync when online.');
        return;
      }
      await widget.api.updateCategory(categoryId, active: !currentlyActive);
      await widget.reload();
    } catch (e) {
      _show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _togglingCategoryId = '');
    }
  }

  Future<void> _createCategory() async {
    if (_categoryName.text.trim().isEmpty) return;
    setState(() => _savingCategory = true);
    try {
      if (_offline) {
        await LocalDb.instance.queueAction('admin_create_category', {
          'name': _categoryName.text.trim(),
          'description': _categoryDescription.text.trim(),
          'icon': _categoryIcon.text.trim().isEmpty ? 'briefcase-outline' : _categoryIcon.text.trim(),
        });
        _categoryName.clear();
        _categoryDescription.clear();
        _show('Queued — will sync when online.');
        return;
      }
      await widget.api.createCategory(
        name: _categoryName.text.trim(),
        description: _categoryDescription.text.trim(),
        icon: _categoryIcon.text.trim().isEmpty ? 'briefcase-outline' : _categoryIcon.text.trim(),
      );
      _categoryName.clear();
      _categoryDescription.clear();
      await widget.reload();
      _show('Category added.');
    } catch (e) {
      _show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingCategory = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: 16),
          _NavBar(
            current: _tab,
            reportBadge: _pendingReportCount,
            onTap: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 20),
          _buildSection(),
        ],
      );

  Widget _buildSection() => switch (_tab) {
        _Tab.overview => _OverviewSection(summary: widget.summary),
        _Tab.users => _UsersSection(
            users: _filteredUsers,
            allUsers: widget.users.where((u) => u.role != 'admin').toList(),
            query: _query,
            filter: _userFilter,
            onQueryChanged: (v) => setState(() => _query = v),
            onFilterChanged: (v) => setState(() => _userFilter = v),
            onUpdateUser: _updateUser,
            onDeleteUser: _deleteUser,
          ),
        _Tab.reports => _ReportsSection(
            reports: _filteredReports,
            allReports: widget.reports,
            filter: _reportFilter,
            onFilterChanged: (v) => setState(() => _reportFilter = v),
            onResolve: _resolveReport,
            onDeleteReportedPost: _deleteReportedPost,
          ),
        _Tab.categories => _CategoriesSection(
            categories: widget.categories,
            nameCtrl: _categoryName,
            iconCtrl: _categoryIcon,
            descCtrl: _categoryDescription,
            saving: _savingCategory,
            togglingId: _togglingCategoryId,
            onCreate: _createCategory,
            onToggle: _toggleCategory,
          ),
        _Tab.monitoring => _MonitoringSection(
            bookings: widget.bookings,
            jobs: widget.jobs,
          ),
        _Tab.analytics => _AnalyticsSection(
            users: widget.users,
            jobs: widget.jobs,
            bookings: widget.bookings,
            categories: widget.categories,
            summary: widget.summary,
            reports: widget.reports,
          ),
        _Tab.feedback => _FeedbackSection(api: widget.api),
        _Tab.ai => AdminAISection(
            api: widget.api,
            users: widget.users,
            reports: widget.reports,
            bookings: widget.bookings,
            jobs: widget.jobs,
          ),
      };
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin Console',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          const Text(
            'Platform management & moderation',
            style: TextStyle(color: appMuted, fontSize: 13),
          ),
        ],
      );
}

// ─── Nav bar ──────────────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.current,
    required this.reportBadge,
    required this.onTap,
  });
  final _Tab current;
  final int reportBadge;
  final void Function(_Tab) onTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _Tab.values.map((tab) {
            final badge = tab == _Tab.reports && reportBadge > 0
                ? reportBadge
                : null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _NavChip(
                icon: tab.icon,
                label: tab.label,
                badge: badge,
                selected: current == tab,
                onTap: () => onTap(tab),
              ),
            );
          }).toList(),
        ),
      );
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? appPrimary : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? appPrimary : appBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: selected ? Colors.white : appMuted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF1F1F1F),
                )),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.red.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? appPrimary : Colors.white,
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.meta});
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900))),
          Text(meta,
              style: const TextStyle(
                  color: appMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─── Shared: role badge ───────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  Color get _color => switch (role) {
        'admin' => appPrimary,
        'worker' => const Color(0xFF10B981),
        'agency' => const Color(0xFF4F7FFF),
        _ => appMuted,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          role[0].toUpperCase() + role.substring(1),
          style: TextStyle(
              color: _color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
}

// ─── Shared: colored stat tile ────────────────────────────────────────────────

class _TileData {
  const _TileData({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData icon;
}

class _ColoredStatTile extends StatelessWidget {
  const _ColoredStatTile({required this.data});
  final _TileData data;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: appBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: data.color.withAlpha(22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, size: 18, color: data.color),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${data.value}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: data.color,
                    height: 1,
                  )),
              const SizedBox(height: 2),
              Text(data.label,
                  style: const TextStyle(
                      color: appMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      );
}

// ─── Overview section ─────────────────────────────────────────────────────────

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.summary});
  final AdminSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _TileData(
          label: 'Total users',
          value: summary.totalUsers,
          color: const Color(0xFF4F7FFF),
          icon: Icons.people),
      _TileData(
          label: 'Active posts',
          value: summary.activePosts,
          color: appPrimary,
          icon: Icons.article),
      _TileData(
          label: 'Completed jobs',
          value: summary.completedJobs,
          color: const Color(0xFF10B981),
          icon: Icons.check_circle),
      _TileData(
          label: 'Pending reports',
          value: summary.pendingReports,
          color: const Color(0xFFEF4444),
          icon: Icons.flag),
      _TileData(
          label: 'Suspended users',
          value: summary.suspendedUsers,
          color: const Color(0xFFF97316),
          icon: Icons.block),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(title: 'Platform Overview', meta: 'Live stats'),
      GridView.count(
        crossAxisCount: MediaQuery.sizeOf(context).width > 620 ? 4 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: tiles.map((t) => _ColoredStatTile(data: t)).toList(),
      ),
    ]);
  }
}

// ─── Users section ────────────────────────────────────────────────────────────

class _UsersSection extends StatelessWidget {
  const _UsersSection({
    required this.users,
    required this.allUsers,
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onUpdateUser,
    required this.onDeleteUser,
  });
  final List<SessionUser> users;
  final List<SessionUser> allUsers;
  final String query;
  final String filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function(String, String) onUpdateUser;
  final Future<void> Function(SessionUser) onDeleteUser;

  int _count(String status) => status == 'all'
      ? allUsers.length
      : allUsers.where((u) => (u.status ?? '') == status).length;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'User Management', meta: '${users.length} shown'),
          TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name, email, role, or status…',
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in [
                  'all',
                  'suspended',
                  'banned'
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                          '${s[0].toUpperCase()}${s.substring(1)} (${_count(s)})'),
                      selected: filter == s,
                      onSelected: (_) => onFilterChanged(s),
                      selectedColor: appAccent,
                      checkmarkColor: appPrimary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const EmptyState(
                icon: Icons.people_outline,
                title: 'No users found',
                subtitle: 'Try a different search or filter.'),
          ...users.map((user) => _UserCard(
                user: user,
                onUpdate: onUpdateUser,
                onDelete: onDeleteUser,
              )),
        ],
      );
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onUpdate, required this.onDelete});
  final SessionUser user;
  final Future<void> Function(String, String) onUpdate;
  final Future<void> Function(SessionUser) onDelete;

  Color _roleColor(String role) => switch (role) {
        'admin' => appPrimary,
        'worker' => const Color(0xFF10B981),
        'agency' => const Color(0xFF4F7FFF),
        _ => appMuted,
      };

  @override
  Widget build(BuildContext context) {
    final rc = _roleColor(user.role);
    final status = user.status ?? 'pending';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: rc.withAlpha(28),
            child: Text(user.initials,
                style: TextStyle(color: rc, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName ?? user.email,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(user.email,
                  style: const TextStyle(color: appMuted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _RoleBadge(role: user.role),
          const SizedBox(width: 8),
          Text(
            '${user.postCount} post${user.postCount == 1 ? '' : 's'}',
            style: const TextStyle(color: appMuted, fontSize: 12),
          ),
          if (user.reportCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${user.reportCount} report${user.reportCount == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ]),
        if (user.role != 'admin') ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (status != 'approved')
              _ActionBtn(
                label: 'Reactivate',
                icon: Icons.check_circle_outline,
                color: const Color(0xFF22C55E),
                onTap: () => onUpdate(user.id, 'approved'),
              ),
            if (status != 'suspended')
              _ActionBtn(
                label: 'Suspend',
                icon: Icons.pause_circle_outline,
                color: Colors.orange.shade700,
                onTap: () => onUpdate(user.id, 'suspended'),
              ),
            if (status != 'banned')
              _ActionBtn(
                label: 'Ban',
                icon: Icons.block,
                color: Colors.red.shade700,
                onTap: () => onUpdate(user.id, 'banned'),
              ),
            _ActionBtn(
              label: 'Delete',
              icon: Icons.delete_outline,
              color: Colors.red.shade900,
              onTap: () => onDelete(user),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      );
}

// ─── Reports section ──────────────────────────────────────────────────────────

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({
    required this.reports,
    required this.allReports,
    required this.filter,
    required this.onFilterChanged,
    required this.onResolve,
    required this.onDeleteReportedPost,
  });
  final List<ReportItem> reports;
  final List<ReportItem> allReports;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function(String, String) onResolve;
  final Future<void> Function(ReportItem) onDeleteReportedPost;

  int _count(String status) => status == 'all'
      ? allReports.length
      : allReports.where((r) => r.status == status).length;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Reports & Complaints', meta: '${reports.length} shown'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in ['all', 'pending', 'resolved', 'dismissed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                          '${s[0].toUpperCase()}${s.substring(1)} (${_count(s)})'),
                      selected: filter == s,
                      onSelected: (_) => onFilterChanged(s),
                      selectedColor: appAccent,
                      checkmarkColor: appPrimary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            const EmptyState(
                icon: Icons.verified_outlined,
                title: 'No reports',
                subtitle:
                    'Fake accounts, scams, and harassment reports appear here.'),
          ...reports.map((report) => AppCard(
                accentColor:
                    report.status == 'pending' ? Colors.red.shade500 : null,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(report.reason,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        StatusChip(status: report.status),
                      ]),
                      const SizedBox(height: 4),
                      if (report.reporterName != null &&
                          report.reporterName!.isNotEmpty)
                        Text(
                          'Reported by: ${report.reporterName}',
                          style: const TextStyle(
                              color: appMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        report.details,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: appMuted, height: 1.4),
                      ),
                      if (report.contentType == 'social_post') ...[
                        const SizedBox(height: 10),
                        _ReportedPostPreview(report: report),
                      ],
                      if (report.status == 'pending') ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          if (report.contentType == 'social_post' &&
                              report.contentId != null)
                            OutlinedButton.icon(
                              onPressed: () => onDeleteReportedPost(report),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Delete Post'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: () => onResolve(report.id, 'resolved'),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Resolve'),
                          ),
                          OutlinedButton(
                            onPressed: () => onResolve(report.id, 'dismissed'),
                            child: const Text('Dismiss'),
                          ),
                        ]),
                      ],
                    ]),
              )),
        ],
      );
}

class _ReportedPostPreview extends StatelessWidget {
  const _ReportedPostPreview({required this.report});
  final ReportItem report;

  @override
  Widget build(BuildContext context) {
    final content = report.reportedContent;
    final body = content?['body']?.toString();
    final author = content?['fullName']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.article_outlined, size: 16, color: appPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              author == null || author.isEmpty
                  ? 'Post content'
                  : 'Post by $author',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          body == null || body.isEmpty
              ? 'Post content is no longer available.'
              : body,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: appMuted, fontSize: 13, height: 1.35),
        ),
      ]),
    );
  }
}

// ─── Categories section ───────────────────────────────────────────────────────

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({
    required this.categories,
    required this.nameCtrl,
    required this.iconCtrl,
    required this.descCtrl,
    required this.saving,
    required this.togglingId,
    required this.onCreate,
    required this.onToggle,
  });
  final List<ServiceCategory> categories;
  final TextEditingController nameCtrl;
  final TextEditingController iconCtrl;
  final TextEditingController descCtrl;
  final bool saving;
  final String togglingId;
  final VoidCallback onCreate;
  final Future<void> Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Category Management', meta: '${categories.length} total'),
          // Add form
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add New Category',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Name', hintText: 'e.g. Plumbing')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoryIcons.containsKey(iconCtrl.text)
                    ? iconCtrl.text
                    : _categoryIcons.keys.first,
                decoration: const InputDecoration(labelText: 'Icon'),
                items: _categoryIcons.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Row(children: [
                            Icon(e.value, size: 18, color: appPrimary),
                            const SizedBox(width: 10),
                            Text(e.key,
                                style: const TextStyle(fontSize: 14)),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) iconCtrl.text = v;
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: saving ? null : onCreate,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
              ),
            ]),
          ),
          // Category list
          if (categories.isEmpty)
            const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                subtitle: 'Add your first service category above.'),
          ...categories.map((cat) => AppCard(
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cat.active ? appAccent : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_resolveIcon(cat.icon),
                        size: 20,
                        color: cat.active ? appPrimary : Colors.grey.shade400),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          if (cat.description.isNotEmpty)
                            Text(cat.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: appMuted, fontSize: 12)),
                        ]),
                  ),
                  if (togglingId == cat.id)
                    const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Switch(
                      value: cat.active,
                      activeColor: appPrimary,
                      onChanged: (_) => onToggle(cat.id, cat.active),
                    ),
                ]),
              )),
        ],
      );
}

// ─── Monitoring section ───────────────────────────────────────────────────────

class _MonitoringSection extends StatelessWidget {
  const _MonitoringSection({
    required this.bookings,
    required this.jobs,
  });
  final List<Booking> bookings;
  final List<JobPost> jobs;

  int _bCount(String status) =>
      bookings.where((b) => b.status == status).length;
  int _jCount(String status) => jobs.where((j) => j.status == status).length;

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width > 620 ? 4 : 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        title: 'Booking & Job Monitoring',
        meta: '${bookings.length} bookings · ${jobs.length} jobs',
      ),
      const Text('Bookings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          _ColoredStatTile(
              data: _TileData(
                  label: 'Pending',
                  value: _bCount('pending'),
                  color: const Color(0xFFF59E0B),
                  icon: Icons.hourglass_empty)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Accepted',
                  value: _bCount('accepted'),
                  color: const Color(0xFF4F7FFF),
                  icon: Icons.handshake_outlined)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Completed',
                  value: _bCount('completed'),
                  color: const Color(0xFF22C55E),
                  icon: Icons.check_circle)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Cancelled',
                  value: _bCount('cancelled'),
                  color: appMuted,
                  icon: Icons.cancel_outlined)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Disputed',
                  value: _bCount('cancellation_requested'),
                  color: const Color(0xFFEF4444),
                  icon: Icons.gavel)),
        ],
      ),
      const SizedBox(height: 20),
      const Text('Job Posts',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          _ColoredStatTile(
              data: _TileData(
                  label: 'Open',
                  value: _jCount('open'),
                  color: const Color(0xFF4F7FFF),
                  icon: Icons.work_outline)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Assigned',
                  value: _jCount('assigned'),
                  color: appPrimary,
                  icon: Icons.assignment_ind_outlined)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Completed',
                  value: _jCount('completed'),
                  color: const Color(0xFF22C55E),
                  icon: Icons.check_circle)),
          _ColoredStatTile(
              data: _TileData(
                  label: 'Cancelled',
                  value: _jCount('cancelled'),
                  color: appMuted,
                  icon: Icons.cancel_outlined)),
        ],
      ),
    ]);
  }
}

// ─── Analytics section ────────────────────────────────────────────────────────

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({
    required this.users,
    required this.jobs,
    required this.bookings,
    required this.categories,
    required this.summary,
    required this.reports,
  });
  final List<SessionUser> users;
  final List<JobPost> jobs;
  final List<Booking> bookings;
  final List<ServiceCategory> categories;
  final AdminSummary summary;
  final List<ReportItem> reports;

  Color _roleColor(String role) => switch (role) {
        'admin' => appPrimary,
        'worker' => const Color(0xFF10B981),
        'agency' => const Color(0xFF4F7FFF),
        _ => appMuted,
      };

  @override
  Widget build(BuildContext context) {
    // Job category distribution
    final categoryCount = <String, int>{};
    for (final job in jobs) {
      categoryCount[job.category] = (categoryCount[job.category] ?? 0) + 1;
    }
    final topCategories = (categoryCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
    final maxJobCount = topCategories.isEmpty ? 1 : topCategories.first.value;

    // User role distribution (providers only)
    final roleCounts = <String, int>{};
    for (final u in users) {
      if (u.role == 'worker' || u.role == 'agency') {
        roleCounts[u.role] = (roleCounts[u.role] ?? 0) + 1;
      }
    }

    // Booking stats
    final totalBookings = bookings.length;
    final completedBookings =
        bookings.where((b) => b.status == 'completed').length;
    final cancelledBookings =
        bookings.where((b) => b.status == 'cancelled').length;
    final activeBookings = bookings
        .where((b) => b.status == 'accepted' || b.status == 'pending')
        .length;
    final bookingCompletionRate =
        totalBookings == 0 ? 0.0 : completedBookings / totalBookings;
    final bookingCancellationRate =
        totalBookings == 0 ? 0.0 : cancelledBookings / totalBookings;

    // Platform health
    final resolvedReports =
        reports.where((r) => r.status == 'resolved').length;
    final resolutionRate =
        reports.isEmpty ? 0.0 : resolvedReports / reports.length;
    final activeUsers = users.where((u) => u.postCount > 0).length;
    final engagementRate =
        summary.totalUsers == 0 ? 0.0 : activeUsers / summary.totalUsers;

    // Category health
    final activeCategories = categories.where((c) => c.active).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(title: 'Analytics', meta: 'Platform insights'),
      // Booking snapshot
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Booking Overview',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(children: [
            _StatPill(
                label: 'Total',
                value: '$totalBookings',
                color: const Color(0xFF4F7FFF)),
            const SizedBox(width: 10),
            _StatPill(
                label: 'Active',
                value: '$activeBookings',
                color: appPrimary),
            const SizedBox(width: 10),
            _StatPill(
                label: 'Completed',
                value: '$completedBookings',
                color: const Color(0xFF22C55E)),
            const SizedBox(width: 10),
            _StatPill(
                label: 'Cancelled',
                value: '$cancelledBookings',
                color: appMuted),
          ]),
          const SizedBox(height: 14),
          _HealthRow(
              label: 'Completion rate',
              value: '${(bookingCompletionRate * 100).toStringAsFixed(0)}%',
              progress: bookingCompletionRate,
              color: const Color(0xFF22C55E)),
          _HealthRow(
              label: 'Cancellation rate',
              value: '${(bookingCancellationRate * 100).toStringAsFixed(0)}%',
              progress: bookingCancellationRate,
              color: const Color(0xFFEF4444)),
        ]),
      ),
      // Platform health
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Platform Health',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          _HealthRow(
              label: 'Report resolution rate',
              value: '${(resolutionRate * 100).toStringAsFixed(0)}%',
              progress: resolutionRate,
              color: const Color(0xFF4F7FFF)),
          _HealthRow(
              label: 'User engagement rate',
              value: '${(engagementRate * 100).toStringAsFixed(0)}%',
              progress: engagementRate,
              color: appPrimary),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: Text(
                      'Active categories: $activeCategories / ${categories.length}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              Text('${(activeCategories / categories.length * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10B981))),
            ]),
          ],
        ]),
      ),
      // Top categories
      if (topCategories.isNotEmpty)
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Top Service Categories',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            ...topCategories.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(entry.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                          Text(
                              '${entry.value} job${entry.value == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: appMuted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: entry.value / maxJobCount,
                            minHeight: 7,
                            backgroundColor: appBorder,
                            color: appPrimary,
                          ),
                        ),
                      ]),
                )),
          ]),
        ),
      // User roles
      if (roleCounts.isNotEmpty)
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Provider Distribution',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            ...roleCounts.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    SizedBox(width: 72, child: _RoleBadge(role: entry.key)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: users.isEmpty ? 0 : entry.value / users.length,
                          minHeight: 7,
                          backgroundColor: appBorder,
                          color: _roleColor(entry.key),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${entry.value}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: appMuted,
                            fontSize: 12)),
                  ]),
                )),
          ]),
        ),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: appMuted)),
          ]),
        ),
      );
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });
  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: appBorder,
              color: color,
            ),
          ),
        ]),
      );
}

// ─── Feedback section ─────────────────────────────────────────────────────────

class _FeedbackSection extends StatefulWidget {
  const _FeedbackSection({required this.api});
  final MarketplaceApi api;

  @override
  State<_FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends State<_FeedbackSection> {
  var _loading = false;
  var _refreshing = false;
  var _feedback = <Map<String, dynamic>>[];
  var _total = 0;
  var _average = 0.0;
  var _distribution = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_feedback.isEmpty) setState(() => _loading = true);
    setState(() => _refreshing = true);
    try {
      final data = await widget.api.getAdminFeedback();
      if (mounted) {
        setState(() {
          _feedback = List<Map<String, dynamic>>.from(data['feedback'] as List? ?? []);
          _total = data['total'] as int? ?? 0;
          _average = (data['average'] as num?)?.toDouble() ?? 0.0;
          _distribution = List<Map<String, dynamic>>.from(data['distribution'] as List? ?? []);
          _loading = false;
          _refreshing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 28),
                              const SizedBox(width: 8),
                              Text(_average.toStringAsFixed(1),
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 8),
                              Text('/ 5.0  ·  $_total ratings',
                                  style: const TextStyle(color: Colors.black54)),
                            ]),
                            const SizedBox(height: 12),
                            ...[5, 4, 3, 2, 1].map((star) {
                              final entry = _distribution.firstWhere(
                                  (d) => d['star'] == star,
                                  orElse: () => {'star': star, 'count': 0});
                              final count = entry['count'] as int? ?? 0;
                              final pct = _total > 0 ? count / _total : 0.0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(children: [
                                  Text('$star', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct, minHeight: 8,
                                        backgroundColor: Colors.grey.shade200,
                                        color: appPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 28,
                                      child: Text('$count', style: const TextStyle(fontSize: 12, color: Colors.black54))),
                                ]),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_feedback.isEmpty)
                        const EmptyState(icon: Icons.star_outline, title: 'No feedback yet',
                            subtitle: 'User feedback will appear here.')
                      else
                        ..._feedback.map((f) {
                          final rating = f['rating'] as int? ?? 0;
                          final comment = f['comment']?.toString() ?? '';
                          final createdAt = parseDate(f['createdAt']);
                          return AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Row(children: List.generate(5, (i) => Icon(
                                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 18,
                                    color: i < rating ? const Color(0xFFFFC107) : Colors.grey.shade400,
                                  ))),
                                  const Spacer(),
                                  Text(timeAgo(createdAt),
                                      style: const TextStyle(color: Colors.black45, fontSize: 12)),
                                ]),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(comment, style: const TextStyle(fontSize: 14)),
                                ],
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
