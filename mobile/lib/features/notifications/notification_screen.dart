import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../shared/widgets/avatar.dart';
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
  var _suggestedUsers = <UserSearchResult>[];
  final Set<String> _followed = {};
  final Set<String> _following = {};
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
      final results = await Future.wait([
        widget.api.getNotifications(),
        widget.api.getSuggestedUsers(limit: 10),
      ]);
      if (mounted) {
        final notifs = results[0] as List<AppNotification>;
        setState(() {
          _notifications = notifs;
          _suggestedUsers = results[1] as List<UserSearchResult>;
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

  Future<void> _toggleFollow(UserSearchResult u) async {
    if (_following.contains(u.id)) return;
    _following.add(u.id);
    try {
      if (_followed.contains(u.id)) {
        await widget.api.unfollowUser(u.id);
        if (mounted) setState(() => _followed.remove(u.id));
      } else {
        await widget.api.followUser(u.id);
        if (mounted) setState(() => _followed.add(u.id));
      }
    } finally {
      _following.remove(u.id);
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
            : _notifications.isEmpty && _suggestedUsers.isEmpty
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
                      if (_suggestedUsers.isNotEmpty)
                        SliverToBoxAdapter(child: _buildSuggestedSection()),
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

  Widget _buildSuggestedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            const Icon(Icons.people_alt_outlined, size: 18, color: appPrimary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('People You May Know',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: appPrimary)),
            ),
          ]),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: _suggestedUsers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final u = _suggestedUsers[i];
              final isFollowed = _followed.contains(u.id);
              final isFollowing = _following.contains(u.id);
              return _SuggestedCard(
                user: u,
                isFollowed: isFollowed,
                isLoading: isFollowing,
                onToggle: () => _toggleFollow(u),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => UserProfileScreen(
                      api: widget.api,
                      userId: u.id,
                      displayName: u.fullName,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SuggestedCard extends StatelessWidget {
  const _SuggestedCard({
    required this.user,
    required this.isFollowed,
    required this.isLoading,
    required this.onToggle,
    required this.onTap,
  });
  final UserSearchResult user;
  final bool isFollowed;
  final bool isLoading;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Avatar(imageData: user.profilePic, name: user.fullName, radius: 28),
            const SizedBox(height: 8),
            Text(
              user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: appMuted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onToggle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            isFollowed ? appPrimary : Colors.transparent,
                        foregroundColor:
                            isFollowed ? Colors.white : appPrimary,
                        side: const BorderSide(color: appPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(isFollowed ? 'Following' : 'Follow',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    if (user.role != 'client') return _cap(user.role);
    if (user.followers > 0) return '${user.followers} followers';
    if (user.bio != null && user.bio!.isNotEmpty) return user.bio!;
    return '';
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
