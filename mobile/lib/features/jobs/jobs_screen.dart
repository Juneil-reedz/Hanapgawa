import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/constants.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/info_pill.dart';
import '../../shared/widgets/report_sheet.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/status_chip.dart';
import '../bookings/chat_screen.dart';
import '../discover/booking_sheet.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.api, this.readOnly = false});
  final MarketplaceApi api;
  final bool readOnly;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  var _segment = 0;
  var _allJobs = <JobPost>[];
  var _reviews = <ReviewItem>[];
  var _reports = <ReportItem>[];
  var _activeBookings = <Booking>[];
  var _loading = false;
  var _refreshing = false;
  var _message = '';
  ProviderDetail? _myWorkerProfile;

  // Browse filters
  final _searchCtrl = TextEditingController();
  var _filterCategory = '';
  var _filterMunicipality = '';
  var _filterBudgetMax = 0; // 0 = any

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 1. Show cached jobs immediately
    if (_allJobs.isEmpty) {
      final cached = await LocalDb.instance.getCachedJobs();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _allJobs = cached.map(JobPost.fromJson).toList();
          _message = '';
        });
      } else if (mounted) {
        setState(() => _loading = true);
      }
    }
    if (mounted) setState(() => _refreshing = true);

    // 2. Fetch fresh from network
    try {
      final myId = widget.api.storedUser?.id ?? '';
      final futureJobs = widget.api.getJobs();
      final futureReviews = !widget.readOnly && myId.isNotEmpty
          ? widget.api.getProviderReviews(myId)
          : Future.value(<ReviewItem>[]);
      final futureReports = widget.readOnly
          ? widget.api.getReports()
          : Future.value(<ReportItem>[]);
      final futureBookings = !widget.readOnly && myId.isNotEmpty
          ? widget.api.getMyBookings().onError((_, __) => <Booking>[])
          : Future.value(<Booking>[]);
      final futureProfile = !widget.readOnly && myId.isNotEmpty
          ? widget.api
              .getProviderDetail(myId)
              .then<ProviderDetail?>((v) => v)
              .onError((_, __) => null)
          : Future<ProviderDetail?>.value(null);

      final jobs = await futureJobs;
      final reviews = await futureReviews;
      final reports = await futureReports;
      final bookings = await futureBookings;
      final profile = await futureProfile;

      const activeStatuses = {'pending', 'accepted', 'in_progress'};
      if (mounted) {
        setState(() {
          _allJobs = jobs;
          _reviews = reviews;
          _reports = reports;
          _activeBookings =
              bookings.where((b) => activeStatuses.contains(b.status)).toList();
          _myWorkerProfile = profile;
          _message = '';
          _loading = false;
          _refreshing = false;
        });
        unawaited(LocalDb.instance.cacheJobs(jobs.map((j) => j.toJson()).toList()));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        if (_allJobs.isEmpty) _message = friendlyError(error);
        _loading = false;
      });
    }
  }

  String? _bookingStatusFor(JobPost job) {
    try {
      return _activeBookings
          .firstWhere((b) => b.serviceListingId == job.id)
          .status;
    } catch (_) {
      return null;
    }
  }

  List<JobPost> get _myPosts {
    final userId = widget.api.storedUser?.id;
    return _allJobs.where((j) => j.clientUserId == userId).toList();
  }

  List<JobPost> get _browsePosts {
    final userId = widget.api.storedUser?.id;
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allJobs.where((j) {
      if (j.clientUserId == userId || j.status != 'open') return false;
      if (q.isNotEmpty &&
          !j.title.toLowerCase().contains(q) &&
          !j.description.toLowerCase().contains(q) &&
          !j.category.toLowerCase().contains(q)) return false;
      if (_filterCategory.isNotEmpty && j.category != _filterCategory) {
        return false;
      }
      if (_filterMunicipality.isNotEmpty &&
          j.municipality != _filterMunicipality) return false;
      if (_filterBudgetMax > 0 && (j.budgetMin ?? 0) > _filterBudgetMax) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> get _availableCategories {
    final cats = _allJobs.map((j) => j.category).toSet().toList()..sort();
    return cats;
  }

  // AI Job Recommendation — sorted jobs matching the worker's profile
  List<JobPost> get _recommendedJobs {
    final profile = _myWorkerProfile;
    if (profile == null) return const [];
    final scored = _browsePosts
        .map((job) {
          int score = 0;
          if (job.category == profile.category) score += 50;
          if (job.municipality == profile.municipality) score += 30;
          if ((job.budgetMin ?? 0) > 0) score += 10;
          return (job: job, score: score);
        })
        .where((e) => e.score >= 50)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(3).map((e) => e.job).toList();
  }

  void _openCreateSheet({JobPost? editPost}) {
    final outerContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _JobPostSheet(
        api: widget.api,
        editPost: editPost,
        onSaved: () {
          Navigator.pop(sheetCtx);
          ScaffoldMessenger.of(outerContext).showSnackBar(
            const SnackBar(
              content: Text('Job post saved!'),
              duration: Duration(seconds: 3),
            ),
          );
          _load();
        },
      ),
    );
  }

  void _openJobDetail(JobPost job) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => JobDetailScreen(
            api: widget.api,
            job: job,
            onRefresh: _load,
            readOnly: widget.readOnly,
            reports: _reports,
            existingBookingStatus: _bookingStatusFor(job)),
      ),
    );
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _filterCategory = '';
      _filterMunicipality = '';
      _filterBudgetMax = 0;
    });
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _filterCategory.isNotEmpty ||
      _filterMunicipality.isNotEmpty ||
      _filterBudgetMax > 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const ButtonSegment(
          value: 0, icon: Icon(Icons.search_outlined), label: Text('Browse')),
      if (!widget.readOnly)
        const ButtonSegment(
            value: 1,
            icon: Icon(Icons.person_outline),
            label: Text('My Posts')),
      if (!widget.readOnly)
        const ButtonSegment(
            value: 2, icon: Icon(Icons.star_outline), label: Text('Reviews')),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!widget.readOnly)
            IconButton(
              onPressed: _openCreateSheet,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Post a Job',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.readOnly) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  segments: tabs,
                  selected: {_segment},
                  onSelectionChanged: (value) =>
                      setState(() => _segment = value.first),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Browse search + filters
            if (_segment == 0) ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search jobs...',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchCtrl.clear())
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip(
                    label:
                        _filterCategory.isEmpty ? 'Category' : _filterCategory,
                    active: _filterCategory.isNotEmpty,
                    onTap: () => _showCategoryFilter(),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _filterMunicipality.isEmpty
                        ? 'Location'
                        : _filterMunicipality,
                    active: _filterMunicipality.isNotEmpty,
                    onTap: () => _showLocationFilter(),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _filterBudgetMax == 0
                        ? 'Budget'
                        : 'Under P$_filterBudgetMax',
                    active: _filterBudgetMax > 0,
                    onTap: () => _showBudgetFilter(),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
            ],
            if (_loading) const SkeletonJobList(),
            if (!_loading && _message.isNotEmpty)
              EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: _message,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Retry'))),
            if (!_loading && _message.isEmpty) ...[
              if (_segment == 0) ...[
                // ── AI Job Recommendation ───────────────────────────────────
                if (_recommendedJobs.isNotEmpty) ...[
                  _AIJobRecommendationBanner(
                    jobs: _recommendedJobs,
                    profile: _myWorkerProfile!,
                    onTap: _openJobDetail,
                  ),
                  const SizedBox(height: 8),
                ],
                if (_browsePosts.isEmpty)
                  EmptyState(
                    icon: Icons.search_outlined,
                    title: _hasActiveFilters
                        ? 'No jobs match your filters'
                        : 'No open job posts right now',
                    action: _hasActiveFilters
                        ? TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear filters'))
                        : null,
                  ),
                ..._browsePosts.map((job) {
                  final bStatus = _bookingStatusFor(job);
                  return _JobCard(
                    job: job,
                    isOwner: false,
                    onTap: () => _openJobDetail(job),
                    bookingStatus: bStatus,
                    onReport: !widget.readOnly && widget.api.token.isNotEmpty
                        ? () => showReportSheet(context,
                            api: widget.api,
                            reportedUserId: job.clientUserId,
                            contentLabel: 'this job post')
                        : null,
                    // Hide Book Now if there's already an active booking or in read-only (admin) mode
                    onBook: !widget.readOnly &&
                            job.postType == 'offering_service' &&
                            job.allowDirectBooking &&
                            widget.api.token.isNotEmpty &&
                            bStatus == null
                        ? () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => BookingSheet(
                                api: widget.api,
                                target: BookingTarget.fromJobPost(job),
                              ),
                            )
                        : null,
                  );
                }),
              ],
              if (_segment == 1) ...[
                if (_myPosts.isEmpty)
                  const EmptyState(
                    icon: Icons.newspaper_outlined,
                    title: 'No posts yet',
                    subtitle: 'Tap + above to create your first job post.',
                  ),
                ..._myPosts.map((job) => _JobCard(
                      job: job,
                      isOwner: true,
                      onTap: () => _openJobDetail(job),
                      onEdit: job.status == 'open'
                          ? () => _openCreateSheet(editPost: job)
                          : null,
                      onDelete: job.status != 'open'
                          ? () async {
                              if (!SyncService.instance.isOnline) {
                                await LocalDb.instance.queueAction(
                                    'delete_job_post', {'jobPostId': job.id});
                                _load();
                              } else {
                                try {
                                  await widget.api.deleteJobPost(job.id);
                                  _load();
                                } catch (e) {
                                  if (SyncService.isNetworkError(e)) {
                                    await LocalDb.instance.queueAction(
                                        'delete_job_post',
                                        {'jobPostId': job.id});
                                    _load();
                                  }
                                }
                              }
                            }
                          : null,
                    )),
              ],
              if (_segment == 2) ...[
                _ReviewsSummaryCard(reviews: _reviews),
                const SizedBox(height: 8),
                if (_reviews.isEmpty)
                  const EmptyState(
                    icon: Icons.star_outline,
                    title: 'No reviews yet',
                    subtitle:
                        'Reviews from clients will appear here after completed bookings.',
                  ),
                ..._reviews.map((r) => _ReviewCard(review: r)),
              ],
            ],
          ],
        ),
      )),
        ],
      ),
    );
  }

  void _showCategoryFilter() {
    final cats = _availableCategories;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('All Categories',
                style: TextStyle(fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.clear),
            onTap: () {
              setState(() => _filterCategory = '');
              Navigator.pop(ctx);
            },
          ),
          const Divider(height: 1),
          ...cats.map((c) => ListTile(
                title: Text(c),
                leading: Icon(
                  Icons.work_outline,
                  color: _filterCategory == c ? appPrimary : null,
                ),
                trailing: _filterCategory == c
                    ? const Icon(Icons.check, color: appPrimary)
                    : null,
                onTap: () {
                  setState(() => _filterCategory = c);
                  Navigator.pop(ctx);
                },
              )),
        ],
      ),
    );
  }

  void _showLocationFilter() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('All Locations',
                style: TextStyle(fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.clear),
            onTap: () {
              setState(() => _filterMunicipality = '');
              Navigator.pop(ctx);
            },
          ),
          const Divider(height: 1),
          ...municipalities.map((m) => ListTile(
                title: Text(m),
                leading: Icon(Icons.place_outlined,
                    color: _filterMunicipality == m ? appPrimary : null),
                trailing: _filterMunicipality == m
                    ? const Icon(Icons.check, color: appPrimary)
                    : null,
                onTap: () {
                  setState(() => _filterMunicipality = m);
                  Navigator.pop(ctx);
                },
              )),
        ],
      ),
    );
  }

  void _showBudgetFilter() {
    const options = [0, 500, 1000, 2500, 5000, 10000];
    final labels = [
      'Any',
      'Under P500',
      'Under P1,000',
      'Under P2,500',
      'Under P5,000',
      'Under P10,000'
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (_, i) => ListTile(
          title: Text(labels[i]),
          trailing: _filterBudgetMax == options[i]
              ? const Icon(Icons.check, color: appPrimary)
              : null,
          onTap: () {
            setState(() => _filterBudgetMax = options[i]);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }
}

class _ReviewsSummaryCard extends StatelessWidget {
  const _ReviewsSummaryCard({required this.reviews});
  final List<ReviewItem> reviews;

  double get _average {
    if (reviews.isEmpty) return 0;
    return reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;
  }

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) return const SizedBox.shrink();
    final avg = _average;
    final counts = List.generate(5, (i) {
      final star = 5 - i;
      return (star, reviews.where((r) => r.rating == star).length);
    });
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rating Overview',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(children: [
            Text(
              avg.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 40, fontWeight: FontWeight.w900, color: appPrimary),
            ),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < avg.round() ? Icons.star : Icons.star_border,
                  size: 16,
                  color: Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                style: const TextStyle(color: appMuted, fontSize: 12)),
          ]),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: counts.map((entry) {
                final star = entry.$1;
                final count = entry.$2;
                final pct = reviews.isEmpty ? 0.0 : count / reviews.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Text('$star', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.star, size: 12, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 20,
                      child: Text('$count',
                          style:
                              const TextStyle(fontSize: 11, color: appMuted)),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final ReviewItem review;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: appPrimary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (review.reviewerName?.isNotEmpty == true
                          ? review.reviewerName![0]
                          : '?')
                      .toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName ?? 'Client',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < review.rating ? Icons.star : Icons.star_border,
                          size: 14,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ]),
            ),
          ]),
          if (review.comment?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: appSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                review.comment!,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? appPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: active ? appPrimary : Colors.grey.shade400),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              label,
              style: TextStyle(
                  color: active ? Colors.white : null,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 13),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 16, color: active ? Colors.white : Colors.grey),
          ]),
        ),
      );
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.isOwner,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onBook,
    this.bookingStatus,
  });
  final JobPost job;
  final bool isOwner;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onBook;
  final String? bookingStatus;

  @override
  Widget build(BuildContext context) {
    final slotLabel =
        job.postType == 'offering_service' ? 'clients' : 'workers';
    return AppCard(
      accentColor:
          job.postType == 'offering_service' ? appPrimary : Colors.green,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusChip(
                status: job.postType == 'offering_service'
                    ? 'Looking for client'
                    : 'Looking for worker'),
            const Spacer(),
            if (bookingStatus != null)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.withAlpha(80)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.hourglass_top_outlined,
                      size: 11, color: Colors.orange),
                  const SizedBox(width: 3),
                  Text(
                    bookingStatus == 'pending'
                        ? 'Pending'
                        : bookingStatus == 'accepted'
                            ? 'Accepted'
                            : 'In Progress',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            StatusChip(status: job.status),
          ]),
          const SizedBox(height: 10),
          Text(job.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (!isOwner && job.clientFullName != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: appMuted),
              const SizedBox(width: 4),
              Text(job.clientFullName!,
                  style: const TextStyle(
                      fontSize: 12,
                      color: appMuted,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 6),
          Text(job.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: appMuted)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 8, children: [
            InfoPill(icon: Icons.work_outline, label: job.category),
            InfoPill(icon: Icons.place_outlined, label: job.municipality),
            InfoPill(
              icon: job.postType == 'offering_service'
                  ? Icons.person_add_alt_outlined
                  : Icons.groups_outlined,
              label:
                  '${job.acceptedOfferCount}/${job.workersNeeded} $slotLabel',
            ),
            if (job.offerCount > 0) _OfferCountPill(count: job.offerCount),
            if ((job.budgetMin ?? 0) > 0)
              InfoPill(
                  icon: Icons.payments_outlined,
                  label:
                      'P${job.budgetMin} - P${job.budgetMax ?? job.budgetMin}'),
          ]),
          if (isOwner && (onEdit != null || onDelete != null))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Text(timeAgo(job.createdAt),
                    style: const TextStyle(color: appMuted, fontSize: 12)),
                const Spacer(),
                if (onEdit != null)
                  TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit')),
                if (onDelete != null)
                  TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Post'),
                            content: const Text(
                                'Are you sure you want to delete this post?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirmed == true) await onDelete!();
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      label: const Text('Delete',
                          style: TextStyle(color: Colors.red))),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Text(timeAgo(job.createdAt),
                    style: const TextStyle(color: appMuted, fontSize: 12)),
                const Spacer(),
                if (onReport != null)
                  TextButton.icon(
                    onPressed: onReport,
                    icon: const Icon(Icons.flag_outlined,
                        size: 15, color: appMuted),
                    label: const Text('Report',
                        style: TextStyle(color: appMuted, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (onBook != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onBook,
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: const Text('Book Now'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen(
      {super.key,
      required this.api,
      required this.job,
      required this.onRefresh,
      this.readOnly = false,
      this.reports = const [],
      this.existingBookingStatus});
  final MarketplaceApi api;
  final JobPost job;
  final VoidCallback onRefresh;
  final bool readOnly;
  final List<ReportItem> reports;
  final String? existingBookingStatus;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  var _offers = <JobOffer>[];
  var _loading = true;
  late JobPost _job;
  var _recommendedWorkers = <ProviderDetail>[];

  bool get _isOwner => widget.api.storedUser?.id == _job.clientUserId;

  bool get _hasAlreadyOffered {
    final userId = widget.api.storedUser?.id;
    return _offers.any((o) => o.providerUserId == userId);
  }

  bool get _canApply =>
      !widget.readOnly &&
      widget.api.token.isNotEmpty &&
      !_isOwner &&
      _job.status == 'open' &&
      !_hasAlreadyOffered;

  List<ReportItem> get _jobReports {
    final title = _job.title.toLowerCase();
    return widget.reports.where((report) {
      if (report.providerUserId == _job.clientUserId) return true;
      final haystack = '${report.reason} ${report.details}'.toLowerCase();
      return haystack.contains(_job.id.toLowerCase()) ||
          (title.isNotEmpty && haystack.contains(title));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _loadDetail();
  }

  double _workerScore(ProviderDetail p) =>
      (p.averageRating * 15) + p.reviews.length.clamp(0, 20).toDouble();

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final detail = await widget.api.getJobDetail(_job.id);
      if (mounted) {
        setState(() {
          _job = detail.jobPost;
          _offers = detail.offers;
          _loading = false;
        });
      }
      // Load worker recommendations if this is the owner of a looking_for_worker post
      if (_isOwner &&
          _job.postType != 'offering_service' &&
          _job.status == 'open') {
        try {
          final workers =
              await widget.api.searchProviders(category: _job.category);
          workers.sort((a, b) => _workerScore(b).compareTo(_workerScore(a)));
          if (mounted) {
            setState(() => _recommendedWorkers = workers.take(5).toList());
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openOfferSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SendOfferSheet(
          api: widget.api,
          job: _job,
          onSent: () {
            _loadDetail();
            _openMessageAfterOffer();
          }),
    );
  }

  void _openMessageAfterOffer() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Offer sent! You can message the poster now.'),
        action: SnackBarAction(
          label: 'Message',
          onPressed: _openChat,
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _StartChatFromJob(
          api: widget.api,
          targetUserId: _job.clientUserId,
          targetName: _job.clientFullName ?? 'Client',
          jobTitle: _job.title,
        ),
      ),
    );
  }

  void _openChatWith(String userId, String name) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _StartChatFromJob(
          api: widget.api,
          targetUserId: userId,
          targetName: name,
          jobTitle: _job.title,
        ),
      ),
    );
  }

  Future<void> _acceptOffer(JobOffer offer) async {
    final slotLabel = _job.postType == 'offering_service' ? 'client' : 'worker';
    final pluralSlotLabel = '${slotLabel}s';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Accept this offer?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Worker: ${offer.providerName ?? 'Worker'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (offer.proposedPrice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Price: P${offer.proposedPrice}',
                      style: const TextStyle(color: appMuted)),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _job.acceptedOfferCount + 1 >= _job.workersNeeded
                      ? 'A booking will be created. This fills the $slotLabel slots, so the post will close.'
                      : 'A booking will be created. The post stays open until ${_job.workersNeeded} $pluralSlotLabel are accepted.',
                  style: TextStyle(color: Colors.green, fontSize: 13),
                ),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.acceptJobOffer(_job.id, offer.id);
      widget.onRefresh();
      await _loadDetail();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Offer Accepted!',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          content: const Text(
            'A booking has been created. You can find it in your Bookings tab. You may also message the provider directly.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _declineOffer(JobOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Decline this offer?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            'Decline offer from ${offer.providerName ?? 'this provider'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decline')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.declineJobOffer(_job.id, offer.id);
      await _loadDetail();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _deleteJobAsAdmin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job post?'),
        content: const Text(
            'This will permanently remove this job post from HanapGawa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance
          .queueAction('delete_job_post', {'jobPostId': _job.id});
      if (!mounted) return;
      widget.onRefresh();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.sync, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Delete queued — will sync when online'),
        ]),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    try {
      await widget.api.deleteJobPost(_job.id);
      widget.onRefresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('delete_job_post', {'jobPostId': _job.id});
        if (!mounted) return;
        widget.onRefresh();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Delete queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Widget? _buildBottomBar() {
    if (_loading || widget.readOnly) return null;
    final isOfferingService = _job.postType == 'offering_service';
    final hasActiveBooking = widget.existingBookingStatus != null &&
        widget.existingBookingStatus != 'completed' &&
        widget.existingBookingStatus != 'cancelled';
    final canBook = isOfferingService &&
        !_isOwner &&
        _job.status == 'open' &&
        widget.api.token.isNotEmpty &&
        !hasActiveBooking;

    Widget? action;

    if (isOfferingService) {
      if (canBook && _job.allowDirectBooking) {
        action = FilledButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => BookingSheet(
              api: widget.api,
              target: BookingTarget.fromJobPost(_job),
            ),
          ),
          icon: const Icon(Icons.calendar_month_outlined, size: 16),
          label: const Text('Book Now'),
        );
      } else if (canBook) {
        action = FilledButton.icon(
          onPressed: _openOfferSheet,
          icon: const Icon(Icons.send_outlined, size: 16),
          label: const Text('Apply / Send Offer'),
        );
      }
    } else {
      if (_canApply) {
        action = FilledButton.icon(
          onPressed: _openOfferSheet,
          icon: const Icon(Icons.send_outlined, size: 16),
          label: const Text('Apply / Send Offer'),
        );
      } else if (_hasAlreadyOffered) {
        action = OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline,
              size: 16, color: Colors.green),
          label:
              const Text('Offer Sent', style: TextStyle(color: Colors.green)),
        );
      }
    }

    if (action == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [Expanded(flex: 2, child: action)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = _jobReports;
    final slotLabel =
        _job.postType == 'offering_service' ? 'clients' : 'workers';
    return Scaffold(
      appBar: AppBar(title: Text(_job.title)),
      bottomNavigationBar: _buildBottomBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // â”€â”€ Hero header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _job.postType == 'offering_service'
                          ? [appPrimary, appSecondary]
                          : [const Color(0xFF1B5E20), Colors.green.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: Colors.white.withAlpha(80)),
                            ),
                            child: Text(
                              _job.postType == 'offering_service'
                                  ? 'Looking for client'
                                  : 'Looking for worker',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _job.status == 'open'
                                  ? Colors.white.withAlpha(30)
                                  : Colors.black26,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _job.status[0].toUpperCase() +
                                  _job.status.substring(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Text(_job.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.2)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.person_outline,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                              'Posted by ${_job.clientFullName ?? 'User'}  Â·  ${timeAgo(_job.createdAt)}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ]),
                      ]),
                ),

                // â”€â”€ Detail cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick info pills
                        Wrap(spacing: 10, runSpacing: 8, children: [
                          _DetailChip(
                              icon: Icons.work_outline, label: _job.category),
                          _DetailChip(
                              icon: Icons.place_outlined,
                              label: _job.municipality),
                          _DetailChip(
                            icon: _job.postType == 'offering_service'
                                ? Icons.person_add_alt_outlined
                                : Icons.groups_outlined,
                            label:
                                '${_job.acceptedOfferCount}/${_job.workersNeeded} $slotLabel accepted',
                            highlight: true,
                            highlightColor: Colors.green,
                          ),
                          if ((_job.budgetMin ?? 0) > 0)
                            _DetailChip(
                                icon: Icons.payments_outlined,
                                label:
                                    'P${_job.budgetMin}â€“P${_job.budgetMax ?? _job.budgetMin}',
                                highlight: true),
                          if (_job.scheduledAt != null)
                            _DetailChip(
                                icon: Icons.calendar_today_outlined,
                                label: formatDate(_job.scheduledAt!)),
                          if (_job.offerCount > 0)
                            _DetailChip(
                                icon: Icons.send_outlined,
                                label:
                                    '${_job.offerCount} offer${_job.offerCount == 1 ? '' : 's'}',
                                highlight: true,
                                highlightColor: appPrimary),
                        ]),

                        const SizedBox(height: 20),

                        if (_isOwner && _job.acceptedWorkers.isNotEmpty) ...[
                          AppCard(
                            accentColor: Colors.green,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Accepted Workers',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16)),
                                const SizedBox(height: 8),
                                ..._job.acceptedWorkers
                                    .map((worker) => ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: const CircleAvatar(
                                              child:
                                                  Icon(Icons.person_outline)),
                                          title: Text(
                                              worker['name']?.toString() ??
                                                  'Worker'),
                                        )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (widget.readOnly) ...[
                          AppCard(
                            accentColor: reports.isEmpty
                                ? Colors.green
                                : Colors.red.shade600,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(
                                      reports.isEmpty
                                          ? Icons.verified_outlined
                                          : Icons.flag_outlined,
                                      color: reports.isEmpty
                                          ? Colors.green
                                          : Colors.red.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        reports.isEmpty
                                            ? 'No reports linked to this job post'
                                            : '${reports.length} report${reports.length == 1 ? '' : 's'} linked to this job post',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ]),
                                  if (reports.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    ...reports.map((report) => Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withAlpha(14),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color:
                                                    Colors.red.withAlpha(50)),
                                          ),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(report.reason,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800)),
                                                if (report.details.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4),
                                                    child: Text(report.details,
                                                        style: const TextStyle(
                                                            color: appMuted,
                                                            fontSize: 13)),
                                                  ),
                                                const SizedBox(height: 4),
                                                StatusChip(
                                                    status: report.status),
                                              ]),
                                        )),
                                  ],
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _deleteJobAsAdmin,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(
                                          color: Colors.red.shade300),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Delete job post'),
                                  ),
                                ]),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Description
                        const _SectionLabel('Description'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: appBorder),
                          ),
                          child: Text(_job.description,
                              style:
                                  const TextStyle(height: 1.6, fontSize: 14)),
                        ),

                        // Location details
                        if (_job.locationDetails != null &&
                            _job.locationDetails!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const _SectionLabel('Location Details'),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: appBorder),
                            ),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.place_outlined,
                                      size: 18, color: appPrimary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(_job.locationDetails!,
                                          style: const TextStyle(
                                              height: 1.5, fontSize: 14))),
                                ]),
                          ),
                        ],

                        // Schedule
                        if (_job.scheduledAt != null) ...[
                          const SizedBox(height: 20),
                          const _SectionLabel('Preferred Schedule'),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: appBorder),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_month_outlined,
                                  size: 18, color: appPrimary),
                              const SizedBox(width: 10),
                              Text(formatDateTime(_job.scheduledAt!),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                            ]),
                          ),
                        ],

                        // Budget
                        if ((_job.budgetMin ?? 0) > 0) ...[
                          const SizedBox(height: 20),
                          const _SectionLabel('Budget'),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(12),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: Colors.green.withAlpha(50)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.payments_outlined,
                                  size: 18, color: Colors.green),
                              const SizedBox(width: 10),
                              Text(
                                'P${_job.budgetMin}${_job.budgetMax != null && _job.budgetMax != _job.budgetMin ? ' â€“ P${_job.budgetMax}' : ''}',
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16),
                              ),
                            ]),
                          ),
                        ],

                        // ── AI Worker Recommendation ────────────────────────
                        if (_recommendedWorkers.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const _SectionLabel('AI Recommended Workers'),
                          const SizedBox(height: 10),
                          _AIWorkerRecommendationCard(
                            workers: _recommendedWorkers,
                            jobCategory: _job.category,
                            api: widget.api,
                          ),
                        ],

                        const SizedBox(height: 24),
                        // Offers section
                        _SectionLabel('Offers (${_offers.length})'),
                        const SizedBox(height: 12),
                        if (_offers.isEmpty)
                          const EmptyState(
                              icon: Icons.send_outlined,
                              title: 'No offers yet'),
                        ..._offers.map((offer) => _OfferDetailCard(
                              offer: offer,
                              isOwner: _isOwner,
                              jobOpen: _job.status == 'open',
                              onAccept: () => _acceptOffer(offer),
                              onDecline: () => _declineOffer(offer),
                              onMessage: () => _isOwner
                                  ? _openChatWith(offer.providerUserId,
                                      offer.providerName ?? 'Worker')
                                  : _openChatWith(_job.clientUserId,
                                      _job.clientFullName ?? 'Client'),
                            )),
                        const SizedBox(height: 80),
                      ]),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w800, color: appMuted),
      );
}

// ─── AI Worker Recommendation card (shown to job owner) ───────────────────────

class _AIWorkerRecommendationCard extends StatelessWidget {
  const _AIWorkerRecommendationCard({
    required this.workers,
    required this.jobCategory,
    required this.api,
  });
  final List<ProviderDetail> workers;
  final String jobCategory;
  final MarketplaceApi api;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [appPrimary.withAlpha(14), appSecondary.withAlpha(14)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: appPrimary.withAlpha(50)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.psychology, size: 16, color: appPrimary),
            const SizedBox(width: 6),
            Text('Best matches for "$jobCategory"',
                style: const TextStyle(
                    color: appPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          ...workers.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final w = entry.value;
            final stars = w.averageRating;
            final reviewCount = w.reviews.length;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: rank == 1 ? appPrimary.withAlpha(80) : appBorder),
              ),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: rank == 1 ? appAccent : appBorder,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('$rank',
                        style: TextStyle(
                            color: rank == 1 ? appPrimary : appMuted,
                            fontWeight: FontWeight.w900,
                            fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.star,
                              size: 13, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 3),
                          Text(
                            stars > 0
                                ? '${stars.toStringAsFixed(1)} · $reviewCount review${reviewCount == 1 ? '' : 's'}'
                                : 'No reviews yet',
                            style:
                                const TextStyle(color: appMuted, fontSize: 12),
                          ),
                        ]),
                      ]),
                ),
                if (rank == 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: appAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Top Pick',
                        style: TextStyle(
                            color: appPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
              ]),
            );
          }),
        ]),
      );
}

// ─── AI Job Recommendation banner (shown to workers in Browse) ────────────────

class _AIJobRecommendationBanner extends StatelessWidget {
  const _AIJobRecommendationBanner({
    required this.jobs,
    required this.profile,
    required this.onTap,
  });
  final List<JobPost> jobs;
  final ProviderDetail profile;
  final void Function(JobPost) onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1B5E20).withAlpha(18),
              Colors.green.withAlpha(12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.green.withAlpha(60)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.psychology, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Jobs For You · ${profile.category}',
                style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ...jobs.map((job) => GestureDetector(
                onTap: () => onTap(job),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: appBorder),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(job.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 3),
                            Row(children: [
                              const Icon(Icons.place_outlined,
                                  size: 13, color: appMuted),
                              const SizedBox(width: 4),
                              Text(job.municipality,
                                  style: const TextStyle(
                                      color: appMuted, fontSize: 12)),
                              if ((job.budgetMin ?? 0) > 0) ...[
                                const SizedBox(width: 10),
                                const Icon(Icons.payments_outlined,
                                    size: 13, color: Colors.green),
                                const SizedBox(width: 4),
                                Text('P${job.budgetMin}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ]),
                          ]),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: appMuted),
                  ]),
                ),
              )),
          const Text('Based on your service category & location',
              style: TextStyle(color: appMuted, fontSize: 11)),
        ]),
      );
}

class _DetailChip extends StatelessWidget {
  const _DetailChip(
      {required this.icon,
      required this.label,
      this.highlight = false,
      this.highlightColor});
  final IconData icon;
  final String label;
  final bool highlight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final color = highlightColor ?? Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? color.withAlpha(20) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight ? color.withAlpha(80) : appBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: highlight ? color : appPrimary),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: highlight ? color : const Color(0xFF1F1F1F))),
      ]),
    );
  }
}

// Opens or creates a conversation with the job poster
class _StartChatFromJob extends StatefulWidget {
  const _StartChatFromJob(
      {required this.api,
      required this.targetUserId,
      required this.targetName,
      required this.jobTitle});
  final MarketplaceApi api;
  final String targetUserId;
  final String targetName;
  final String jobTitle;

  @override
  State<_StartChatFromJob> createState() => _StartChatFromJobState();
}

class _StartChatFromJobState extends State<_StartChatFromJob> {
  var _loading = true;
  Conversation? _conversation;

  @override
  void initState() {
    super.initState();
    _findOrCreateConversation();
  }

  Future<void> _findOrCreateConversation() async {
    try {
      final conversations = await widget.api.getMyConversations();
      final existing = conversations.firstWhere(
        (c) =>
            c.clientUserId == widget.targetUserId ||
            c.providerUserId == widget.targetUserId,
        orElse: () => _emptyConversation,
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
      // Start new conversation
      await widget.api.startInquiry(
        widget.targetUserId,
        'Hi! I\'m interested in your job post: ${widget.jobTitle}',
      );
      final updated = await widget.api.getMyConversations();
      final created = updated.firstWhere(
        (c) =>
            c.clientUserId == widget.targetUserId ||
            c.providerUserId == widget.targetUserId,
        orElse: () => _emptyConversation,
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
        Navigator.pop(context);
      }
    }
  }

  static final _emptyConversation = Conversation(
    id: '',
    clientUserId: '',
    providerUserId: '',
    lastMessagePreview: '',
    updatedAt: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_conversation == null || _conversation!.id.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('Could not open conversation.')));
    }
    return ChatScreen(
      api: widget.api,
      conversation: _conversation!,
      title: widget.targetName,
    );
  }
}

class _SendOfferSheet extends StatefulWidget {
  const _SendOfferSheet(
      {required this.api, required this.job, required this.onSent});
  final MarketplaceApi api;
  final JobPost job;
  final VoidCallback onSent;

  @override
  State<_SendOfferSheet> createState() => _SendOfferSheetState();
}

class _SendOfferSheetState extends State<_SendOfferSheet> {
  final _message = TextEditingController();
  final _price = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _message.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    setState(() => _sending = true);

    // Queue offline
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('send_job_offer', {
        'jobPostId': widget.job.id,
        'message': _message.text.trim(),
        if (_price.text.isNotEmpty) 'proposedPrice': int.tryParse(_price.text),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Offer queued — will send when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    try {
      await widget.api.sendJobOffer(
        widget.job.id,
        _message.text.trim(),
        proposedPrice: int.tryParse(_price.text),
      );
      if (mounted) Navigator.pop(context);
      widget.onSent();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send Offer',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Applying for: ${widget.job.title}',
              style: const TextStyle(color: appMuted)),
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Message',
                hintText:
                    'Describe your experience and why you\'re a good fit...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Proposed price (optional)', prefixText: 'P '),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit Offer'),
          ),
        ],
      ),
    );
  }
}

class _JobPostSheet extends StatefulWidget {
  const _JobPostSheet(
      {required this.api, this.editPost, required this.onSaved});
  final MarketplaceApi api;
  final JobPost? editPost;
  final VoidCallback onSaved;

  @override
  State<_JobPostSheet> createState() => _JobPostSheetState();
}

class _JobPostSheetState extends State<_JobPostSheet> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _budgetMin;
  late final TextEditingController _budgetMax;
  late final TextEditingController _workersNeeded;
  late String _municipality;
  late String _postType;
  late bool _allowDirectBooking;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final post = widget.editPost;
    _title = TextEditingController(text: post?.title ?? '');
    _category = TextEditingController(text: post?.category ?? 'Carpentry');
    _location = TextEditingController();
    _description = TextEditingController(text: post?.description ?? '');
    _budgetMin =
        TextEditingController(text: post?.budgetMin?.toString() ?? '500');
    _budgetMax =
        TextEditingController(text: post?.budgetMax?.toString() ?? '2500');
    _workersNeeded =
        TextEditingController(text: (post?.workersNeeded ?? 1).toString());
    _municipality = post?.municipality ?? 'Bongao';
    _postType = post?.postType ?? 'looking_for_worker';
    _allowDirectBooking = post?.allowDirectBooking ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _location.dispose();
    _description.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _workersNeeded.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final payload = JobPostPayload(
      postType: _postType,
      title: _title.text.trim(),
      category: _category.text.trim(),
      municipality: _municipality,
      locationDetails: _location.text.trim(),
      description: _description.text.trim(),
      budgetMin: int.tryParse(_budgetMin.text),
      budgetMax: int.tryParse(_budgetMax.text),
      workersNeeded: int.tryParse(_workersNeeded.text) ?? 1,
      allowDirectBooking:
          _postType == 'offering_service' ? _allowDirectBooking : false,
    );
    final actionPayload = <String, dynamic>{
      'postType': payload.postType,
      'title': payload.title,
      'category': payload.category,
      'municipality': payload.municipality,
      'locationDetails': payload.locationDetails,
      'description': payload.description,
      if (payload.budgetMin != null) 'budgetMin': payload.budgetMin,
      if (payload.budgetMax != null) 'budgetMax': payload.budgetMax,
      'workersNeeded': payload.workersNeeded,
      'allowDirectBooking': payload.allowDirectBooking,
      if (widget.editPost != null) 'jobPostId': widget.editPost!.id,
    };
    final actionType =
        widget.editPost != null ? 'update_job_post' : 'create_job_post';

    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction(actionType, actionPayload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.sync, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('Job post queued — will submit when online')),
        ]),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ));
      widget.onSaved();
      return;
    }

    try {
      if (widget.editPost != null) {
        await widget.api.updateJobPost(widget.editPost!.id, payload);
      } else {
        await widget.api.createJobPost(payload);
      }
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      if (SyncService.isNetworkError(error)) {
        await LocalDb.instance.queueAction(actionType, actionPayload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              Icon(Icons.sync, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Job post queued — will submit when online')),
            ]),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ));
          widget.onSaved();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(error)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5)));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 14, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                    color: appPrimary, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Text(
                widget.editPost == null ? 'Create Job Post' : 'Edit Job Post',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ]),
            const SizedBox(height: 14),
            StatefulBuilder(
              builder: (context, setInner) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'looking_for_worker',
                      label: Text('Looking for worker')),
                  ButtonSegment(
                      value: 'offering_service',
                      label: Text('Looking for client')),
                ],
                selected: {_postType},
                onSelectionChanged: (value) {
                  setInner(() => _postType = value.first);
                  setState(() => _postType = value.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 10),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category.text),
              optionsBuilder: (value) {
                const suggestions = [
                  'Carpentry',
                  'Plumbing',
                  'Electrical',
                  'Cleaning',
                  'Home Repair',
                  'Painting',
                  'Landscaping',
                  'Tutoring',
                  'Beauty & Wellness',
                  'Security',
                  'Delivery',
                  'Food Service',
                  'Fitness',
                  'Computer & Tech',
                  'Car Repair',
                  'Pet Care',
                  'Medical Aide',
                  'Photography',
                  'Tailoring',
                  'General Labor',
                ];
                if (value.text.isEmpty) return suggestions;
                return suggestions.where(
                    (s) => s.toLowerCase().contains(value.text.toLowerCase()));
              },
              onSelected: (val) => _category.text = val,
              fieldViewBuilder: (context, ctrl, focusNode, onSubmitted) {
                ctrl.text = _category.text;
                ctrl.addListener(() => _category.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Category'),
                );
              },
            ),
            const SizedBox(height: 10),
            StatefulBuilder(
              builder: (context, setInner) => DropdownButtonFormField<String>(
                value: _municipality,
                decoration: const InputDecoration(labelText: 'Municipality'),
                items: municipalities
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (value) =>
                    setInner(() => _municipality = value ?? _municipality),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _workersNeeded,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _postType == 'offering_service'
                    ? 'How many clients do you want?'
                    : 'How many workers do you need?',
                helperText: _postType == 'offering_service'
                    ? 'The post stays open until this many clients are accepted.'
                    : 'The job stays open until this many offers are accepted.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _location,
                decoration:
                    const InputDecoration(labelText: 'Location details')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _budgetMin,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min budget'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: _budgetMax,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Max budget'))),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description')),
            if (_postType == 'offering_service') ...[
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setInner) => Container(
                  decoration: BoxDecoration(
                    color: _allowDirectBooking
                        ? appPrimary.withAlpha(12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _allowDirectBooking
                          ? appPrimary.withAlpha(60)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: SwitchListTile(
                    value: _allowDirectBooking,
                    activeColor: appPrimary,
                    onChanged: (value) {
                      setInner(() => _allowDirectBooking = value);
                      setState(() => _allowDirectBooking = value);
                    },
                    title: const Text(
                      'Allow clients to book me directly',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      _allowDirectBooking
                          ? 'Clients will see a "Book Now" button on this post.'
                          : 'Clients can message you or send an inquiry.',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              _allowDirectBooking ? appPrimary : Colors.grey),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.editPost == null
                      ? 'Publish Post'
                      : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Per-offer card inside job detail screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _OfferCountPill extends StatelessWidget {
  const _OfferCountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: appPrimary.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: appPrimary.withAlpha(80)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.send_outlined, size: 13, color: appPrimary),
          const SizedBox(width: 4),
          Text(
            '$count ${count == 1 ? 'offer' : 'offers'}',
            style: TextStyle(
                color: appPrimary, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ]),
      );
}

class _OfferDetailCard extends StatelessWidget {
  const _OfferDetailCard({
    required this.offer,
    required this.isOwner,
    required this.jobOpen,
    required this.onAccept,
    required this.onDecline,
    required this.onMessage,
  });
  final JobOffer offer;
  final bool isOwner;
  final bool jobOpen;
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

    return AppCard(
      accentColor:
          isAccepted ? Colors.green : (isPending ? appPrimary : appMuted),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Provider header
        Row(children: [
          Container(
            width: 42,
            height: 42,
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
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(offer.providerName ?? 'Worker',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(timeAgo(offer.createdAt),
                  style: const TextStyle(color: appMuted, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              offer.status[0].toUpperCase() + offer.status.substring(1),
              style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Message bubble
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(offer.message, style: const TextStyle(height: 1.45)),
        ),
        // Proposed price
        if (offer.proposedPrice != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withAlpha(50)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.payments_outlined,
                  size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text('P${offer.proposedPrice} proposed',
                  style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          ),
        ],
        // Booking notice after acceptance
        if (isAccepted) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text('Booking created â€” check the Bookings tab',
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
            ]),
          ),
        ],
        // Action buttons — owner + pending + open
        if (isOwner && isPending && jobOpen) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onMessage,
              icon: const Icon(Icons.message_outlined, size: 16),
              label: const Text('Message'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDecline,
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                label:
                    const Text('Decline', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Accept'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.message_outlined, size: 16),
            label: const Text('Message'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ]),
    );
  }
}
