import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../ai/user_ai_screen.dart';
import '../bookings/bookings_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../discover/discover_screen.dart';
import '../discover/feed_card.dart';
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
  var _discoverRefreshKey = 0;

  // Draggable FAB position (initialized in build once we have screen size)
  double? _fabX;
  double? _fabY;
  bool _dragging = false;

  // Tour keys — invisible anchors overlaid on nav tabs + AppBar buttons in child screens
  final _exploreTabKey = GlobalKey();
  final _bookingsTabKey = GlobalKey();
  final _jobsTabKey = GlobalKey();
  final _profileTabKey = GlobalKey();
  final _aiButtonKey = GlobalKey();
  final _notificationKey = GlobalKey();
  final _suggestedKey = GlobalKey();

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
    if (!widget.api.hasSeenAppTour) {
      // Delay so the nav bar and AppBar are fully laid out before we measure keys
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 800), _startTour);
      });
    }
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
    if (value != 0) FeedCard.stopAllMusic();
    if (value == 0) _discoverRefreshKey++;
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

  void _startTour() {
    if (!mounted) return;
    final isAdmin = _isAdmin;

    ContentAlign _top = ContentAlign.top;

    final targets = <TargetFocus>[
      TargetFocus(
        identify: 'explore',
        keyTarget: _exploreTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: _top,
            builder: (_, __) => _TourCard(
              icon: Icons.search_outlined,
              title: 'Explore',
              body: 'Browse posts, jobs, and services from people you follow. '
                  'Swipe through stories, like posts, and discover new workers near you.',
            ),
          ),
        ],
      ),
      if (!isAdmin)
        TargetFocus(
          identify: 'suggested',
          keyTarget: _suggestedKey,
          alignSkip: Alignment.topRight,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => _TourCard(
                icon: Icons.person_add_outlined,
                title: 'Find People to Follow',
                body: 'Tap here to see suggested workers and clients. '
                    'Follow them to see their posts in your feed.',
              ),
            ),
          ],
        ),
      if (!isAdmin)
        TargetFocus(
          identify: 'notification',
          keyTarget: _notificationKey,
          alignSkip: Alignment.topRight,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (_, __) => _TourCard(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                body: 'See who liked or commented on your posts, new bookings, '
                    'job offers, and people who followed you.',
              ),
            ),
          ],
        ),
      if (!isAdmin)
        TargetFocus(
          identify: 'bookings',
          keyTarget: _bookingsTabKey,
          alignSkip: Alignment.topRight,
          contents: [
            TargetContent(
              align: _top,
              builder: (_, __) => _TourCard(
                icon: Icons.calendar_month_outlined,
                title: 'Bookings',
                body: 'Manage your service bookings and chat with clients or workers. '
                    'You\'ll see a badge here when new booking requests arrive.',
              ),
            ),
          ],
        ),
      TargetFocus(
        identify: 'jobs',
        keyTarget: _jobsTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: _top,
            builder: (_, __) => _TourCard(
              icon: Icons.work_outline,
              title: 'Jobs',
              body: isAdmin
                  ? 'View and moderate all job posts on the platform.'
                  : 'Browse job listings and apply, or post a job for workers to apply to. '
                      'Offers are tracked here.',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'profile',
        keyTarget: _profileTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: _top,
            builder: (_, __) => _TourCard(
              icon: Icons.person_outline,
              title: 'Your Profile',
              body: 'Edit your bio, portfolio, and services. '
                  'Clients and workers can find you by visiting your profile.',
            ),
          ),
        ],
      ),
      if (!isAdmin)
        TargetFocus(
          identify: 'ai',
          keyTarget: _aiButtonKey,
          shape: ShapeLightFocus.Circle,
          alignSkip: Alignment.topRight,
          contents: [
            TargetContent(
              align: _top,
              builder: (_, __) => _TourCard(
                icon: Icons.auto_awesome_outlined,
                title: 'HanapGawa AI',
                body: 'Need help? Tap the logo button anytime to ask AI for '
                    'job recommendations, career advice, or help writing your bio.',
              ),
            ),
          ],
        ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.82,
      paddingFocus: 12,
      hideSkip: false,
      skipWidget: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(220),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Skip tour',
            style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      ),
      onFinish: () => widget.api.markAppTourSeen(),
      onSkip: () {
        widget.api.markAppTourSeen();
        return true;
      },
    ).show(context: context);
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
                api: widget.api,
                onLogout: widget.onLogout,
                readOnly: true,
                refreshKey: _discoverRefreshKey,
                notificationKey: _notificationKey,
                suggestedKey: _suggestedKey),
            JobsScreen(api: widget.api, readOnly: true),
            ProfileScreen(
                api: widget.api,
                openDashboard: () => setState(() => _index = 0),
                onLogout: widget.onLogout),
          ]
        : [
            DiscoverScreen(
                api: widget.api,
                onLogout: widget.onLogout,
                refreshKey: _discoverRefreshKey,
                notificationKey: _notificationKey,
                suggestedKey: _suggestedKey),
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

    final tabCount = _isAdmin ? 4 : 4;
    final tabWidth = screen.width / tabCount;
    // Invisible containers anchored over each nav tab for tour highlights
    final navKeyOverlay = Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 70 + MediaQuery.of(context).padding.bottom,
      child: Row(
        children: _isAdmin
            ? [
                SizedBox(key: _exploreTabKey, width: tabWidth),
                SizedBox(width: tabWidth),
                SizedBox(key: _jobsTabKey, width: tabWidth),
                SizedBox(key: _profileTabKey, width: tabWidth),
              ]
            : [
                SizedBox(key: _exploreTabKey, width: tabWidth),
                SizedBox(key: _bookingsTabKey, width: tabWidth),
                SizedBox(key: _jobsTabKey, width: tabWidth),
                SizedBox(key: _profileTabKey, width: tabWidth),
              ],
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          navKeyOverlay,
          if (!_isAdmin)
            Positioned(
              left: _fabX,
              top: _fabY,
              child: GestureDetector(
                key: _aiButtonKey,
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

class _TourCard extends StatelessWidget {
  const _TourCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6B46C1).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF6B46C1), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: Color(0xFF6B46C1))),
            ),
          ]),
          const SizedBox(height: 10),
          Text(body,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black87, height: 1.45)),
          const SizedBox(height: 12),
          const Text('Tap anywhere to continue →',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
