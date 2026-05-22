import 'package:flutter/material.dart';
import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'review_sheet.dart';

class BookingCard extends StatefulWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.myId,
    required this.onStatus,
    required this.onMessage,
    this.api,
    this.onRepost,
    this.onReschedule,
    this.onTap,
    this.onDelete,
  });
  final Booking booking;
  final String myId;
  final Future<void> Function(String status) onStatus;
  final VoidCallback onMessage;
  final MarketplaceApi? api;
  final VoidCallback? onRepost;
  final VoidCallback? onReschedule;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  State<BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<BookingCard> {
  var _rated = false;

  Booking get booking => widget.booking;
  String get myId => widget.myId;

  MarketplaceApi? get api => widget.api;
  Future<void> Function(String) get onStatus => widget.onStatus;
  VoidCallback get onMessage => widget.onMessage;
  VoidCallback? get onRepost => widget.onRepost;
  VoidCallback? get onReschedule => widget.onReschedule;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onDelete => widget.onDelete;

  bool get _isClient => booking.clientUserId == myId;
  bool get _isWorker => booking.workerUserId == myId;
  bool get _isApprover =>
      (booking.source == 'job_application'
          ? booking.clientUserId
          : booking.workerUserId) ==
      myId;

  String get _otherName => _isClient
      ? (booking.workerName ?? 'Worker')
      : (booking.clientName ?? 'Client');

  String get _otherLabel => _isClient ? 'Worker' : 'Client';

  String get _displayTitle => booking.jobTitle?.trim().isNotEmpty == true
      ? booking.jobTitle!.trim()
      : booking.serviceCategory;

  String get _sourceLabel {
    switch (booking.source) {
      case 'job_application':
        return 'Job Application';
      case 'service_booking':
        return 'Service Booking';
      default:
        return 'Direct Booking';
    }
  }

  List<(String, String, bool)> get _actions {
    if (_isClient) {
      if (booking.status == 'completion_requested') {
        return [('Confirm Complete', 'completed', true)];
      }
    }
    if (booking.status == 'pending') {
      if (_isApprover) {
        return [
          ('Accept', 'accepted', true),
          ('Decline', 'rejected', false),
        ];
      }
      return [('Cancel', 'cancellation_requested', false)];
    }
    if (_isClient) {
      if (['accepted', 'in_progress'].contains(booking.status)) {
        return [('Cancel', 'cancellation_requested', false)];
      }
    } else if (_isWorker) {
      if (booking.status == 'accepted') {
        return [
          ('Start', 'in_progress', true),
          ('Cancel', 'cancellation_requested', false),
        ];
      }
      if (booking.status == 'in_progress') {
        return [
          ('Mark Complete', 'completion_requested', true),
          ('Cancel', 'cancellation_requested', false),
        ];
      }
    }
    if (booking.status == 'cancellation_requested') {
      return [('Finalize Cancel', 'cancelled', false)];
    }
    return [];
  }

  bool get _canReschedule {
    if (_isClient && booking.status == 'pending') return true;
    if (_isWorker && booking.status == 'accepted') return true;
    return false;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return appPrimary;
      case 'completion_requested':
        return Colors.teal;
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'rejected':
      case 'cancelled':
        return Colors.red;
      case 'cancellation_requested':
        return Colors.deepOrange;
      default:
        return appMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'completion_requested':
        return 'Awaiting Confirmation';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'cancellation_requested':
        return 'Cancel Requested';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(booking.status);
    final isActive =
        !['completed', 'rejected', 'cancelled'].contains(booking.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header stripe
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withAlpha(18),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(booking.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatDate(booking.createdAt),
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service name
                    Text(
                      _displayTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),

                    // Other party
                    _InfoRow(
                      icon: Icons.person_outline,
                      label: _otherLabel,
                      value: _otherName,
                      color: appPrimary,
                    ),
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: Icons.local_offer_outlined,
                      label: 'Source',
                      value: _sourceLabel,
                    ),
                    const SizedBox(height: 6),

                    // Location
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: 'Location',
                      value: booking.municipality +
                          (booking.locationDetails.isNotEmpty
                              ? ' · ${booking.locationDetails}'
                              : ''),
                    ),
                    const SizedBox(height: 6),

                    // Schedule
                    _InfoRow(
                      icon: Icons.calendar_month_outlined,
                      label: 'Schedule',
                      value: booking.scheduledAt == null
                          ? 'Not set'
                          : formatDate(booking.scheduledAt!),
                    ),

                    // Notes
                    if (booking.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: appSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          booking.notes,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],

                    // Reschedule note
                    if (booking.rescheduleNote != null &&
                        booking.rescheduleNote!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(18),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.orange.withAlpha(60)),
                        ),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.edit_calendar_outlined,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Rescheduled: ${booking.rescheduleNote}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.deepOrange),
                                ),
                              ),
                            ]),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Actions row
                    Row(children: [
                      // Status action buttons
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _actions.map((a) {
                            if (a.$3) {
                              return FilledButton(
                                onPressed: () => onStatus(a.$2),
                                style: FilledButton.styleFrom(
                                  backgroundColor: color,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(a.$1,
                                    style: const TextStyle(fontSize: 13)),
                              );
                            } else {
                              return OutlinedButton(
                                onPressed: () => onStatus(a.$2),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: a.$2 == 'rejected' ||
                                          a.$2 == 'cancellation_requested' ||
                                          a.$2 == 'cancelled'
                                      ? Colors.red
                                      : color,
                                  side: BorderSide(
                                    color: a.$2 == 'rejected' ||
                                            a.$2 == 'cancellation_requested' ||
                                            a.$2 == 'cancelled'
                                        ? Colors.red
                                        : color,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(a.$1,
                                    style: const TextStyle(fontSize: 13)),
                              );
                            }
                          }).toList(),
                        ),
                      ),
                      // Message button — visible to both parties after booking is accepted
                      if (isActive && booking.status != 'pending') ...[
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: onMessage,
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          tooltip: 'Message',
                          style: IconButton.styleFrom(
                            foregroundColor: appPrimary,
                            side: const BorderSide(color: appPrimary),
                            padding: const EdgeInsets.all(8),
                            minimumSize: const Size(36, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ]),

                    // Move Date — provider on accepted, client on pending
                    if (_canReschedule && onReschedule != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onReschedule,
                          icon: const Icon(Icons.edit_calendar_outlined,
                              size: 16),
                          label: const Text('Move Date'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],

                    if (['completed', 'cancelled', 'rejected']
                            .contains(booking.status) &&
                        onRepost != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRepost,
                          icon: const Icon(Icons.refresh_outlined, size: 16),
                          label: Text(_isClient
                              ? 'Re-post as Job'
                              : 'Make Available Again'),
                          style: FilledButton.styleFrom(
                            backgroundColor: appPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],

                    // Delete — only for completed/cancelled/rejected
                    if (onDelete != null &&
                        ['completed', 'cancelled', 'rejected']
                            .contains(booking.status)) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],

                    // Mutual rating — both parties can rate each other
                    if (booking.status == 'completed' && api != null) ...[
                      const SizedBox(height: 8),
                      _rated
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.star,
                                  size: 16, color: Colors.amber),
                              label: const Text('Rated'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: Colors.amber,
                                side: const BorderSide(color: Colors.amber),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: () {
                                final reviewedName = _isClient
                                    ? (booking.workerName ?? 'Worker')
                                    : (booking.clientName ?? 'Client');
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20))),
                                  builder: (context) => ReviewSheet(
                                    api: api!,
                                    booking: booking,
                                    reviewedName: reviewedName,
                                    onDone: () => setState(() => _rated = true),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.star_outline, size: 16),
                              label: Text(
                                  _isClient ? 'Rate Worker' : 'Rate Client'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color = appMuted,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 13, color: color, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
