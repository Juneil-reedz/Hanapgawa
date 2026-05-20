import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/info_pill.dart';
import '../../shared/widgets/status_chip.dart';
import 'booking_sheet.dart';

class ProviderDetailScreen extends StatefulWidget {
  const ProviderDetailScreen(
      {super.key, required this.api, required this.providerUserId});
  final MarketplaceApi api;
  final String providerUserId;

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  ProviderDetail? _detail;
  List<Booking> _activeBookings = [];
  var _loading = true;
  var _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final detailFuture = widget.api.getProviderDetail(widget.providerUserId);
      final bookingsFuture = widget.api.token.isNotEmpty
          ? widget.api.getMyBookings()
          : Future.value(<Booking>[]);
      final detail = await detailFuture;
      final bookings = await bookingsFuture;
      if (mounted) {
        setState(() {
          _detail = detail;
          _activeBookings = bookings
              .where((b) => !['completed', 'cancelled', 'rejected'].contains(b.status))
              .toList();
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  bool _hasActiveBookingWith(String providerUserId) {
    return _activeBookings.any((b) => b.providerUserId == providerUserId);
  }

  void _openBooking(ServiceListing listing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BookingSheet(
          api: widget.api,
          target: BookingTarget.fromListing(listing)),
    );
  }

  void _openContact() {
    final detail = _detail;
    if (detail == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _ContactSheet(api: widget.api, providerUserId: detail.providerUserId),
    );
  }

  void _openReport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _ReportSheet(api: widget.api, providerUserId: widget.providerUserId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.name ?? 'Worker Profile'),
        actions: [
          if (_detail != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'report') _openReport();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'report',
                    child: Row(children: [
                      Icon(Icons.flag_outlined),
                      SizedBox(width: 8),
                      Text('Report'),
                    ])),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: _error,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Retry')),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final detail = _detail!;
    final avgRating = detail.averageRating;

    return ListView(
      children: [
        Container(
          height: 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [appPrimary, appSecondary, Color(0xFFC8AAAA)]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform.translate(
                offset: const Offset(0, -48),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Avatar(label: detail.name[0].toUpperCase(), size: 80),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(detail.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          Wrap(spacing: 8, children: [
                            StatusChip(
                                status: detail.approvalStatus ?? 'pending'),
                            Text(detail.category,
                                style: const TextStyle(color: appMuted)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      InfoPill(
                          icon: Icons.place_outlined,
                          label: detail.municipality),
                      const SizedBox(width: 8),
                      if (avgRating > 0)
                        InfoPill(
                            icon: Icons.star,
                            label:
                                '${avgRating.toStringAsFixed(1)} (${detail.reviews.length})'),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      if (detail.providerUserId !=
                          (widget.api.storedUser?.id ?? '')) ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: detail.listings.isEmpty ||
                                    _hasActiveBookingWith(detail.providerUserId)
                                ? null
                                : () => _openBooking(detail.listings.first),
                            icon: Icon(detail.listings.isNotEmpty &&
                                    detail.listings.first.allowDirectBooking
                                ? Icons.bolt
                                : Icons.calendar_month_outlined),
                            label: Text(_hasActiveBookingWith(detail.providerUserId)
                                ? 'Already Booked'
                                : detail.listings.isNotEmpty &&
                                    detail.listings.first.allowDirectBooking
                                ? 'Book Now'
                                : 'Book'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openContact,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Contact'),
                        ),
                      ),
                    ]),
                    if (detail.services.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Skills',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: detail.services
                              .map((s) => Chip(label: Text(s)))
                              .toList()),
                    ],
                    const SizedBox(height: 16),
                    Text('Services (${detail.listings.length})',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (detail.listings.isEmpty)
                      const EmptyState(
                          icon: Icons.work_outline,
                          title: 'No service listings yet'),
                    ...detail.listings.map((listing) => AppCard(
                          accentColor: appPrimary,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(listing.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  if (listing.allowDirectBooking)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: appPrimary.withAlpha(20),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: appPrimary.withAlpha(60)),
                                      ),
                                      child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.bolt,
                                                size: 11, color: appPrimary),
                                            SizedBox(width: 3),
                                            Text('Instant',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: appPrimary,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ]),
                                    ),
                                ]),
                                const SizedBox(height: 6),
                                Text(listing.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: appMuted)),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          'P${listing.priceMin} - P${listing.priceMax}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800))),
                                  if (detail.providerUserId !=
                                      (widget.api.storedUser?.id ?? ''))
                                    FilledButton(
                                        onPressed: _hasActiveBookingWith(
                                                detail.providerUserId)
                                            ? null
                                            : () => _openBooking(listing),
                                        child: Text(_hasActiveBookingWith(
                                                detail.providerUserId)
                                            ? 'Already Booked'
                                            : listing.allowDirectBooking
                                                ? 'Book Now'
                                                : 'Book')),
                                ]),
                              ]),
                        )),
                    const SizedBox(height: 16),
                    Text('Reviews (${detail.reviews.length})',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (detail.reviews.isEmpty)
                      const EmptyState(
                          icon: Icons.star_outline, title: 'No reviews yet'),
                    ...detail.reviews.map((review) => AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    children: List.generate(
                                        5,
                                        (index) => Icon(
                                              index < review.rating
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.orange,
                                              size: 18,
                                            ))),
                                const SizedBox(height: 6),
                                if (review.comment?.isNotEmpty ?? false)
                                  Text('"${review.comment}"'),
                                if (review.reviewerName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('by ${review.reviewerName}',
                                        style: const TextStyle(
                                            color: appMuted, fontSize: 12)),
                                  ),
                              ]),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.api, required this.providerUserId});
  final MarketplaceApi api;
  final String providerUserId;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  final _message = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.api
          .startInquiry(widget.providerUserId, _message.text.trim());
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Message sent.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(error))));
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
          Text('Contact Provider',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Hi, I\'m interested in your services...'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send Message'),
          ),
        ],
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.api, required this.providerUserId});
  final MarketplaceApi api;
  final String providerUserId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _reason = TextEditingController();
  final _details = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty || _details.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reason and details are required.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.api.submitReport(
        providerUserId: widget.providerUserId,
        reason: _reason.text.trim(),
        details: _details.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(error))));
        setState(() => _submitting = false);
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
          Text('Report Provider',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
              controller: _reason,
              decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. Fraud, Misconduct, False advertising')),
          const SizedBox(height: 10),
          TextField(
            controller: _details,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Details', hintText: 'Describe what happened...'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit Report'),
          ),
        ],
      ),
    );
  }
}
