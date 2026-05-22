import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton.dart';
import 'booking_card.dart';
import 'chat_screen.dart';
import 'conversation_tile.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen(
      {super.key,
      required this.api,
      this.openJobs,
      this.pendingBookingCount = 0});
  final MarketplaceApi api;
  final VoidCallback? openJobs;
  final int pendingBookingCount;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  var _segment = 0;
  var _bookings = <Booking>[];
  var _conversations = <Conversation>[];
  var _loading = false;
  var _refreshing = false;
  var _message = '';

  // Selected person index for horizontal person selector (segments 0 & 1)
  var _activeGroupIndex = 0;
  var _historyGroupIndex = 0;

  final _searchCtrl = TextEditingController();
  var _searchQuery = '';

  // Unread tracking: convId → updatedAt when last seen
  final _lastSeen = <String, DateTime>{};
  var _initialLoadDone = false;
  // Pinned conversation IDs
  final _pinned = <String>{};
  // Inbox selection mode
  var _inboxSelectMode = false;
  final _selectedConvIds = <String>{};

  @override
  void initState() {
    super.initState();
    _initInbox();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
        if (_segment == 2) _loadConversations(q);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Load persisted last-seen timestamps from SQLite, then start data fetch.
  Future<void> _initInbox() async {
    await _loadLastSeen();
    _load();
  }

  Future<void> _loadLastSeen() async {
    final raw = await LocalDb.instance.getSetting('inbox_last_seen');
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _lastSeen.addAll(map.map(
        (k, v) => MapEntry(k, DateTime.fromMillisecondsSinceEpoch(v as int)),
      ));
    }
    if (mounted) setState(() => _initialLoadDone = true);
  }

  Future<void> _persistLastSeen() async {
    final map = _lastSeen.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch));
    await LocalDb.instance.setSetting('inbox_last_seen', jsonEncode(map));
  }

  bool _isUnread(Conversation conv) {
    if (!_initialLoadDone) return false;
    // Never highlight as unread when the current user sent the last message.
    final myId = widget.api.storedUser?.id ?? '';
    if (conv.lastSenderId != null && conv.lastSenderId == myId) return false;
    final seen = _lastSeen[conv.id];
    if (seen == null) return true;
    return conv.updatedAt.isAfter(seen);
  }

  void _markSeen(String convId) {
    final conv = _conversations.firstWhere((c) => c.id == convId,
        orElse: () => _conversations.first);
    setState(() => _lastSeen[convId] = conv.updatedAt);
    _persistLastSeen();
  }

  void _markUnread(String convId) {
    setState(() => _lastSeen.remove(convId));
    _persistLastSeen();
  }

  void _togglePin(String convId) {
    setState(() {
      if (_pinned.contains(convId)) {
        _pinned.remove(convId);
      } else {
        _pinned.add(convId);
      }
    });
  }

  int get _unreadCount => _conversations.where(_isUnread).length;

  static const _doneStatuses = {'completed', 'cancelled', 'rejected'};

  List<Booking> get _activeBookings =>
      _bookings.where((b) => !_doneStatuses.contains(b.status)).toList();

  List<Booking> get _historyBookings =>
      _bookings.where((b) => _doneStatuses.contains(b.status)).toList();

  List<Booking> get _filteredHistoryBookings {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _historyBookings;
    return _historyBookings.where((b) {
      final title = b.jobTitle?.trim().isNotEmpty == true
          ? b.jobTitle!.toLowerCase()
          : b.serviceCategory.toLowerCase();
      return title.contains(q) ||
          b.serviceCategory.toLowerCase().contains(q) ||
          b.notes.toLowerCase().contains(q) ||
          b.locationDetails.toLowerCase().contains(q) ||
          (b.workerName ?? '').toLowerCase().contains(q) ||
          (b.clientName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// Groups bookings by the other party and returns ordered pairs of
  /// (otherUserId, otherName, bookings).
  List<({String userId, String name, List<Booking> bookings})> _grouped(
      List<Booking> bookings) {
    final myId = widget.api.storedUser?.id ?? '';
    final map = <String, List<Booking>>{};
    final names = <String, String>{};
    for (final b in bookings) {
      final otherId = b.clientUserId == myId ? b.workerUserId : b.clientUserId;
      final otherName = b.clientUserId == myId
          ? (b.workerName ?? 'Worker')
          : (b.clientName ?? 'Client');
      (map[otherId] ??= []).add(b);
      names[otherId] ??= otherName;
    }
    return map.entries
        .map((e) => (userId: e.key, name: names[e.key]!, bookings: e.value))
        .toList();
  }

  List<Conversation> get _sortedConversations {
    final pinned = _conversations.where((c) => _pinned.contains(c.id)).toList();
    final rest = _conversations.where((c) => !_pinned.contains(c.id)).toList();
    return [...pinned, ...rest];
  }

  Future<void> _load() async {
    // 1. Show cached data immediately — no full-screen spinner if cache exists.
    //    Do NOT set _initialLoadDone or _lastSeen from cache: stale timestamps
    //    cause false "unread" badges when fresh data arrives with newer updatedAt.
    if (_bookings.isEmpty && _conversations.isEmpty) {
      final cachedBookings = await LocalDb.instance.getCachedBookings();
      final cachedConvs = await LocalDb.instance.getCachedConversations();
      if ((cachedBookings.isNotEmpty || cachedConvs.isNotEmpty) && mounted) {
        setState(() {
          _bookings = cachedBookings.map(Booking.fromJson).toList();
          _conversations = cachedConvs.map(Conversation.fromJson).toList();
          _message = '';
        });
      } else if (mounted) {
        setState(() => _loading = true);
      }
    }
    if (mounted) setState(() => _refreshing = true);

    // 2. Fetch fresh data in background
    try {
      final results = await Future.wait([
        widget.api.getMyBookings(),
        widget.api.getMyConversations(search: _searchQuery),
      ]);
      if (!mounted) return;
      final bookings = results[0] as List<Booking>;
      final convs = results[1] as List<Conversation>;
      unawaited(LocalDb.instance
          .cacheBookings(bookings.map((b) => b.toJson()).toList()));
      unawaited(LocalDb.instance
          .cacheConversations(convs.map((c) => c.toJson()).toList()));
      setState(() {
        _bookings = bookings;
        _conversations = convs;
        _message = '';
        _activeGroupIndex = 0;
        _historyGroupIndex = 0;
        _loading = false;
        _refreshing = false;
        // Auto-mark as seen any conversation where the current user sent the
        // last message — the sender can never have an unread on their own message.
        final myId = widget.api.storedUser?.id ?? '';
        var changed = false;
        for (final c in convs) {
          if (c.lastSenderId == myId) {
            _lastSeen[c.id] = c.updatedAt;
            changed = true;
          }
        }
        if (changed) unawaited(_persistLastSeen());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        if (_bookings.isEmpty && _conversations.isEmpty) {
          _message = friendlyError(error);
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadConversations([String search = '']) async {
    try {
      final list = await widget.api.getMyConversations(search: search);
      if (search.isEmpty) {
        unawaited(LocalDb.instance
            .cacheConversations(list.map((c) => c.toJson()).toList()));
      }
      if (mounted) {
        final myId = widget.api.storedUser?.id ?? '';
        var changed = false;
        for (final c in list) {
          if (c.lastSenderId == myId) {
            _lastSeen[c.id] = c.updatedAt;
            changed = true;
          }
        }
        setState(() => _conversations = list);
        if (changed) unawaited(_persistLastSeen());
      }
    } catch (_) {
      if (search.isEmpty && mounted) {
        final cached = await LocalDb.instance.getCachedConversations();
        if (cached.isNotEmpty && mounted) {
          setState(() =>
              _conversations = cached.map(Conversation.fromJson).toList());
        }
      }
    }
  }

  static const _reasonStatuses = {
    'cancellation_requested',
    'cancelled',
    'rejected'
  };

  Future<String?> _promptReason(String status) async {
    final title =
        status == 'rejected' ? 'Reason for declining' : 'Reason for cancelling';
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'Tell the other party why...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Confirm')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _updateStatus(Booking booking, String status) async {
    String? reason;
    if (_reasonStatuses.contains(status)) {
      reason = await _promptReason(status);
      if (reason == null || !mounted) return; // user cancelled the dialog
    }

    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('update_booking_status', {
        'bookingId': booking.id,
        'status': status,
        if (reason != null && reason.isNotEmpty) 'cancellationReason': reason,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Status update queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    await widget.api
        .updateBookingStatus(booking.id, status, cancellationReason: reason);
    await _load();
  }

  Future<void> _openReschedule(Booking booking) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RescheduleSheet(
        api: widget.api,
        booking: booking,
        onSaved: _load,
      ),
    );
  }

  Future<void> _deleteBooking(Booking booking) async {
    if (!SyncService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You\'re offline — can\'t delete bookings right now'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove booking?'),
        content:
            const Text('This will permanently remove this booking record.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteBooking(booking.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _repostBooking(Booking booking) async {
    final payload = JobPostPayload(
      postType: 'looking_for_worker',
      title: booking.jobTitle?.trim().isNotEmpty == true
          ? booking.jobTitle!.trim()
          : booking.serviceCategory,
      category: booking.serviceCategory,
      municipality: booking.municipality,
      locationDetails: booking.locationDetails,
      description: booking.notes.isEmpty
          ? 'Reposted job from booking history.'
          : booking.notes,
      workersNeeded: 1,
    );
    try {
      await widget.api.repostBooking(booking.id, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Job reposted to Browse.'),
      ));
      widget.openJobs?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _openBookingDetail(Booking booking) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BookingDetailSheet(
        booking: booking,
        myId: widget.api.storedUser?.id ?? '',
        onStatus: (status) async {
          Navigator.pop(ctx);
          await _updateStatus(booking, status);
        },
        onMessage: () {
          Navigator.pop(ctx);
          _messageOtherParty(booking);
        },
        onReschedule: () {
          Navigator.pop(ctx);
          _openReschedule(booking);
        },
      ),
    );
  }

  Future<void> _messageOtherParty(Booking booking) async {
    if (!SyncService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You\'re offline — messaging requires a connection'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final myId = widget.api.storedUser?.id ?? '';
    final isRequester = booking.clientUserId == myId;
    final otherUserId =
        isRequester ? booking.workerUserId : booking.clientUserId;
    final otherName = isRequester
        ? (booking.workerName ?? 'Worker')
        : (booking.clientName ?? 'Client');

    // Try to find existing conversation; otherwise create one
    Conversation? conv;
    try {
      final all = await widget.api.getMyConversations();
      conv = all.firstWhere(
        (c) =>
            (c.clientUserId == myId && c.providerUserId == otherUserId) ||
            (c.providerUserId == myId && c.clientUserId == otherUserId),
        orElse: () => throw StateError('none'),
      );
    } catch (_) {
      // No existing conversation — create one
      try {
        final convJson = await widget.api.startInquiry(otherUserId,
            'Hi, regarding our booking for ${booking.jobTitle?.trim().isNotEmpty == true ? booking.jobTitle!.trim() : booking.serviceCategory}.');
        conv = Conversation(
          id: convJson['id']?.toString() ?? '',
          clientUserId: myId,
          clientName: widget.api.storedUser?.fullName,
          providerUserId: otherUserId,
          providerName: otherName,
          lastMessagePreview: '',
          updatedAt: DateTime.now(),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
        return;
      }
    }

    if (!mounted) return;
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          api: widget.api,
          conversation: conv!,
          title: otherName,
        ),
      ),
    );
    _loadConversations(_searchQuery);
  }

  Future<void> _startNewConversation() async {
    if (!SyncService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You\'re offline — can\'t start new conversations'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final result = await showModalBottomSheet<_NewConvResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NewConversationSheet(api: widget.api),
    );
    if (result == null || !mounted) return;
    try {
      final convJson =
          await widget.api.startInquiry(result.userId, result.initialMessage);
      final conv = Conversation(
        id: convJson['id']?.toString() ?? '',
        clientUserId: widget.api.storedUser?.id ?? '',
        clientName: widget.api.storedUser?.fullName,
        providerUserId: result.userId,
        providerName: result.userName,
        lastMessagePreview: result.initialMessage,
        updatedAt: DateTime.now(),
      );
      if (!mounted) return;
      await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            api: widget.api,
            conversation: conv,
            title: result.userName,
          ),
        ),
      );
      _loadConversations(_searchQuery);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _deleteSelectedConversations() async {
    if (_selectedConvIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Delete ${_selectedConvIds.length} conversation${_selectedConvIds.length == 1 ? '' : 's'}?'),
        content: const Text(
            'All messages in the selected conversations will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final id in List.of(_selectedConvIds)) {
      try {
        await widget.api.deleteConversation(id);
      } catch (_) {}
    }
    setState(() {
      _conversations = _conversations
          .where((c) => !_selectedConvIds.contains(c.id))
          .toList();
      _selectedConvIds.clear();
      _inboxSelectMode = false;
    });
  }

  Future<void> _deleteAllConversations() async {
    if (_conversations.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all conversations?'),
        content: const Text(
            'All messages will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete All',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final c in List.of(_conversations)) {
      try {
        await widget.api.deleteConversation(c.id);
      } catch (_) {}
    }
    setState(() {
      _conversations = [];
      _selectedConvIds.clear();
      _inboxSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inboxActions = _segment == 2
        ? _inboxSelectMode
            ? [
                if (_selectedConvIds.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteSelectedConversations,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    label: Text('Delete (${_selectedConvIds.length})',
                        style: const TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () => setState(() {
                    _inboxSelectMode = false;
                    _selectedConvIds.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ]
            : [
                if (_conversations.isNotEmpty)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'select')
                        setState(() => _inboxSelectMode = true);
                      if (v == 'delete_all') _deleteAllConversations();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'select', child: Text('Select messages')),
                      PopupMenuItem(
                          value: 'delete_all',
                          child: Text('Delete all',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
              ]
        : const <Widget>[];

    return Scaffold(
      appBar: AppBar(actions: inboxActions),
      floatingActionButton: _segment == 2 && !_inboxSelectMode
          ? FloatingActionButton(
              onPressed: _startNewConversation,
              tooltip: 'New message',
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      body: Column(
        children: [
          if (_refreshing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0,
                    icon: Badge(
                      isLabelVisible: widget.pendingBookingCount > 0,
                      label: Text('${widget.pendingBookingCount}'),
                      child: const Icon(Icons.list_outlined),
                    ),
                    label: const Text('Booked')),
                const ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.history_outlined),
                    label: Text('History')),
                ButtonSegment(
                    value: 2,
                    icon: Badge(
                      isLabelVisible: _unreadCount > 0,
                      label: Text('$_unreadCount'),
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                    label: const Text('Inbox')),
              ],
              selected: {_segment},
              onSelectionChanged: (value) =>
                  setState(() => _segment = value.first),
            ),
            const SizedBox(height: 12),
            if (_segment == 1 || _segment == 2) ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: _segment == 1
                      ? 'Search job history...'
                      : 'Search conversations...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_loading) const SkeletonBookingList(),
            if (!_loading && _message.isNotEmpty)
              EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: _message,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Retry'))),
            if (!_loading && _message.isEmpty && _segment == 0) ...[
              if (_activeBookings.isEmpty)
                const EmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'No active bookings',
                  subtitle:
                      'Find a provider in Explore and send your first booking request.',
                )
              else ...[
                _PersonSelector(
                  groups: _grouped(_activeBookings),
                  selectedIndex: _activeGroupIndex.clamp(
                      0, _grouped(_activeBookings).length - 1),
                  onSelected: (i) => setState(() => _activeGroupIndex = i),
                ),
                const SizedBox(height: 8),
                Builder(builder: (ctx) {
                  final groups = _grouped(_activeBookings);
                  final idx = _activeGroupIndex.clamp(0, groups.length - 1);
                  final group = groups[idx];
                  return _GroupDetail(
                    userId: group.userId,
                    name: group.name,
                    bookings: group.bookings,
                    myId: widget.api.storedUser?.id ?? '',
                    api: widget.api,
                    onStatus: _updateStatus,
                    onMessage: _messageOtherParty,
                    onReschedule: _openReschedule,
                    onTap: _openBookingDetail,
                  );
                }),
              ],
            ],
            if (!_loading && _message.isEmpty && _segment == 1) ...[
              if (_filteredHistoryBookings.isEmpty)
                const EmptyState(
                  icon: Icons.history_outlined,
                  title: 'No history found',
                  subtitle:
                      'Completed and cancelled bookings will appear here.',
                )
              else ...[
                _PersonSelector(
                  groups: _grouped(_filteredHistoryBookings),
                  selectedIndex: _historyGroupIndex.clamp(
                      0, _grouped(_filteredHistoryBookings).length - 1),
                  onSelected: (i) => setState(() => _historyGroupIndex = i),
                ),
                const SizedBox(height: 8),
                Builder(builder: (ctx) {
                  final groups = _grouped(_filteredHistoryBookings);
                  final idx = _historyGroupIndex.clamp(0, groups.length - 1);
                  final group = groups[idx];
                  return _GroupDetail(
                    userId: group.userId,
                    name: group.name,
                    bookings: group.bookings,
                    myId: widget.api.storedUser?.id ?? '',
                    api: widget.api,
                    onStatus: _updateStatus,
                    onMessage: _messageOtherParty,
                    onTap: _openBookingDetail,
                    onDeleteBooking: _deleteBooking,
                    onRepostBooking: _repostBooking,
                  );
                }),
              ],
            ],
            if (!_loading && _message.isEmpty && _segment == 2)
              ..._sortedConversations.map((conv) {
                final isSelected = _selectedConvIds.contains(conv.id);
                if (_inboxSelectMode) {
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedConvIds.add(conv.id);
                      } else {
                        _selectedConvIds.remove(conv.id);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      conv.clientUserId == widget.api.storedUser?.id
                          ? conv.providerName ?? 'User'
                          : conv.clientName ?? 'User',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      conv.lastMessagePreview.isEmpty
                          ? 'No messages'
                          : conv.lastMessagePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }
                return ConversationTile(
                  api: widget.api,
                  conversation: conv,
                  isUnread: _isUnread(conv),
                  isPinned: _pinned.contains(conv.id),
                  onDeleted: () => setState(() => _conversations =
                      _conversations.where((c) => c.id != conv.id).toList()),
                  onTogglePin: () => _togglePin(conv.id),
                  onToggleRead: () => _isUnread(conv)
                      ? _markSeen(conv.id)
                      : _markUnread(conv.id),
                  onOpened: () {
                    _markSeen(conv.id);
                    _loadConversations(_searchQuery);
                  },
                );
              }),
            if (!_loading &&
                _message.isEmpty &&
                _segment == 2 &&
                _conversations.isEmpty)
              const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  subtitle: 'Tap the edit button to start a conversation.'),
          ],
        ),
      )),
        ],
      ),
    );
  }
}

/// Horizontal scrollable row of person avatar chips.
class _PersonSelector extends StatelessWidget {
  const _PersonSelector({
    required this.groups,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<({String userId, String name, List<Booking> bookings})> groups;
  final int selectedIndex;
  final void Function(int) onSelected;

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final group = groups[i];
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 70,
              decoration: BoxDecoration(
                color: selected
                    ? appPrimary.withAlpha(20)
                    : Theme.of(ctx).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? appPrimary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        selected ? appPrimary : appPrimary.withAlpha(40),
                    child: Text(
                      _initials(group.name),
                      style: TextStyle(
                        color: selected ? Colors.white : appPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      group.name.split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? appPrimary : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Text(
                    '${group.bookings.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? appPrimary : appMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shows the bookings for one selected person, split by role.
class _GroupDetail extends StatelessWidget {
  const _GroupDetail({
    required this.userId,
    required this.name,
    required this.bookings,
    required this.myId,
    required this.api,
    required this.onStatus,
    required this.onMessage,
    this.onReschedule,
    required this.onTap,
    this.onDeleteBooking,
    this.onRepostBooking,
  });

  final String userId;
  final String name;
  final List<Booking> bookings;
  final String myId;
  final MarketplaceApi api;
  final Future<void> Function(Booking, String) onStatus;
  final Future<void> Function(Booking) onMessage;
  final Future<void> Function(Booking)? onReschedule;
  final Future<void> Function(Booking) onTap;
  final Future<void> Function(Booking)? onDeleteBooking;
  final Future<void> Function(Booking)? onRepostBooking;

  @override
  Widget build(BuildContext context) {
    final asClient = bookings.where((b) => b.clientUserId == myId).toList();
    final asWorker = bookings.where((b) => b.workerUserId == myId).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (asClient.isNotEmpty)
          _RoleSection(
            label: 'You are the client',
            icon: Icons.person_outlined,
            bookings: asClient,
            myId: myId,
            api: api,
            onStatus: onStatus,
            onMessage: onMessage,
            onReschedule: onReschedule,
            onTap: onTap,
            onDeleteBooking: onDeleteBooking,
            onRepostBooking: onRepostBooking,
          ),
        if (asWorker.isNotEmpty) ...[
          if (asClient.isNotEmpty) const SizedBox(height: 4),
          _RoleSection(
            label: 'You are the worker',
            icon: Icons.work_outline,
            bookings: asWorker,
            myId: myId,
            api: api,
            onStatus: onStatus,
            onMessage: onMessage,
            onReschedule: onReschedule,
            onTap: onTap,
            onDeleteBooking: onDeleteBooking,
            onRepostBooking: onRepostBooking,
          ),
        ],
      ],
    );
  }
}

class _RoleSection extends StatelessWidget {
  const _RoleSection({
    required this.label,
    required this.icon,
    required this.bookings,
    required this.myId,
    required this.api,
    required this.onStatus,
    required this.onMessage,
    this.onReschedule,
    required this.onTap,
    this.onDeleteBooking,
    this.onRepostBooking,
  });

  final String label;
  final IconData icon;
  final List<Booking> bookings;
  final String myId;
  final MarketplaceApi api;
  final Future<void> Function(Booking, String) onStatus;
  final Future<void> Function(Booking) onMessage;
  final Future<void> Function(Booking)? onReschedule;
  final Future<void> Function(Booking) onTap;
  final Future<void> Function(Booking)? onDeleteBooking;
  final Future<void> Function(Booking)? onRepostBooking;

  @override
  Widget build(BuildContext context) {
    final isHired = icon == Icons.work_outline;
    final accentColor = isHired ? Colors.teal : appPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(0, 6, 0, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withAlpha(18),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: accentColor, width: 3)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 0.2)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${bookings.length} booking${bookings.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 11,
                    color: accentColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...bookings.asMap().entries.map((entry) {
                  final booking = entry.value;
                  return SizedBox(
                    width: 300,
                    child: BookingCard(
                      booking: booking,
                      myId: myId,
                      api: api,
                      onStatus: (status) => onStatus(booking, status),
                      onMessage: () => onMessage(booking),
                      onReschedule: onReschedule != null
                          ? () => onReschedule!(booking)
                          : null,
                      onTap: () => onTap(booking),
                      onRepost: onRepostBooking != null &&
                              booking.clientUserId == myId &&
                              ['completed', 'cancelled', 'rejected']
                                  .contains(booking.status)
                          ? () => onRepostBooking!(booking)
                          : null,
                      onDelete: onDeleteBooking != null &&
                              ['completed', 'cancelled', 'rejected']
                                  .contains(booking.status)
                          ? () => onDeleteBooking!(booking)
                          : null,
                    ),
                  );
                }),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BookingDetailSheet extends StatelessWidget {
  const _BookingDetailSheet({
    required this.booking,
    required this.myId,
    required this.onStatus,
    required this.onMessage,
    required this.onReschedule,
  });
  final Booking booking;
  final String myId;
  final Future<void> Function(String) onStatus;
  final VoidCallback onMessage;
  final VoidCallback onReschedule;

  bool get _isClient => booking.clientUserId == myId;
  bool get _isWorker => booking.workerUserId == myId;
  bool get _isApprover =>
      (booking.source == 'job_application'
          ? booking.clientUserId
          : booking.workerUserId) ==
      myId;

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

  String get _displayTitle => booking.jobTitle?.trim().isNotEmpty == true
      ? booking.jobTitle!.trim()
      : booking.serviceCategory;

  Color _statusColor(String s) {
    switch (s) {
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

  String _statusLabel(String s) {
    switch (s) {
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
        return s;
    }
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: appMuted),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: appMuted, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(booking.status);
    final isActive =
        !['completed', 'rejected', 'cancelled'].contains(booking.status);
    final canReschedule = (_isClient && booking.status == 'pending') ||
        (_isWorker && booking.status == 'accepted');
    final otherName = _isClient
        ? (booking.workerName ?? 'Worker')
        : (booking.clientName ?? 'Client');

    List<(String, String, bool)> actions() {
      if (_isClient) {
        if (booking.status == 'completion_requested')
          return [('Confirm Complete', 'completed', true)];
      }
      if (booking.status == 'pending') {
        if (_isApprover)
          return [('Accept', 'accepted', true), ('Decline', 'rejected', false)];
        return [('Cancel Booking', 'cancellation_requested', false)];
      }
      if (_isClient) {
        if (['accepted', 'in_progress'].contains(booking.status))
          return [('Cancel Booking', 'cancellation_requested', false)];
      } else if (_isWorker) {
        if (booking.status == 'accepted')
          return [
            ('Start Job', 'in_progress', true),
            ('Cancel', 'cancellation_requested', false)
          ];
        if (booking.status == 'in_progress')
          return [
            ('Mark Complete', 'completion_requested', true),
            ('Cancel', 'cancellation_requested', false)
          ];
      }
      if (booking.status == 'cancellation_requested')
        return [('Finalize Cancel', 'cancelled', false)];
      return [];
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Status badge
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(booking.status),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
            const Spacer(),
            Text(DateFormat('MMM d, yyyy').format(booking.createdAt),
                style: const TextStyle(color: appMuted, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          Text(_displayTitle,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(_isClient ? 'Worker: $otherName' : 'Client: $otherName',
              style: const TextStyle(
                  color: appPrimary, fontWeight: FontWeight.w600)),
          const Divider(height: 24),
          _infoRow(Icons.local_offer_outlined, 'Source', _sourceLabel),
          _infoRow(
              Icons.place_outlined,
              'Location',
              booking.municipality +
                  (booking.locationDetails.isNotEmpty
                      ? ' · ${booking.locationDetails}'
                      : '')),
          _infoRow(
              Icons.calendar_month_outlined,
              'Schedule',
              booking.scheduledAt == null
                  ? 'Not set'
                  : DateFormat('EEE, MMM d, yyyy · hh:mm a')
                      .format(booking.scheduledAt!.toLocal())),
          if (booking.notes.isNotEmpty)
            _infoRow(Icons.notes_outlined, 'Notes', booking.notes),
          if (booking.rescheduleNote != null &&
              booking.rescheduleNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(60)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.edit_calendar_outlined,
                    size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('Rescheduled: ${booking.rescheduleNote}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.deepOrange))),
              ]),
            ),
          ],
          if (booking.cancellationReason != null &&
              booking.cancellationReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(50)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Reason: ${booking.cancellationReason}',
                      style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          // Action buttons
          ...actions().map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: a.$3
                    ? FilledButton(
                        onPressed: () => onStatus(a.$2),
                        style: FilledButton.styleFrom(
                            backgroundColor: color,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text(a.$1,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      )
                    : OutlinedButton(
                        onPressed: () => onStatus(a.$2),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: [
                            'rejected',
                            'cancellation_requested',
                            'cancelled'
                          ].contains(a.$2)
                              ? Colors.red
                              : color,
                          side: BorderSide(
                              color: [
                            'rejected',
                            'cancellation_requested',
                            'cancelled'
                          ].contains(a.$2)
                                  ? Colors.red
                                  : color),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(a.$1, style: const TextStyle(fontSize: 15)),
                      ),
              )),
          if (isActive && booking.status != 'pending') ...[
            OutlinedButton.icon(
              onPressed: onMessage,
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Message'),
              style: OutlinedButton.styleFrom(
                foregroundColor: appPrimary,
                side: const BorderSide(color: appPrimary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (canReschedule) ...[
            OutlinedButton.icon(
              onPressed: onReschedule,
              icon: const Icon(Icons.edit_calendar_outlined, size: 16),
              label: const Text('Move Date'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewConvResult {
  const _NewConvResult(
      {required this.userId,
      required this.userName,
      required this.initialMessage});
  final String userId;
  final String userName;
  final String initialMessage;
}

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet({required this.api});
  final MarketplaceApi api;

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  var _results = <UserSearchResult>[];
  UserSearchResult? _selected;
  var _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await widget.api.searchUsers(q.trim());
      if (mounted) setState(() => _results = r);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
                child: Text('New Message',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 12),
          if (_selected == null) ...[
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search for a user...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                filled: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator())),
            if (!_searching)
              ..._results.map((u) => ListTile(
                    leading: Avatar(label: u.initials),
                    title: Text(u.fullName),
                    onTap: () => setState(() => _selected = u),
                  )),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(label: _selected!.initials),
              title: Text(_selected!.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Change')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              minLines: 2,
              maxLines: 5,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Write your first message...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final msg = _msgCtrl.text.trim();
                if (msg.isEmpty) return;
                Navigator.pop(
                  context,
                  _NewConvResult(
                    userId: _selected!.id,
                    userName: _selected!.fullName,
                    initialMessage: msg,
                  ),
                );
              },
              child: const Text('Start Conversation'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({
    required this.api,
    required this.booking,
    required this.onSaved,
  });
  final MarketplaceApi api;
  final Booking booking;
  final VoidCallback onSaved;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  DateTime? _date;
  TimeOfDay? _time;
  final _noteCtrl = TextEditingController();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing scheduled date if any
    if (widget.booking.scheduledAt != null) {
      final dt = widget.booking.scheduledAt!.toLocal();
      _date = DateTime(dt.year, dt.month, dt.day);
      _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select new date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a new date.')));
      return;
    }
    final t = _time ?? const TimeOfDay(hour: 8, minute: 0);
    final scheduledAt =
        DateTime(_date!.year, _date!.month, _date!.day, t.hour, t.minute);

    setState(() => _saving = true);
    try {
      await widget.api.rescheduleBooking(
          widget.booking.id, scheduledAt, _noteCtrl.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Date updated successfully.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.booking.workerUserId == widget.api.storedUser?.id;
    final dateLabel = _date == null
        ? 'Select new date'
        : DateFormat('EEE, MMM d, yyyy').format(_date!);
    final timeLabel = _time == null ? 'Select time' : _time!.format(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Move Date',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            isProvider
                ? 'You can reschedule accepted bookings.'
                : 'You can move the date before the worker accepts.',
            style: const TextStyle(color: appMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'New Date',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(dateLabel,
                      style: TextStyle(color: _date == null ? appMuted : null)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _date == null ? null : _pickTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Time',
                    prefixIcon: const Icon(Icons.access_time_outlined),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    enabled: _date != null,
                  ),
                  child: Text(timeLabel,
                      style: TextStyle(color: _time == null ? appMuted : null)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason for moving date',
              hintText: 'e.g. Client requested an earlier slot...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm New Date'),
          ),
        ],
      ),
    );
  }
}
