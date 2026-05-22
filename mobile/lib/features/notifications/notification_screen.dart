import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../discover/post_detail_screen.dart';
import '../discover/user_profile_screen.dart';
import '../jobs/jobs_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, required this.api});
  final MarketplaceApi api;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  var _notifications = <AppNotification>[];
  var _loading = false;
  var _refreshing = false;
  var _navigating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1. Load cached notifications immediately
    if (_notifications.isEmpty) {
      final cached = await LocalDb.instance.getCachedNotifications();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _notifications = cached.map(AppNotification.fromJson).toList();
        });
      } else if (mounted) {
        setState(() => _loading = true);
      }
    }
    if (mounted) setState(() => _refreshing = true);

    // 2. Fetch fresh from network
    try {
      final notifs = await widget.api.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifs;
          _loading = false;
          _refreshing = false;
        });
        unawaited(LocalDb.instance.cacheNotifications(
            notifs.map((n) => n.toJson()).toList()));
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  Future<void> _markAllRead() async {
    await widget.api.markAllNotificationsRead();
    setState(() {
      _notifications = _notifications
          .map((n) => AppNotification(
                id: n.id,
                type: n.type,
                actorId: n.actorId,
                actorName: n.actorName,
                title: n.title,
                body: n.body,
                linkType: n.linkType,
                linkId: n.linkId,
                isRead: true,
                createdAt: n.createdAt,
              ))
          .toList();
    });
  }

  Future<void> _onTap(AppNotification notif) async {
    if (!notif.isRead) {
      await widget.api.markNotificationRead(notif.id);
      setState(() {
        _notifications = _notifications
            .map((n) => n.id == notif.id
                ? AppNotification(
                    id: n.id,
                    type: n.type,
                    actorId: n.actorId,
                    actorName: n.actorName,
                    title: n.title,
                    body: n.body,
                    linkType: n.linkType,
                    linkId: n.linkId,
                    isRead: true,
                    createdAt: n.createdAt,
                  )
                : n)
            .toList();
      });
    }

    if (!mounted) return;

    final linkType = notif.linkType;
    final linkId = notif.linkId;

    if (linkType == 'post' && linkId != null) {
      await _openPost(linkId, notif.actorName);
    } else if (linkType == 'job' && linkId != null) {
      await _openJob(linkId);
    } else if (linkType == 'user' && linkId != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            api: widget.api,
            userId: linkId,
            displayName: notif.actorName,
          ),
        ),
      );
    } else if (notif.actorId != null &&
        (notif.type == 'follow' || notif.type == 'mention')) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            api: widget.api,
            userId: notif.actorId!,
            displayName: notif.actorName,
          ),
        ),
      );
    }
  }

  Future<void> _openJob(String jobPostId) async {
    setState(() => _navigating = true);
    try {
      final detail = await widget.api.getJobDetail(jobPostId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => JobDetailScreen(
            api: widget.api,
            job: detail.jobPost,
            onRefresh: () {},
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load job post.')),
        );
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _openPost(String postId, String actorName) async {
    setState(() => _navigating = true);
    try {
      final item = await widget.api.getFeedItem(postId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(
            item: item,
            api: widget.api,
            initialLiked: item.isLiked,
            initialLikeCount: item.likeCount,
            onLikeChanged: (_, __) {},
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load post.')),
        );
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'comment':
        return Icons.comment_outlined;
      case 'share':
        return Icons.share_outlined;
      case 'mention':
        return Icons.alternate_email;
      case 'job_offer':
        return Icons.work_outline;
      case 'offer_accepted':
        return Icons.check_circle_outline;
      case 'follow':
        return Icons.person_add_outlined;
      case 'booking':
        return Icons.calendar_month_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'comment':
        return Colors.blue;
      case 'share':
        return appPrimary;
      case 'mention':
        return Colors.orange;
      case 'job_offer':
        return const Color(0xFF2E7D32);
      case 'offer_accepted':
        return Colors.teal;
      case 'follow':
        return appPrimary;
      case 'booking':
        return Colors.indigo;
      default:
        return appMuted;
    }
  }

  Widget _buildAvatar(AppNotification n) {
    final parts = n.actorName.trim().split(' ');
    final initials = n.actorName.isEmpty
        ? '?'
        : (parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : n.actorName[0].toUpperCase());
    final color = _colorFor(n.type);

    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withAlpha(180)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 1.5,
              ),
            ),
            child: Icon(_iconFor(n.type), color: Colors.white, size: 10),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_navigating)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_outlined,
                            size: 64, color: appMuted),
                        SizedBox(height: 12),
                        Text('No notifications yet.',
                            style: TextStyle(color: appMuted, fontSize: 16)),
                      ],
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      if (_notifications.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none_outlined,
                                    size: 64, color: appMuted),
                                SizedBox(height: 12),
                                Text('No notifications yet.',
                                    style: TextStyle(
                                        color: appMuted, fontSize: 16)),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final n = _notifications[i];
                              final hasLink =
                                  n.linkType != null && n.linkId != null;
                              final canNavigate = hasLink ||
                                  (n.actorId != null &&
                                      (n.type == 'follow' ||
                                          n.type == 'mention'));
                              return Column(
                                children: [
                                  if (i > 0)
                                    const Divider(height: 1, indent: 76),
                                  InkWell(
                                    onTap: () => _onTap(n),
                                    child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          color: n.isRead
                              ? null
                              : appPrimary.withAlpha(15),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAvatar(n),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text(n.title,
                                            style: TextStyle(
                                              fontWeight: n.isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w800,
                                              fontSize: 14,
                                            )),
                                      ),
                                      if (!n.isRead)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(left: 6),
                                          decoration: const BoxDecoration(
                                            color: appPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ]),
                                    if (n.body.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(n.body,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: appMuted, fontSize: 13)),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Text(timeAgo(n.createdAt),
                                          style: const TextStyle(
                                              color: appMuted, fontSize: 12)),
                                      if (canNavigate) ...[
                                        const SizedBox(width: 6),
                                        const Text('·',
                                            style: TextStyle(
                                                color: appMuted, fontSize: 12)),
                                        const SizedBox(width: 6),
                                        Text('Tap to view',
                                            style: TextStyle(
                                                color: appPrimary
                                                    .withAlpha(180),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ]),
                                  ],
                                ),
                              ),
                              if (canNavigate)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, top: 2),
                                  child: Icon(Icons.chevron_right,
                                      color: appMuted, size: 20),
                                ),
                            ],
                          ),
                                    ),
                                  ),
                                ],
                              );
                            },
                            childCount: _notifications.length,
                          ),
                        ),
                      ],
                    ),
      )),
        ],
      ),
    );
  }

}
