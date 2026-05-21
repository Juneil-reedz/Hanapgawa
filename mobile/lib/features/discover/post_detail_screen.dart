import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/video_controller_cache.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/feed_header.dart';
import '../../shared/widgets/info_pill.dart';
import 'booking_sheet.dart';
import 'feed_card.dart';
import 'provider_detail_screen.dart';
import 'user_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.item,
    required this.api,
    required this.initialLiked,
    required this.initialLikeCount,
    required this.onLikeChanged,
  });
  final FeedItem item;
  final MarketplaceApi api;
  final bool initialLiked;
  final int initialLikeCount;
  final void Function(bool liked, int count) onLikeChanged;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late bool _liked;
  late int _likeCount;
  var _comments = <PostComment>[];
  var _commentsLoading = true;
  var _likers = <Map<String, dynamic>>[];
  var _sharers = <Map<String, dynamic>>[];
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  PostComment? _replyingTo;
  String? _commentGifUrl;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.initialLiked;
    _likeCount = widget.initialLikeCount;
    _loadComments();
    if (widget.item.socialPost != null) _loadLikersAndSharers();
  }

  @override
  void dispose() {
    _commentFocus.unfocus();
    _commentFocus.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLikersAndSharers() async {
    try {
      final results = await Future.wait([
        widget.api.getPostLikers(widget.item.type, widget.item.id),
        widget.api.getPostSharers(widget.item.type, widget.item.id),
      ]);
      if (mounted) {
        setState(() {
          _likers = results[0];
          _sharers = results[1];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    try {
      final comments =
          await widget.api.getPostComments(widget.item.type, widget.item.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _commentsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _toggleLike() async {
    final messenger = ScaffoldMessenger.of(context);
    // Optimistic update
    final prevLiked = _liked;
    final prevCount = _likeCount;
    setState(() {
      _liked = !_liked;
      _likeCount = _liked ? prevCount + 1 : prevCount - 1;
    });
    widget.onLikeChanged(_liked, _likeCount);
    try {
      final (liked, count) =
          await widget.api.toggleLike(widget.item.type, widget.item.id);
      if (!mounted) return;
      setState(() {
        _liked = liked;
        _likeCount = count;
      });
      widget.onLikeChanged(liked, count);
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('toggle_like', {
          'itemType': widget.item.type,
          'itemId': widget.item.id,
        });
      } else {
        // Revert optimistic update
        if (mounted) {
          setState(() {
            _liked = prevLiked;
            _likeCount = prevCount;
          });
          widget.onLikeChanged(prevLiked, prevCount);
        }
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _submitComment() async {
    final body = _commentCtrl.text.trim();
    final gifUrl = _commentGifUrl;
    if (body.isEmpty && gifUrl == null) return;
    final parent = _replyingTo;
    setState(() => _submitting = true);
    try {
      final comment = await widget.api.addPostComment(
        widget.item.type,
        widget.item.id,
        body,
        parentCommentId: parent?.id,
        gifUrl: gifUrl,
      );
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _replyingTo = null;
        _commentGifUrl = null;
        _comments = [..._comments, comment];
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('add_comment', {
          'itemType': widget.item.type,
          'itemId': widget.item.id,
          'body': body,
          if (parent?.id != null) 'parentCommentId': parent!.id,
          if (gifUrl != null) 'gifUrl': gifUrl,
        });
        _commentCtrl.clear();
        if (mounted) {
          setState(() {
            _replyingTo = null;
            _commentGifUrl = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              Icon(Icons.sync, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Comment queued — will post when online')),
            ]),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ));
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _replyTo(PostComment comment) {
    final isMine = comment.userId == (widget.api.storedUser?.id ?? '');
    final prefix = isMine ? '' : '@${comment.fullName} ';
    setState(() => _replyingTo = comment);
    _commentCtrl.text = prefix;
    _commentCtrl.selection = TextSelection.collapsed(offset: prefix.length);
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _pickCommentGif() async {
    final controller = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var loading = false;
    final gif = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Add GIF',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search GIFs'),
                onSubmitted: (value) async {
                  if (value.trim().isEmpty) return;
                  setSheetState(() => loading = true);
                  final found = await widget.api.searchGifs(value.trim());
                  setSheetState(() {
                    results = found;
                    loading = false;
                  });
                },
              ),
              if (loading)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator())
              else
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6),
                    itemCount: results.length,
                    itemBuilder: (_, index) {
                      final item = results[index];
                      final preview = item['previewUrl']?.toString() ??
                          item['url']?.toString() ??
                          '';
                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, item),
                        child: Image.network(preview, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
    if (gif != null) setState(() => _commentGifUrl = gif['url']?.toString());
  }

  void _openAuthorProfile(String userId, String name) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          api: widget.api,
          userId: userId,
          displayName: name,
        ),
      ),
    );
  }

  Future<void> _toggleCommentReaction(PostComment comment) async {
    if (widget.api.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to react to comments.')));
      return;
    }
    try {
      final (reacted, count) =
          await widget.api.toggleCommentReaction(comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments
            .map((c) => c.id == comment.id
                ? c.copyWith(reactionCount: count, isReacted: reacted)
                : c)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _editComment(PostComment comment) async {
    var draft = comment.body;
    final updatedBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextFormField(
          initialValue: comment.body,
          autofocus: true,
          maxLines: null,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(hintText: 'Update your comment'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, draft.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (updatedBody == null ||
        updatedBody.isEmpty ||
        updatedBody == comment.body) {
      return;
    }
    try {
      final updated =
          await widget.api.updatePostComment(comment.id, updatedBody);
      if (!mounted) return;
      setState(() {
        _comments = _comments
            .map((c) => c.id == comment.id
                ? updated.copyWith(
                    reactionCount: c.reactionCount,
                    isReacted: c.isReacted,
                  )
                : c)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _deleteComment(PostComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This comment will be permanently removed.'),
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
    if (confirmed != true) return;
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance
          .queueAction('delete_comment', {'commentId': comment.id});
      if (!mounted) return;
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
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
      await widget.api.deletePostComment(comment.id);
      if (!mounted) return;
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('delete_comment', {'commentId': comment.id});
        if (!mounted) return;
        setState(() => _comments.removeWhere((c) => c.id == comment.id));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildFullPost(context),
                _buildActionBar(context),
                const Divider(height: 24),
                _buildCommentsSection(context),
              ],
            ),
          ),
          if (widget.api.token.isNotEmpty) _buildCommentInput(context),
        ],
      ),
    );
  }

  Widget _buildFullPost(BuildContext context) {
    if (widget.item.listing != null) return _buildListingPost(context);
    if (widget.item.job != null) return _buildJobPost(context);
    if (widget.item.socialPost != null) return _buildSocialPost(context);
    if (widget.item.review != null) return _buildReviewPost(context);
    return const SizedBox.shrink();
  }

  Widget _buildSocialPost(BuildContext context) {
    final post = widget.item.socialPost!;
    final parts = post.fullName.trim().split(' ');
    final initials = post.fullName.isEmpty
        ? '?'
        : (parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : post.fullName[0].toUpperCase());

    return AppCard(
      accentColor: Colors.blue.shade700,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => _openAuthorProfile(post.userId, post.fullName),
          borderRadius: BorderRadius.circular(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: appPrimary),
              child: ClipOval(
                child: post.profilePic != null
                    ? (post.profilePic!.startsWith('http')
                        ? Image.network(post.profilePic!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                                child: Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800))))
                        : Image.memory(base64Decode(post.profilePic!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                                child: Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800)))))
                    : Center(
                        child: Text(initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(timeAgo(widget.item.createdAt),
                        style: const TextStyle(color: appMuted, fontSize: 12)),
                  ]),
            ),
          ]),
        ),
        if (post.metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          PostMetadata(metadata: post.metadata),
        ],
        if (post.body.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: post.metadata['backgroundColor'] is int
                  ? Color(post.metadata['backgroundColor'] as int)
                  : appSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(post.body,
                style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: post.metadata['backgroundColor'] is int
                        ? Colors.white
                        : null)),
          ),
        ],
        if (post.metadata['mediaItems'] is List &&
            (post.metadata['mediaItems'] as List).isNotEmpty) ...[
          const SizedBox(height: 10),
          _PostMediaGrid(
              items: List<Map<String, dynamic>>.from(
                  post.metadata['mediaItems'] as List)),
        ] else ...[
          if (post.image != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: post.image!.startsWith('http')
                  ? Image.network(post.image!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  : Image.memory(base64Decode(post.image!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
          if (post.video != null) ...[
            const SizedBox(height: 10),
            _InlineVideoPlayer(video: post.video!),
          ],
        ],
        if (post.sharedSnapshot != null) ...[
          const SizedBox(height: 10),
          SharedPostPreview(snapshot: post.sharedSnapshot!),
        ],
      ]),
    );
  }

  Widget _buildListingPost(BuildContext context) {
    final listing = widget.item.listing!;
    return AppCard(
      accentColor: appPrimary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => ProviderDetailScreen(
                  api: widget.api, providerUserId: listing.providerUserId),
            ),
          ),
          child: FeedHeader(
            name: listing.providerDisplayName ?? 'Worker',
            subtitle:
                '${listing.municipality} Â· ${timeAgo(widget.item.createdAt)}',
            badge: listing.providerRole,
            color: appPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Text(listing.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(listing.description),
        if (listing.requirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: listing.requirements
                  .map((tag) => Chip(label: Text(tag)))
                  .toList()),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('P${listing.priceMin} â€“ P${listing.priceMax}',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => BookingSheet(
                  api: widget.api, target: BookingTarget.fromListing(listing)),
            ),
            child: const Text('Book'),
          ),
        ]),
      ]),
    );
  }

  Widget _buildJobPost(BuildContext context) {
    final job = widget.item.job!;
    return AppCard(
      accentColor: Colors.green,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FeedHeader(
          name: job.clientFullName ?? 'Client',
          subtitle: '${job.municipality} Â· ${timeAgo(widget.item.createdAt)}',
          badge: job.postType == 'offering_service' ? 'client' : 'worker',
          color: Colors.green,
        ),
        const SizedBox(height: 14),
        Text(job.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(job.description),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          InfoPill(icon: Icons.work_outline, label: job.category),
          InfoPill(icon: Icons.place_outlined, label: job.municipality),
          InfoPill(icon: Icons.mail_outline, label: '${job.offerCount} offers'),
        ]),
        const SizedBox(height: 10),
        Text('P${job.budgetMin ?? 0} â€“ P${job.budgetMax ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
    );
  }

  Widget _buildReviewPost(BuildContext context) {
    final review = widget.item.review!;
    return AppCard(
      accentColor: Colors.orange,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FeedHeader(
          name: 'Review',
          subtitle: timeAgo(widget.item.createdAt),
          badge: '${review.rating}/5',
          color: Colors.orange,
        ),
        const SizedBox(height: 12),
        Row(
            children: List.generate(
                5,
                (index) => Icon(
                      index < review.rating ? Icons.star : Icons.star_border,
                      color: Colors.orange,
                      size: 22,
                    ))),
        const SizedBox(height: 8),
        Text(
            review.comment?.isEmpty ?? true
                ? 'No comment provided.'
                : '"${review.comment}"',
            style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Text('Worker: ${review.providerName ?? 'Worker'}',
            style: const TextStyle(color: appMuted)),
        if (review.reviewerName != null)
          Text('By: ${review.reviewerName}',
              style: const TextStyle(color: appMuted)),
      ]),
    );
  }

  void _showReactorSheet(String title, List<Map<String, dynamic>> people) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No one yet.', style: TextStyle(color: appMuted)),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: people.length,
                itemBuilder: (_, i) {
                  final p = people[i];
                  final name = p['fullName']?.toString() ?? 'User';
                  final pic = p['profilePic']?.toString();
                  final initials = name.trim().isEmpty
                      ? '?'
                      : name.trim().split(' ').length >= 2
                          ? '${name.trim().split(' ').first[0]}${name.trim().split(' ').last[0]}'
                              .toUpperCase()
                          : name[0].toUpperCase();
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: appPrimary,
                      backgroundImage: pic != null && pic.startsWith('http')
                          ? NetworkImage(pic)
                          : null,
                      child: pic == null || !pic.startsWith('http')
                          ? Text(initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700))
                          : null,
                    ),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final isSocialPost = widget.item.socialPost != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Reaction summary row (always visible for social posts) ───────────
        if (isSocialPost && (_likeCount > 0 || _sharers.isNotEmpty)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(children: [
              if (_likeCount > 0)
                GestureDetector(
                  onTap: () => _showReactorSheet(
                      '$_likeCount Like${_likeCount == 1 ? '' : 's'}', _likers),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                          color: Colors.red.shade400, shape: BoxShape.circle),
                      child: const Icon(Icons.favorite,
                          color: Colors.white, size: 12),
                    ),
                    const SizedBox(width: 4),
                    Text('$_likeCount',
                        style: const TextStyle(fontSize: 13, color: appMuted)),
                  ]),
                ),
              if (_likeCount > 0 && _sharers.isNotEmpty)
                const SizedBox(width: 12),
              if (_sharers.isNotEmpty)
                GestureDetector(
                  onTap: () => _showReactorSheet(
                      '${_sharers.length} Share${_sharers.length == 1 ? '' : 's'}',
                      _sharers),
                  child: Text(
                      '${_sharers.length} Share${_sharers.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 13, color: appMuted)),
                ),
            ]),
          ),
          const Divider(height: 8),
        ],
        // ── Action buttons row ───────────────────────────────────────────────
        Row(
          children: [
            // Like — tap icon to toggle, tap count to see likers
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: widget.api.token.isNotEmpty
                    ? _toggleLike
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Log in to like posts.'))),
                icon: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? Colors.red : appMuted,
                  size: 22,
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: isSocialPost
                    ? () => _showReactorSheet(
                        '$_likeCount Like${_likeCount == 1 ? '' : 's'}',
                        _likers)
                    : null,
                child: Text('$_likeCount',
                    style: TextStyle(
                        fontSize: 13,
                        color: appMuted,
                        decoration:
                            isSocialPost ? TextDecoration.underline : null)),
              ),
              const SizedBox(width: 16),
            ]),
            // Comment count
            const Icon(Icons.comment_outlined, size: 20, color: appMuted),
            const SizedBox(width: 4),
            Text('${_comments.length}',
                style: const TextStyle(fontSize: 13, color: appMuted)),
            const SizedBox(width: 16),
            // Share
            TextButton.icon(
              onPressed: () {
                if (widget.api.token.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Log in to share posts.')));
                  return;
                }
                final outerContext = context;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => ShareSheet(
                    item: widget.item,
                    api: widget.api,
                    onShared: () {
                      if (outerContext.mounted) {
                        ScaffoldMessenger.of(outerContext).showSnackBar(
                            const SnackBar(
                                content: Text('Post shared!'),
                                duration: Duration(seconds: 3)));
                      }
                    },
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined, size: 20, color: appMuted),
              label: const Text('Share', style: TextStyle(color: appMuted)),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_commentsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No comments yet. Be the first!',
                style: TextStyle(color: appMuted)),
          )
        else
          ..._comments
              .where((c) => c.parentCommentId == null)
              .map((c) => _CommentTile(
                    comment: c,
                    allComments: _comments,
                    replies: _comments
                        .where((r) => r.parentCommentId == c.id)
                        .toList(),
                    isMine: c.userId == (widget.api.storedUser?.id ?? ''),
                    onReply: () => _replyTo(c),
                    onReact: () => _toggleCommentReaction(c),
                    onEdit: () => _editComment(c),
                    onDelete: () => _deleteComment(c),
                    isReplyMine: (reply) =>
                        reply.userId == (widget.api.storedUser?.id ?? ''),
                    onReplyToReply: _replyTo,
                    onReactReply: _toggleCommentReaction,
                    onEditReply: _editComment,
                    onDeleteReply: _deleteComment,
                  )),
      ],
    );
  }

  Widget _buildCommentInput(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            12, 8, 12, 8 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyingTo != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: appSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.reply, size: 16, color: appMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Replying to ${_replyingTo!.fullName}',
                      style: const TextStyle(fontSize: 12, color: appMuted)),
                ),
                InkWell(
                    onTap: _cancelReply,
                    child: const Icon(Icons.close, size: 16)),
              ]),
            ),
          if (_commentGifUrl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Stack(children: [
                _CommentGifPreview(url: _commentGifUrl!),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _commentGifUrl = null),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                focusNode: _commentFocus,
                decoration: const InputDecoration(
                  hintText: 'Write a comment...',
                  isDense: true,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitComment(),
              ),
            ),
            IconButton(
              onPressed: _pickCommentGif,
              icon: const Icon(Icons.gif_box_outlined),
              color: appMuted,
              tooltip: 'Add GIF',
            ),
            const SizedBox(width: 8),
            _submitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    onPressed: _submitComment,
                    icon: const Icon(Icons.send),
                    color: appPrimary,
                  ),
          ]),
        ]),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.allComments,
    required this.replies,
    required this.isMine,
    required this.onReply,
    required this.onReact,
    required this.onEdit,
    required this.onDelete,
    required this.isReplyMine,
    required this.onReplyToReply,
    required this.onReactReply,
    required this.onEditReply,
    required this.onDeleteReply,
  });
  final PostComment comment;
  final List<PostComment> allComments;
  final List<PostComment> replies;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool Function(PostComment reply) isReplyMine;
  final void Function(PostComment reply) onReplyToReply;
  final void Function(PostComment reply) onReactReply;
  final void Function(PostComment reply) onEditReply;
  final void Function(PostComment reply) onDeleteReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isMine ? appPrimary : Colors.grey.shade400,
            child: Text(
              comment.fullName.isNotEmpty
                  ? comment.fullName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(comment.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text(timeAgo(comment.createdAt),
                      style: const TextStyle(color: appMuted, fontSize: 12)),
                ]),
                const SizedBox(height: 2),
                if (comment.body.isNotEmpty) Text(comment.body),
                if (comment.gifUrl != null) ...[
                  if (comment.body.isNotEmpty) const SizedBox(height: 6),
                  _CommentGifPreview(url: comment.gifUrl!),
                ],
                const SizedBox(height: 4),
                _CommentActions(
                  comment: comment,
                  isMine: isMine,
                  onReply: onReply,
                  onReact: onReact,
                  onEdit: onEdit,
                  onDelete: onDelete,
                ),
                if (replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(
                      border:
                          Border(left: BorderSide(color: appBorder, width: 2)),
                    ),
                    child: Column(
                      children: replies
                          .map((reply) => _ReplyTile(
                                reply: reply,
                                allComments: allComments,
                                isMine: isReplyMine(reply),
                                isReplyMine: isReplyMine,
                                onReply: () => onReplyToReply(reply),
                                onReact: () => onReactReply(reply),
                                onEdit: () => onEditReply(reply),
                                onDelete: () => onDeleteReply(reply),
                                onReplyToReply: onReplyToReply,
                                onReactReply: onReactReply,
                                onEditReply: onEditReply,
                                onDeleteReply: onDeleteReply,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.reply,
    required this.allComments,
    required this.isMine,
    required this.isReplyMine,
    required this.onReply,
    required this.onReact,
    required this.onEdit,
    required this.onDelete,
    required this.onReplyToReply,
    required this.onReactReply,
    required this.onEditReply,
    required this.onDeleteReply,
  });
  final PostComment reply;
  final List<PostComment> allComments;
  final bool isMine;
  final bool Function(PostComment reply) isReplyMine;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(PostComment reply) onReplyToReply;
  final void Function(PostComment reply) onReactReply;
  final void Function(PostComment reply) onEditReply;
  final void Function(PostComment reply) onDeleteReply;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(reply.fullName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 6),
            Text(timeAgo(reply.createdAt),
                style: const TextStyle(color: appMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 2),
          if (reply.body.isNotEmpty)
            Text(reply.body, style: const TextStyle(fontSize: 13)),
          if (reply.gifUrl != null) ...[
            if (reply.body.isNotEmpty) const SizedBox(height: 6),
            _CommentGifPreview(url: reply.gifUrl!, compact: true),
          ],
          _CommentActions(
            comment: reply,
            isMine: isMine,
            onReply: onReply,
            onReact: onReact,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
          ...allComments
              .where((child) => child.parentCommentId == reply.id)
              .map((child) => Padding(
                    padding: const EdgeInsets.only(left: 10, top: 4),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: appBorder, width: 2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _ReplyTile(
                          reply: child,
                          allComments: allComments,
                          isMine: isReplyMine(child),
                          isReplyMine: isReplyMine,
                          onReply: () => onReplyToReply(child),
                          onReact: () => onReactReply(child),
                          onEdit: () => onEditReply(child),
                          onDelete: () => onDeleteReply(child),
                          onReplyToReply: onReplyToReply,
                          onReactReply: onReactReply,
                          onEditReply: onEditReply,
                          onDeleteReply: onDeleteReply,
                        ),
                      ),
                    ),
                  )),
        ]),
      );
}

class _CommentGifPreview extends StatelessWidget {
  const _CommentGifPreview({required this.url, this.compact = false});

  final String url;
  final bool compact;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: compact ? 180 : double.infinity,
          height: compact ? 120 : 170,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: compact ? 180 : double.infinity,
            height: compact ? 80 : 110,
            alignment: Alignment.center,
            color: appSurface,
            child: const Text('GIF unavailable',
                style: TextStyle(color: appMuted, fontSize: 12)),
          ),
        ),
      );
}

class _CommentActions extends StatelessWidget {
  const _CommentActions({
    required this.comment,
    required this.isMine,
    required this.onReply,
    required this.onReact,
    required this.onEdit,
    required this.onDelete,
  });
  final PostComment comment;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: onReply,
            icon: const Icon(Icons.reply_outlined, size: 16),
            label: const Text('Reply'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          TextButton.icon(
            onPressed: onReact,
            icon: Icon(
              comment.isReacted ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: comment.isReacted ? Colors.red : appMuted,
            ),
            label: Text(comment.reactionCount.toString()),
            style: TextButton.styleFrom(
              foregroundColor: comment.isReacted ? Colors.red : appMuted,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          if (isMine) ...[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 17),
              tooltip: 'Edit comment',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 17),
              color: Colors.red.shade700,
              tooltip: 'Delete comment',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ],
      );
}

String _toCloudinaryMp4(String url) {
  if (!url.contains('res.cloudinary.com')) return url;
  if (url.contains('/upload/f_mp4,vc_h264') ||
      url.contains('/upload/vc_h264,f_mp4')) {
    return url;
  }
  return url.replaceFirst('/upload/', '/upload/f_mp4,vc_h264/');
}

// ─── Multi-media grid (detail display) ────────────────────────────────────────

class _PostMediaGrid extends StatelessWidget {
  const _PostMediaGrid({required this.items});
  final List<Map<String, dynamic>> items;

  Widget _cell(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? 'image';
    final url = item['url']?.toString() ?? '';
    if (type == 'video') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _InlineVideoPlayer(video: url),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.startsWith('http')
          ? Image.network(url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Colors.black12))
          : Image.memory(base64Decode(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Colors.black12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    if (count == 1) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: _cell(items[0]),
      );
    }

    return SizedBox(
      height: 360,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: count,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _cell(items[index]),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${index + 1}/$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({required this.video});
  final String video;

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  static VideoPlayerController? _activeVideoController;

  VideoPlayerController? _controller;
  VoidCallback? _playbackListener;
  ScrollPosition? _scrollPosition;
  VoidCallback? _scrollListener;
  bool _initialized = false;
  bool _error = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    final cached = VideoControllerCache.peek(widget.video);
    if (cached?.isReady == true) {
      _controller = cached!.controller;
      _initialized = true;
      cached.touch();
      _attachPlaybackMonitor(cached.controller);
    }
    _init();
  }

  Future<void> _init() async {
    try {
      final v = widget.video;
      final ctrl = await _controllerFor(v);
      if (identical(_controller, ctrl) && _initialized) return;
      if (mounted) {
        _attachPlaybackMonitor(ctrl);
        setState(() {
          _controller = ctrl;
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint('[VideoPlayer] detail init error: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    final listener = _playbackListener;
    if (listener != null) {
      _controller?.removeListener(listener);
    }
    final scrollListener = _scrollListener;
    final scrollPosition = _scrollPosition;
    if (scrollListener != null && scrollPosition != null) {
      scrollPosition.removeListener(scrollListener);
    }
    if (identical(_activeVideoController, _controller)) {
      _activeVideoController = null;
    }
    _controller?.pause();
    super.dispose();
  }

  void _attachPlaybackMonitor(VideoPlayerController ctrl) {
    final oldListener = _playbackListener;
    if (oldListener != null) {
      _controller?.removeListener(oldListener);
    }
    _playbackListener = () {
      if (ctrl.value.isPlaying) _attachScrollMonitor();
    };
    ctrl.addListener(_playbackListener!);
  }

  void _attachScrollMonitor() {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || identical(position, _scrollPosition)) return;

    final oldListener = _scrollListener;
    final oldPosition = _scrollPosition;
    if (oldListener != null && oldPosition != null) {
      oldPosition.removeListener(oldListener);
    }

    _scrollPosition = position;
    _scrollListener = () => _pauseIfOffscreen();
    position.addListener(_scrollListener!);
  }

  void _pauseIfOffscreen() {
    final ctrl = _controller;
    if (!mounted || ctrl == null || !ctrl.value.isPlaying) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottom = topLeft.dy + renderObject.size.height;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visibleTop = topLeft.dy.clamp(0.0, screenHeight);
    final visibleBottom = bottom.clamp(0.0, screenHeight);
    final visibleHeight = visibleBottom - visibleTop;

    if (visibleHeight <= renderObject.size.height * 0.1) {
      ctrl.pause();
    }
  }

  Future<void> _toggleMute() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final nextMuted = !_muted;
    await ctrl.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => _muted = nextMuted);
  }

  Future<VideoPlayerController> _controllerFor(String source) async {
    return VideoControllerCache.get(source, () => _createController(source));
  }

  Future<VideoPlayerController> _createController(String source) async {
    VideoPlayerController ctrl;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final transformed = _toCloudinaryMp4(source);
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(source),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await ctrl.initialize();
      } catch (_) {
        if (transformed != source) {
          await ctrl.dispose();
          ctrl = VideoPlayerController.networkUrl(
            Uri.parse(transformed),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
          await ctrl.initialize();
        } else {
          rethrow;
        }
      }
    } else {
      final payload = source.contains(',') ? source.split(',').last : source;
      final bytes = base64Decode(payload);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/detail_video_${source.hashCode}.mp4');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
      }
      ctrl = VideoPlayerController.file(file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await ctrl.initialize();
    }
    return ctrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(12)),
        child: const Center(
            child: Text('Could not load video',
                style: TextStyle(color: Colors.white70))),
      );
    }
    if (!_initialized || _controller == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(12)),
        child:
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final ctrl = _controller!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(
            aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl)),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: ctrl,
          builder: (_, value, __) => GestureDetector(
            onTap: () {
              if (value.isPlaying) {
                ctrl.pause();
              } else {
                final active = _activeVideoController;
                if (active != null && !identical(active, ctrl)) {
                  active.pause();
                }
                _activeVideoController = ctrl;
                ctrl.play();
              }
            },
            child: Container(
              color: Colors.transparent,
              child: value.isPlaying
                  ? const SizedBox.shrink()
                  : Container(
                      decoration: const BoxDecoration(
                          color: Colors.black45, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(12),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 40),
                    ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(
                _muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: _toggleMute,
            ),
          ),
        ),
      ]),
    );
  }
}
