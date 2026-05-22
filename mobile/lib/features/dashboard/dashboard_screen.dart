import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../features/bookings/booking_card.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/info_pill.dart';
import '../../shared/widgets/status_chip.dart';
import '../bookings/chat_screen.dart';
import 'admin_panel.dart';
import 'provider_profile_form.dart';
import 'service_listing_form.dart';
import 'stats_row.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api, this.onLogout});
  final MarketplaceApi api;
  final Future<void> Function()? onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  var _segment = 0;
  var _bookings = <Booking>[];
  var _myJobPosts = <JobPost>[];
  var _myJobOffers = <({JobPost job, List<JobOffer> offers})>[];
  var _adminSummary = AdminSummary.empty();
  var _adminUsers = <SessionUser>[];
  var _reports = <ReportItem>[];
  var _categories = <ServiceCategory>[];
  var _isOffline = false;
  var _loading = false;
  var _refreshing = false;
  var _loadError = '';
  final _displayName = TextEditingController();
  final _category = TextEditingController();
  final _services = TextEditingController();
  final _serviceTitle = TextEditingController();
  final _serviceDescription = TextEditingController();
  final _priceMin = TextEditingController(text: '800');
  final _priceMax = TextEditingController(text: '2500');
  var _municipality = 'Bongao';
  var _allowDirectBooking = false;

  bool get _isAdmin => widget.api.storedUser?.role == 'admin';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _segment = 4;
    _displayName.text = widget.api.storedUser?.fullName ?? '';
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _category.dispose();
    _services.dispose();
    _serviceTitle.dispose();
    _serviceDescription.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    super.dispose();
  }

  // For admin: all bookings. For regular users: bookings where they are the provider.
  List<Booking> get _incoming {
    final user = widget.api.storedUser;
    if (user?.role == 'admin') return _bookings;
    return _bookings.where((b) => b.workerUserId == user?.id).toList();
  }


  Future<void> _load() async {
    _loadError = '';
    if (_isAdmin) {
      await _loadAdmin();
      return;
    }

    // Cache first — show immediately if available
    final cachedBookings = await LocalDb.instance.getCachedBookings();
    final cachedJobs = await LocalDb.instance.getCachedJobs();
    if (cachedBookings.isNotEmpty || cachedJobs.isNotEmpty) {
      final allJobs = cachedJobs.map(JobPost.fromJson).toList();
      final userId = widget.api.storedUser?.id;
      if (mounted) setState(() {
        _bookings = cachedBookings.map(Booking.fromJson).toList();
        _myJobPosts = allJobs.where((j) => j.clientUserId == userId).toList();
        _myJobOffers = _myJobPosts.map((j) => (job: j, offers: <JobOffer>[])).toList();
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = true);
    }

    if (mounted) setState(() => _refreshing = true);
    try {
      final results = await Future.wait([
        widget.api.getMyBookings(),
        widget.api.getJobs(),
      ]);
      _bookings = results[0] as List<Booking>;
      final allJobs = results[1] as List<JobPost>;
      final userId = widget.api.storedUser?.id;
      _myJobPosts = allJobs.where((j) => j.clientUserId == userId).toList();
      _myJobOffers = [];
      for (final job in _myJobPosts) {
        try {
          final detail = await widget.api.getJobDetail(job.id);
          _myJobOffers.add((job: detail.jobPost, offers: detail.offers));
        } catch (_) {
          _myJobOffers.add((job: job, offers: []));
        }
      }
      unawaited(LocalDb.instance.cacheBookings(_bookings.map((b) => b.toJson()).toList()));
      unawaited(LocalDb.instance.cacheJobs(allJobs.map((j) => j.toJson()).toList()));
    } catch (error) {
      if (_bookings.isEmpty) _loadError = friendlyError(error);
    }
    if (mounted) setState(() { _loading = false; _refreshing = false; });
  }

  Future<void> _loadAdmin() async {
    // Cache first — show immediately if available
    final cached = await Future.wait([
      LocalDb.instance.getCachedAdminData('summary'),
      LocalDb.instance.getCachedAdminData('users'),
      LocalDb.instance.getCachedAdminData('reports'),
      LocalDb.instance.getCachedAdminData('categories'),
      LocalDb.instance.getCachedBookings(),
      LocalDb.instance.getCachedJobs(),
    ]);
    final hasCached = cached[0] != null || (cached[4] as List).isNotEmpty || (cached[5] as List).isNotEmpty;
    if (hasCached && mounted) {
      if (cached[0] != null) _adminSummary = AdminSummary.fromJson(Map<String, dynamic>.from(cached[0] as Map));
      if (cached[1] != null) _adminUsers = (cached[1] as List).map((u) => SessionUser.fromJson(Map<String, dynamic>.from(u as Map))).toList();
      if (cached[2] != null) _reports = (cached[2] as List).map((r) => ReportItem.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      if (cached[3] != null) _categories = (cached[3] as List).map((c) => ServiceCategory.fromJson(Map<String, dynamic>.from(c as Map))).toList();
      _bookings = (cached[4] as List<Map<String, dynamic>>).map(Booking.fromJson).toList();
      _myJobPosts = (cached[5] as List<Map<String, dynamic>>).map(JobPost.fromJson).toList();
      setState(() => _loading = false);
    } else {
      if (mounted) setState(() => _loading = true);
    }

    if (mounted) setState(() => _refreshing = true);
    try {
      final results = await Future.wait([
        widget.api.getAdminSummary(),
        widget.api.getAdminUsers(),
        widget.api.getReports(),
        widget.api.getAdminCategories(),
        widget.api.getAllBookings(),
        widget.api.getJobs(),
      ]);
      _adminSummary = results[0] as AdminSummary;
      _adminUsers = results[1] as List<SessionUser>;
      _reports = results[2] as List<ReportItem>;
      _categories = results[3] as List<ServiceCategory>;
      _bookings = results[4] as List<Booking>;
      _myJobPosts = results[5] as List<JobPost>;
      _isOffline = false;
      unawaited(LocalDb.instance.cacheAdminData('summary', _adminSummary.toJson()));
      unawaited(LocalDb.instance.cacheAdminData('users', _adminUsers.map((u) => u.toJson()).toList()));
      unawaited(LocalDb.instance.cacheAdminData('reports', _reports.map((r) => r.toJson()).toList()));
      unawaited(LocalDb.instance.cacheAdminData('categories', _categories.map((c) => c.toJson()).toList()));
      unawaited(LocalDb.instance.cacheBookings(_bookings.map((b) => b.toJson()).toList()));
      unawaited(LocalDb.instance.cacheJobs(_myJobPosts.map((j) => j.toJson()).toList()));
    } catch (e) {
      if (_adminSummary == AdminSummary.empty() && _adminUsers.isEmpty) {
        _isOffline = true;
        _loadError = friendlyError(e);
      }
    }
    if (mounted) setState(() { _loading = false; _refreshing = false; });
  }

  Future<T> _safeLoad<T>(String label, Future<T> request, T fallback,
      {bool reportError = true}) async {
    try {
      return await request;
    } catch (error) {
      final message = friendlyError(error);
      if (reportError) _loadError = '$label: $message';
      return fallback;
    }
  }

  Future<void> _saveProfile() async {
    await widget.api.upsertProviderProfile(ProviderProfilePayload(
      displayName: _displayName.text.trim(),
      category: _category.text.trim(),
      municipality: _municipality,
      services: splitCsv(_services.text),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker profile saved.')));
    }
  }

  Future<void> _saveService() async {
    await widget.api.createServiceListing(ServiceListingPayload(
      title: _serviceTitle.text.trim(),
      category:
          _category.text.trim().isEmpty ? 'Carpentry' : _category.text.trim(),
      municipality: _municipality,
      description: _serviceDescription.text.trim(),
      priceMin: int.tryParse(_priceMin.text) ?? 0,
      priceMax: int.tryParse(_priceMax.text) ?? 0,
      estimatedDuration: '2 to 5 hours',
      requirements: splitCsv(_services.text),
      availability: const [],
      allowDirectBooking: _allowDirectBooking,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service listing published.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = [
      if (!_isAdmin)
        const ButtonSegment(
            value: 0,
            icon: Icon(Icons.calendar_month_outlined),
            label: Text('Bookings')),
      if (!_isAdmin)
        const ButtonSegment(
            value: 1,
            icon: Icon(Icons.newspaper_outlined),
            label: Text('Jobs')),
      if (!_isAdmin)
        const ButtonSegment(
            value: 2, icon: Icon(Icons.person_outline), label: Text('Profile')),
      if (!_isAdmin)
        const ButtonSegment(
            value: 3, icon: Icon(Icons.work_outline), label: Text('Services')),
      if (_isAdmin)
        const ButtonSegment(
            value: 4, icon: Icon(Icons.shield_outlined), label: Text('Admin')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Admin Dashboard' : 'Dashboard'),
        actions: const [],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isAdmin) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  segments: segments,
                  selected: {_segment},
                  onSelectionChanged: (value) =>
                      setState(() => _segment = value.first),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_loading) const SkeletonDashboard(),
            if (!_loading && _loadError.isNotEmpty) ...[
              AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Could not load all dashboard data',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(_loadError, style: const TextStyle(color: appMuted)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ]),
              ),
            ],
            if (!_loading && _segment == 0) ...[
              StatsRow(bookings: _incoming),
              const SizedBox(height: 12),
              if (_incoming.isEmpty)
                EmptyState(
                    icon: Icons.calendar_month_outlined,
                    title: _isAdmin
                        ? 'No bookings yet'
                        : 'No incoming bookings yet',
                    subtitle: _isAdmin
                        ? 'All platform bookings will appear here for review.'
                        : null),
              ..._incoming.map((booking) => BookingCard(
                    booking: booking,
                    myId: widget.api.storedUser?.id ?? '',
                    onStatus: (status) async {
                      await widget.api.updateBookingStatus(booking.id, status);
                      await _load();
                    },
                    onMessage: () {},
                  )),
            ],
            if (!_loading && _segment == 1) ...[
              _DashboardJobsPanel(
                api: widget.api,
                jobOffers: _myJobOffers,
                onReload: _load,
              ),
            ],
            if (!_loading && _segment == 2)
              ProviderProfileForm(
                displayName: _displayName,
                category: _category,
                services: _services,
                municipality: _municipality,
                onMunicipality: (value) =>
                    setState(() => _municipality = value),
                onSave: _saveProfile,
              ),
            if (!_loading && _segment == 3)
              ServiceListingForm(
                title: _serviceTitle,
                description: _serviceDescription,
                category: _category,
                priceMin: _priceMin,
                priceMax: _priceMax,
                municipality: _municipality,
                onMunicipality: (value) =>
                    setState(() => _municipality = value),
                onSave: _saveService,
                allowDirectBooking: _allowDirectBooking,
                onAllowDirectBooking: (value) =>
                    setState(() => _allowDirectBooking = value),
              ),
            if (!_loading && _segment == 4 && _isAdmin) ...[
              if (_isOffline)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.cloud_off_outlined, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline — showing cached data. Write actions will sync when online.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              AdminPanel(
                api: widget.api,
                summary: _adminSummary,
                users: _adminUsers,
                reports: _reports,
                categories: _categories,
                bookings: _bookings,
                jobs: _myJobPosts,
                isOffline: _isOffline,
                reload: _load,
              ),
            ],
          ],
        ),
      )),
        ],
      ),
    );
  }
}


// â”€â”€â”€ Dashboard Jobs Panel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DashboardJobsPanel extends StatefulWidget {
  const _DashboardJobsPanel({
    required this.api,
    required this.jobOffers,
    required this.onReload,
  });
  final MarketplaceApi api;
  final List<({JobPost job, List<JobOffer> offers})> jobOffers;
  final Future<void> Function() onReload;

  @override
  State<_DashboardJobsPanel> createState() => _DashboardJobsPanelState();
}

class _DashboardJobsPanelState extends State<_DashboardJobsPanel> {
  final _busy = <String>{};

  int _pendingCount(List<JobOffer> offers) =>
      offers.where((o) => o.status == 'pending').length;

  Future<void> _acceptOffer(JobPost job, JobOffer offer) async {
    final priceText = offer.proposedPrice != null
        ? 'Proposed price: P${offer.proposedPrice}'
        : 'No price proposed';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Accept offer?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Worker: ${offer.providerName ?? 'Worker'}'),
          const SizedBox(height: 4),
          Text(priceText),
          const SizedBox(height: 12),
          const Text(
            'Accepting creates a Booking and closes this job post.',
            style: TextStyle(color: appMuted, fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(offer.id));
    try {
      await widget.api.acceptJobOffer(job.id, offer.id);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Booking created'),
          content: const Text(
              'The booking has been created. Check your Bookings tab to manage it.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it')),
          ],
        ),
      );
      await widget.onReload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(offer.id));
    }
  }

  Future<void> _declineOffer(JobPost job, JobOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline offer?'),
        content: Text(
            'Decline the offer from ${offer.providerName ?? 'this provider'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Decline')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(offer.id));
    try {
      await widget.api.declineJobOffer(job.id, offer.id);
      await widget.onReload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(offer.id));
    }
  }

  void _openChat(String targetUserId, String targetName, String jobTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _StartChatFromDashboard(
                api: widget.api,
                targetUserId: targetUserId,
                targetName: targetName,
                jobTitle: jobTitle,
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jobOffers.isEmpty) {
      return const EmptyState(
        icon: Icons.work_outline,
        title: 'No job posts yet',
        subtitle: 'Post a job from the Jobs tab to receive offers.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Job Posts (${widget.jobOffers.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...widget.jobOffers.map((entry) => _JobOfferGroup(
              job: entry.job,
              offers: entry.offers,
              busy: _busy,
              pendingCount: _pendingCount(entry.offers),
              onAccept: (offer) => _acceptOffer(entry.job, offer),
              onDecline: (offer) => _declineOffer(entry.job, offer),
              onMessage: (offer) => _openChat(offer.providerUserId,
                  offer.providerName ?? 'Worker', entry.job.title),
            )),
      ],
    );
  }
}

class _JobOfferGroup extends StatefulWidget {
  const _JobOfferGroup({
    required this.job,
    required this.offers,
    required this.busy,
    required this.pendingCount,
    required this.onAccept,
    required this.onDecline,
    required this.onMessage,
  });
  final JobPost job;
  final List<JobOffer> offers;
  final Set<String> busy;
  final int pendingCount;
  final void Function(JobOffer) onAccept;
  final void Function(JobOffer) onDecline;
  final void Function(JobOffer) onMessage;

  @override
  State<_JobOfferGroup> createState() => _JobOfferGroupState();
}

class _JobOfferGroupState extends State<_JobOfferGroup> {
  var _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.pendingCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final isOpen = job.status == 'open';

    return AppCard(
      accentColor: isOpen ? appPrimary : appMuted,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Job header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 12, runSpacing: 4, children: [
                      InfoPill(icon: Icons.work_outline, label: job.category),
                      InfoPill(
                          icon: Icons.place_outlined, label: job.municipality),
                    ]),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusChip(status: job.status),
              const SizedBox(height: 4),
              if (widget.offers.isNotEmpty)
                _OfferBadge(
                    total: widget.offers.length, pending: widget.pendingCount),
            ]),
            const SizedBox(width: 4),
            Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: appMuted,
            ),
          ]),
        ),
        // Offers section
        if (_expanded) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (widget.offers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No offers yet.',
                  style: TextStyle(color: appMuted, fontSize: 13)),
            )
          else
            ...widget.offers.map((offer) => _DashboardOfferTile(
                  offer: offer,
                  isJobOpen: isOpen,
                  isBusy: widget.busy.contains(offer.id),
                  onAccept: () => widget.onAccept(offer),
                  onDecline: () => widget.onDecline(offer),
                  onMessage: () => widget.onMessage(offer),
                )),
        ],
      ]),
    );
  }
}

class _OfferBadge extends StatelessWidget {
  const _OfferBadge({required this.total, required this.pending});
  final int total;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pending > 0 ? appPrimary.withAlpha(20) : appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: pending > 0 ? appPrimary.withAlpha(60) : appBorder),
      ),
      child: Text(
        pending > 0
            ? '$pending new offer${pending > 1 ? 's' : ''}'
            : '$total offer${total > 1 ? 's' : ''}',
        style: TextStyle(
          color: pending > 0 ? appPrimary : appMuted,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DashboardOfferTile extends StatelessWidget {
  const _DashboardOfferTile({
    required this.offer,
    required this.isJobOpen,
    required this.isBusy,
    required this.onAccept,
    required this.onDecline,
    required this.onMessage,
  });
  final JobOffer offer;
  final bool isJobOpen;
  final bool isBusy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onMessage;

  Color get _statusColor {
    switch (offer.status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
      case 'declined':
        return Colors.red;
      default:
        return appPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = offer.status == 'pending';
    final isAccepted = offer.status == 'accepted';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAccepted
            ? Colors.green.withAlpha(8)
            : (isPending ? appPrimary.withAlpha(8) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAccepted
              ? Colors.green.withAlpha(40)
              : (isPending ? appPrimary.withAlpha(40) : Colors.grey.shade200),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Provider row
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [appPrimary, Colors.blue.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (offer.providerName ?? 'P')
                    .split(' ')
                    .where((p) => p.isNotEmpty)
                    .take(2)
                    .map((p) => p[0])
                    .join()
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(offer.providerName ?? 'Worker',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text(timeAgo(offer.createdAt),
                  style: const TextStyle(color: appMuted, fontSize: 11)),
            ]),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              offer.status[0].toUpperCase() + offer.status.substring(1),
              style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Message
        Text(offer.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.4)),
        // Price
        if (offer.proposedPrice != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withAlpha(50)),
            ),
            child: Text(
              'P${offer.proposedPrice}',
              style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 13),
            ),
          ),
        ],
        // Booking created notice
        if (isAccepted) ...[
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
            SizedBox(width: 4),
            Text('Booking created',
                style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
        // Action buttons (only for pending offers on open jobs)
        if (isPending && isJobOpen) ...[
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(
              onPressed: isBusy ? null : onMessage,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.message_outlined, size: 14),
              label: const Text('Message', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: isBusy ? null : onDecline,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Decline', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isBusy ? null : onAccept,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Accept', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ],
      ]),
    );
  }
}

// â”€â”€â”€ Start Chat From Dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StartChatFromDashboard extends StatefulWidget {
  const _StartChatFromDashboard({
    required this.api,
    required this.targetUserId,
    required this.targetName,
    required this.jobTitle,
  });
  final MarketplaceApi api;
  final String targetUserId;
  final String targetName;
  final String jobTitle;

  @override
  State<_StartChatFromDashboard> createState() =>
      _StartChatFromDashboardState();
}

class _StartChatFromDashboardState extends State<_StartChatFromDashboard> {
  var _loading = true;
  Conversation? _conversation;

  static final _empty = Conversation(
    id: '',
    clientUserId: '',
    providerUserId: '',
    lastMessagePreview: '',
    updatedAt: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _findOrCreate();
  }

  Future<void> _findOrCreate() async {
    try {
      final all = await widget.api.getMyConversations();
      final existing = all.firstWhere(
        (c) =>
            c.clientUserId == widget.targetUserId ||
            c.providerUserId == widget.targetUserId,
        orElse: () => _empty,
      );
      if (existing.id.isNotEmpty) {
        if (mounted) {
          setState(() {
            _conversation = existing;
            _loading = false;
          });
        }
        return;
      }
      await widget.api.startInquiry(
        widget.targetUserId,
        'Hi! Regarding your offer on my job post: ${widget.jobTitle}',
      );
      final updated = await widget.api.getMyConversations();
      final created = updated.firstWhere(
        (c) =>
            c.clientUserId == widget.targetUserId ||
            c.providerUserId == widget.targetUserId,
        orElse: () => _empty,
      );
      if (mounted) {
        setState(() {
          _conversation = created;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e))));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.targetName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_conversation == null || _conversation!.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.targetName)),
        body: const Center(child: Text('Could not open conversation.')),
      );
    }
    return ChatScreen(
        api: widget.api,
        conversation: _conversation!,
        title: widget.targetName);
  }
}
