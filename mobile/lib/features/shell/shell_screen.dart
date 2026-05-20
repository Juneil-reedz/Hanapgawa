import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../ai/user_ai_screen.dart';
import '../bookings/bookings_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../discover/discover_screen.dart';
import '../jobs/jobs_screen.dart';
import '../profile/profile_screen.dart';

// Non-admin tab indices
const _kBookings = 1;
const _kJobs = 2;

const _kFabSize = 56.0;

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.api, required this.onLogout});
  final MarketplaceApi api;
  final Future<void> Function() onLogout;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  var _index = 0;

  // Draggable FAB position (initialized in build once we have screen size)
  double? _fabX;
  double? _fabY;
  bool _dragging = false;

  // Badge counts
  int _bookingBadge = 0;
  int _inboxBadge = 0;
  int _jobsBadge = 0;

  // Track conversation seen times for inbox badge (independent from BookingsScreen)
  final _shellLastSeen = <String, DateTime>{};
  bool _shellInitDone = false;

  // Track IDs the user has already seen so the badge only fires for NEW items
  final _seenBookingIds = <String>{};
  final _seenJobPostIds = <String>{};
  bool _bookingInitDone = false;
  bool _jobsInitDone = false;

  Timer? _badgeTimer;

  bool get _isAdmin => widget.api.storedUser?.role == 'admin';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _index = 0;
    _loadBadges();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadBadges());
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBadges() async {
    final myId = widget.api.storedUser?.id ?? '';
    if (myId.isEmpty || _isAdmin) return;
    try {
      final results = await Future.wait([
        widget.api.getMyBookings().catchError((_) => <Booking>[]),
        widget.api.getMyConversations().catchError((_) => <Conversation>[]),
        widget.api.getJobs().catchError((_) => <JobPost>[]),
      ]);
      if (!mounted) return;

      final bookings = results[0] as List<Booking>;
      final conversations = results[1] as List<Conversation>;
      final jobs = results[2] as List<JobPost>;

      // Bookings: seed seen IDs on first load (or after user visits tab)
      final pendingProviderBookingIds = bookings
          .where((b) => b.workerUserId == myId && b.status == 'pending')
          .map((b) => b.id)
          .toSet();
      if (!_bookingInitDone) {
        _seenBookingIds.addAll(pendingProviderBookingIds);
        _bookingInitDone = true;
      }
      final bookingBadge = pendingProviderBookingIds.difference(_seenBookingIds).length;

      // Unread conversations: seed on first load (or after user visits tab)
      if (!_shellInitDone) {
        for (final c in conversations) {
          _shellLastSeen[c.id] = c.updatedAt;
        }
        _shellInitDone = true;
      }
      var inboxBadge = 0;
      for (final c in conversations) {
        // Skip conversations where the current user sent the last message
        if (c.lastSenderId == myId) continue;
        final seen = _shellLastSeen[c.id];
        if (seen == null || c.updatedAt.isAfter(seen)) inboxBadge++;
      }

      // Jobs: seed seen IDs on first load (or after user visits tab)
      final jobsWithPendingIds = jobs
          .where((j) => j.clientUserId == myId && j.pendingOfferCount > 0)
          .map((j) => j.id)
          .toSet();
      if (!_jobsInitDone) {
        _seenJobPostIds.addAll(jobsWithPendingIds);
        _jobsInitDone = true;
      }
      final jobsBadge = jobsWithPendingIds.difference(_seenJobPostIds).length;

      setState(() {
        _bookingBadge = bookingBadge;
        _inboxBadge = inboxBadge;
        _jobsBadge = jobsBadge;
      });
    } catch (_) {}
  }

  void _onDestinationSelected(int value) {
    setState(() => _index = value);
    if (_isAdmin) return;

    if (value == _kBookings) {
      _seenBookingIds.clear();
      _bookingInitDone = false;
      _shellLastSeen.clear();
      _shellInitDone = false;
      setState(() {
        _bookingBadge = 0;
        _inboxBadge = 0;
      });
      // Re-seed immediately so badges don't reappear on next timer tick
      _loadBadges();
    }

    if (value == _kJobs) {
      _seenJobPostIds.clear();
      _jobsInitDone = false;
      setState(() => _jobsBadge = 0);
      // Re-seed immediately
      _loadBadges();
    }
  }

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    setState(() {
      _dragging = true;
      _fabX = (_fabX! + d.delta.dx).clamp(0, screen.width - _kFabSize);
      _fabY = (_fabY! + d.delta.dy).clamp(0, screen.height - _kFabSize);
    });
  }

  void _onPanEnd(DragEndDetails d, Size screen) {
    // Snap to nearest horizontal edge
    final snapX = _fabX! < screen.width / 2 ? 12.0 : screen.width - _kFabSize - 12.0;
    setState(() {
      _dragging = false;
      _fabX = snapX;
    });
  }

  Widget _newBadgedIcon(Widget icon, bool hasNew) => Badge(
        isLabelVisible: hasNew,
        label: const Text('NEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.red,
        child: icon,
      );

  Widget _badgedIcon(Widget icon, int count) => Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: icon,
      );

  @override
  Widget build(BuildContext context) {
    final hasNewBookings = (_bookingBadge + _inboxBadge) > 0;

    final pages = _isAdmin
        ? [
            DashboardScreen(api: widget.api, onLogout: widget.onLogout),
            DiscoverScreen(
                api: widget.api, onLogout: widget.onLogout, readOnly: true),
            JobsScreen(api: widget.api, readOnly: true),
            ProfileScreen(
                api: widget.api,
                openDashboard: () => setState(() => _index = 0),
                onLogout: widget.onLogout),
          ]
        : [
            DiscoverScreen(api: widget.api, onLogout: widget.onLogout),
            BookingsScreen(
                api: widget.api,
                openJobs: () => setState(() => _index = _kJobs),
                pendingBookingCount: _bookingBadge),
            JobsScreen(api: widget.api),
            ProfileScreen(api: widget.api),
          ];

    if (_index >= pages.length) _index = 0;

    final screen = MediaQuery.of(context).size;

    // Set default position bottom-left above nav bar
    _fabX ??= 12.0;
    _fabY ??= screen.height - _kFabSize - 90;

    final navBar = SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: _index,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _onDestinationSelected,
        destinations: _isAdmin
            ? const [
                NavigationDestination(
                    icon: Icon(Icons.shield_outlined),
                    selectedIcon: Icon(Icons.shield),
                    label: 'Admin'),
                NavigationDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search),
                    label: 'Explore'),
                NavigationDestination(
                    icon: Icon(Icons.work_outline),
                    selectedIcon: Icon(Icons.work),
                    label: 'Job Posts'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profile'),
              ]
            : [
                const NavigationDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search),
                    label: 'Explore'),
                NavigationDestination(
                    icon: _newBadgedIcon(const Icon(Icons.calendar_month_outlined), hasNewBookings),
                    selectedIcon: _newBadgedIcon(const Icon(Icons.calendar_month), hasNewBookings),
                    label: 'Bookings'),
                NavigationDestination(
                    icon: _badgedIcon(const Icon(Icons.work_outline), _jobsBadge),
                    selectedIcon: _badgedIcon(const Icon(Icons.work), _jobsBadge),
                    label: 'Jobs'),
                const NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profile'),
              ],
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (!_isAdmin)
            Positioned(
              left: _fabX,
              top: _fabY,
              child: GestureDetector(
                onPanUpdate: (d) => _onPanUpdate(d, screen),
                onPanEnd: (d) => _onPanEnd(d, screen),
                onTap: _dragging
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => UserAIScreen(api: widget.api)),
                        ),
                child: AnimatedScale(
                  scale: _dragging ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(_dragging ? 80 : 40),
                          blurRadius: _dragging ? 12 : 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/hanapgawa-shaped-white-background-logo.png',
                      width: _kFabSize,
                      height: _kFabSize,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: navBar,
    );
  }
}
