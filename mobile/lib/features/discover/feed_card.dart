import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import '../../shared/widgets/report_sheet.dart';
import 'booking_sheet.dart';
import 'post_detail_screen.dart';
import 'provider_detail_screen.dart';
import 'user_profile_screen.dart';

class FeedCard extends StatefulWidget {
  const FeedCard(
      {super.key,
      required this.item,
      required this.api,
      required this.reload,
      this.readOnly = false});
  final FeedItem item;
  final MarketplaceApi api;
  final Future<void> Function() reload;
  final bool readOnly;

  static Future<void> stopAllMusic() => _FeedCardState._stopAllMusic();

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> {
  static _FeedCardState? _activeMusicCard;

  static Future<void> _stopAllMusic() async {
    await _activeMusicCard?._stopMusic();
  }

  late bool _liked;
  late int _likeCount;
  late bool _followingAuthor;
  var _followingInProgress = false;
  AudioPlayer? _musicPlayer;
  List<String>? _searchedMusicUrls;
  ScrollPosition? _scrollPosition;
  VoidCallback? _scrollListener;
  var _deleting = false;
  var _isSaved = false;
  var _musicPlaying = false;
  var _videoPlayingInPost = false;
  var _updatingMusic = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.item.isLiked;
    _likeCount = widget.item.likeCount;
    _followingAuthor = widget.item.isFollowingAuthor;
    LocalDb.instance.isFavorite(widget.item.id, widget.item.type).then((v) {
      if (mounted) setState(() => _isSaved = v);
    });
    // Pre-cache music and video for instant playback
    _preFetchMediaInBackground();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachScrollMonitor();
      _updateMusicPlayback();
    });
  }

  static int _activePrefetches = 0;
  static const int _maxPrefetches = 2;

  void _preFetchMediaInBackground() {
    if (_activePrefetches >= _maxPrefetches) return;
    _activePrefetches++;
    Future(() async {
      try {
        for (final url in _savedMusicUrls) {
          await _cacheFeedMusicFile(url, download: true);
        }
        final video = widget.item.socialPost?.video;
        if (video != null &&
            (video.startsWith('http://') || video.startsWith('https://'))) {
          await _preFetchFeedVideo(video);
        }
      } finally {
        _activePrefetches--;
      }
    });
  }

  static String _stableFeedKey(String url) {
    var hash = 5381;
    for (final unit in url.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x3fffffff;
    }
    return '${url.length}_$hash';
  }

  static Future<File?> _cacheFeedMusicFile(String url,
      {required bool download}) async {
    try {
      final dir =
          Directory('${(await getTemporaryDirectory()).path}/feed_music');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${_stableFeedKey(url)}.mp3');
      if (await file.exists() && await file.length() > 0) return file;
      if (!download || !SyncService.instance.isOnline) return null;
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _preFetchFeedVideo(String url) async {
    if (!SyncService.instance.isOnline) return;
    try {
      final dir =
          Directory('${(await getTemporaryDirectory()).path}/post_videos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final transformed = _toCloudinaryMp4(url);
      for (final u in [url, transformed]) {
        final file = File('${dir.path}/${_stableFeedKey(u)}.mp4');
        if (await file.exists() && await file.length() > 0) return;
      }
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(transformed));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) return;
        final file =
            File('${dir.path}/${_stableFeedKey(transformed)}.mp4');
        await response.pipe(file.openWrite());
      } finally {
        client.close(force: true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final listener = _scrollListener;
    final position = _scrollPosition;
    if (listener != null && position != null) {
      position.removeListener(listener);
    }
    if (identical(_activeMusicCard, this)) _activeMusicCard = null;
    _musicPlayer?.dispose();
    super.dispose();
  }

  List<String> get _savedMusicUrls {
    final post = widget.item.socialPost;
    final values = [
      post?.metadata['musicUrl'],
      post?.metadata['previewUrl'],
      post?.metadata['audioUrl'],
    ];
    return values
        .map((value) => value?.toString().trim() ?? '')
        .where((url) => url.startsWith('http'))
        .toSet()
        .toList();
  }

  String? get _musicTitle {
    final title = widget.item.socialPost?.metadata['music']?.toString().trim();
    return title == null || title.isEmpty ? null : title;
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
    _scrollListener = _updateMusicPlayback;
    position.addListener(_scrollListener!);
  }

  bool get _isMostlyVisible {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottom = topLeft.dy + renderObject.size.height;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visibleTop = topLeft.dy.clamp(0.0, screenHeight);
    final visibleBottom = bottom.clamp(0.0, screenHeight);
    return visibleBottom - visibleTop > renderObject.size.height * 0.45;
  }

  Future<void> _updateMusicPlayback() async {
    if (_updatingMusic) return;
    if (_savedMusicUrls.isEmpty && _musicTitle == null) return;
    _updatingMusic = true;
    try {
      if (_videoPlayingInPost || !_isMostlyVisible) {
        await _stopMusic();
        return;
      }
      await _playMusic();
    } finally {
      _updatingMusic = false;
    }
  }

  Future<void> _playMusic() async {
    if (_musicPlaying) return;
    if (_activeMusicCard != null && !identical(_activeMusicCard, this)) {
      await _activeMusicCard!._stopMusic();
    }
    final player = _musicPlayer ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    final savedPlayed = await _tryPlayMusicUrls(_savedMusicUrls);
    if (savedPlayed) return;

    final searchedPlayed = await _tryPlayMusicUrls(await _searchMusicUrls());
    if (!searchedPlayed) await _stopMusic();
  }

  Future<bool> _tryPlayMusicUrls(List<String> urls) async {
    final player = _musicPlayer;
    if (player == null) return false;
    for (final url in urls) {
      try {
        await player.stop();
        final cached = await _cacheFeedMusicFile(url, download: false);
        if (cached != null) {
          await player.play(DeviceFileSource(cached.path));
        } else {
          await player.play(UrlSource(url));
          // Cache in background for next time
          unawaited(_cacheFeedMusicFile(url, download: true));
        }
        _activeMusicCard = this;
        _musicPlaying = true;
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<List<String>> _searchMusicUrls() async {
    final cached = _searchedMusicUrls;
    if (cached != null) return cached;
    final title = _musicTitle;
    if (title == null) return const [];
    try {
      final tracks = await widget.api.searchMusic(title);
      _searchedMusicUrls = tracks
          .map((track) => track['previewUrl']?.toString().trim() ?? '')
          .where((url) => url.startsWith('http'))
          .toSet()
          .toList();
    } catch (_) {}
    return _searchedMusicUrls ?? const [];
  }

  Future<void> _stopMusic() async {
    if (!_musicPlaying) return;
    try {
      await _musicPlayer?.stop();
    } catch (_) {}
    _musicPlaying = false;
    if (identical(_activeMusicCard, this)) _activeMusicCard = null;
  }

  void _handlePostVideoPlay() {
    _videoPlayingInPost = true;
    _stopMusic();
  }

  Future<void> _toggleSave() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_isSaved) {
      await LocalDb.instance.removeFavorite(widget.item.id, widget.item.type);
      if (mounted) setState(() => _isSaved = false);
      messenger
          .showSnackBar(const SnackBar(content: Text('Removed from saved.')));
    } else {
      final item = widget.item;
      final data = <String, dynamic>{
        'id': item.id,
        'type': item.type,
        'createdAt': item.createdAt.toIso8601String(),
        if (item.listing != null) ...{
          'title': item.listing!.title,
          'subtitle': item.listing!.providerDisplayName,
          'category': item.listing!.category,
          'municipality': item.listing!.municipality,
        },
        if (item.job != null) ...{
          'title': item.job!.title,
          'subtitle': item.job!.clientFullName ?? '',
          'category': item.job!.category,
          'municipality': item.job!.municipality,
        },
        if (item.socialPost != null) ...{
          'title': item.socialPost!.body,
          'subtitle': item.socialPost!.fullName,
        },
        if (item.review != null) ...{
          'title': 'Review by ${item.review!.reviewerName ?? 'User'}',
          'subtitle': item.review!.comment ?? '',
        },
      };
      await LocalDb.instance.saveFavorite(item.id, item.type, data);
      if (mounted) setState(() => _isSaved = true);
      messenger.showSnackBar(const SnackBar(content: Text('Saved!')));
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
    try {
      final (liked, count) =
          await widget.api.toggleLike(widget.item.type, widget.item.id);
      if (mounted) {
        setState(() {
          _liked = liked;
          _likeCount = count;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('toggle_like', {
          'itemType': widget.item.type,
          'itemId': widget.item.id,
        });
      } else {
        // Revert optimistic update on non-network errors
        if (mounted) {
          setState(() {
            _liked = prevLiked;
            _likeCount = prevCount;
          });
        }
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _openDetail() {
    if (widget.readOnly) return;

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => PostDetailScreen(
          item: widget.item,
          api: widget.api,
          initialLiked: _liked,
          initialLikeCount: _likeCount,
          onLikeChanged: (liked, count) => setState(() {
            _liked = liked;
            _likeCount = count;
          }),
        ),
      ),
    );
  }

  void _openShareSheet() {
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ShareSheet(
        item: widget.item,
        api: widget.api,
        onShared: () {
          if (outerContext.mounted) {
            ScaffoldMessenger.of(outerContext).showSnackBar(const SnackBar(
                content: Text('Post shared!'), duration: Duration(seconds: 3)));
            widget.reload();
          }
        },
      ),
    );
  }

  bool get _canManageSocialPost {
    final post = widget.item.socialPost;
    if (post == null) return false;
    if (widget.readOnly) return false;
    final myId = widget.api.storedUser?.id;
    if (myId == null || myId.isEmpty) return false;
    return post.userId == myId;
  }

  bool get _canAdminManageSocialPost =>
      widget.item.socialPost != null && widget.api.storedUser?.role == 'admin';

  bool get _isAdminViewer => widget.api.storedUser?.role == 'admin';

  Future<void> _suspendUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend user?'),
        content: const Text(
            'This will suspend the post owner account from the platform.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.updateAdminUserStatus(userId, 'suspended');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User suspended.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  Future<void> _editSocialPost(SocialPost post) async {
    final bodyCtrl = TextEditingController(text: post.body);
    var privacy = post.privacy;
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                18, 18, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Edit post',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Update your post'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: privacy,
                decoration: const InputDecoration(labelText: 'Privacy'),
                items: const ['Public', 'Friends', 'Only me']
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setSheetState(() => privacy = value);
                },
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final body = bodyCtrl.text.trim();
                    if (!SyncService.instance.isOnline) {
                      await LocalDb.instance.queueAction('update_social_post', {
                        'postId': post.id,
                        'body': body,
                        'privacy': privacy,
                      });
                      if (ctx.mounted) Navigator.pop(ctx, true);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Row(children: [
                            Icon(Icons.sync, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Edit queued — will sync when online'),
                          ]),
                          backgroundColor: Colors.orange,
                        ));
                      }
                      return;
                    }
                    try {
                      await widget.api.updateSocialPost(post.id, body, privacy);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (!ctx.mounted) return;
                      if (SyncService.isNetworkError(e)) {
                        await LocalDb.instance
                            .queueAction('update_social_post', {
                          'postId': post.id,
                          'body': body,
                          'privacy': privacy,
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Row(children: [
                            Icon(Icons.sync, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Edit queued — will sync when online'),
                          ]),
                          backgroundColor: Colors.orange,
                        ));
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(friendlyError(e))));
                      }
                    }
                  },
                  child: const Text('Save changes'),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(bodyCtrl.dispose);
    if (updated == true) widget.reload();
  }

  void _showPostActions(SocialPost post) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Post actions',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: appMuted)),
              ),
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: appPrimary.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_outlined,
                    color: appPrimary, size: 20),
              ),
              title: const Text('Edit post',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Update text or privacy',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: appMuted),
              onTap: () {
                Navigator.pop(ctx);
                _editSocialPost(post);
              },
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
              ),
              title: const Text('Delete post',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.red)),
              subtitle: const Text('This cannot be undone',
                  style: TextStyle(fontSize: 12)),
              trailing:
                  const Icon(Icons.chevron_right, color: Colors.red, size: 20),
              onTap: _deleting
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _deleteSocialPost(post);
                    },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showOtherPostActions(SocialPost post) {
    const defaultDeleteReason =
        'Removed by admin for violating HanapGawa community guidelines.';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (!_isAdminViewer)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flag_outlined,
                      color: Colors.red, size: 20),
                ),
                title: const Text('Report post',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.red)),
                subtitle: const Text('Help us keep the community safe',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.red, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportSheet(context,
                      api: widget.api,
                      reportedUserId: post.userId,
                      contentType: 'social_post',
                      contentId: post.id,
                      contentLabel: 'this post');
                },
              ),
            if (_canAdminManageSocialPost)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                ),
                title: const Text('Delete post as admin',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.red)),
                subtitle: const Text(defaultDeleteReason,
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.red, size: 20),
                onTap: _deleting
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _deleteSocialPost(post,
                            adminReason: defaultDeleteReason);
                      },
              ),
            if (_canAdminManageSocialPost)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.pause_circle_outline,
                      color: Colors.orange.shade700, size: 20),
                ),
                title: Text('Suspend post owner',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade700)),
                subtitle: const Text('Restrict this user account',
                    style: TextStyle(fontSize: 12)),
                trailing: Icon(Icons.chevron_right,
                    color: Colors.orange.shade700, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _suspendUser(post.userId);
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteSocialPost(SocialPost post, {String? adminReason}) async {
    final isAdminDelete = adminReason != null &&
        widget.api.storedUser?.role == 'admin' &&
        post.userId != widget.api.storedUser?.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text(isAdminDelete
            ? 'This post will be permanently removed. Reason: $adminReason'
            : 'This post will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    if (!SyncService.instance.isOnline) {
      if (isAdminDelete) {
        if (mounted) {
          setState(() => _deleting = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Admin post deletion requires a connection.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }
      await LocalDb.instance
          .queueAction('delete_social_post', {'postId': post.id});
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Delete queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
        widget.reload();
      }
      return;
    }
    try {
      if (isAdminDelete) {
        await widget.api.deleteAdminPost(post.id, reason: adminReason);
      } else {
        await widget.api.deleteSocialPost(post.id);
      }
      await widget.reload();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('delete_social_post', {'postId': post.id});
        if (!mounted) return;
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Delete queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
        widget.reload();
      } else {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Color accentColor;
    Widget content;
    // Social posts manage their own internal taps (CRUD 3-dot must not be inside
    // an outer GestureDetector or it gets swallowed).
    bool selfManagesTaps;

    if (widget.item.listing != null) {
      accentColor = appPrimary;
      content = _buildListingContent(context);
      selfManagesTaps = false;
    } else if (widget.item.job != null) {
      accentColor = widget.item.job!.postType == 'offering_service'
          ? const Color(0xFF1E88E5)
          : appPrimary;
      content = _buildJobContent(context);
      selfManagesTaps = false;
    } else if (widget.item.socialPost != null) {
      accentColor = appPrimary;
      content = _buildSocialPostContent(context);
      selfManagesTaps = true;
    } else if (widget.item.review != null) {
      accentColor = Colors.orange;
      content = _buildReviewContent(context);
      selfManagesTaps = false;
    } else {
      return const SizedBox.shrink();
    }

    return AppCard(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          selfManagesTaps
              ? content
              : GestureDetector(
                  onTap: _openDetail,
                  child: content,
                ),
          if (!widget.readOnly) ...[
            const Divider(height: 1, thickness: 0.5),
            _buildActionBar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionBtn(
            icon: _liked ? Icons.favorite : Icons.favorite_border,
            iconColor: _liked ? Colors.red : null,
            count: _likeCount,
            onTap: widget.api.token.isNotEmpty
                ? _toggleLike
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log in to like posts.'))),
          ),
        ),
        Expanded(
          child: _ActionBtn(
            icon: Icons.comment_outlined,
            count: widget.item.commentCount,
            onTap: _openDetail,
          ),
        ),
        Expanded(
          child: _ActionBtn(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: _openShareSheet,
          ),
        ),
        Expanded(
          child: _ActionBtn(
            icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
            label: _isSaved ? 'Saved' : 'Save',
            onTap: _toggleSave,
          ),
        ),
      ],
    );
  }

  // ── Listing card ───────────────────────────────────────────────────────────

  Widget _buildListingContent(BuildContext context) {
    final listing = widget.item.listing!;
    final badge = listing.providerRole == 'agency' ? 'Agency' : 'Worker';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _isAdminViewer
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => ProviderDetailScreen(
                            api: widget.api,
                            providerUserId: listing.providerUserId),
                      ),
                    ),
            child: FeedHeader(
              name: listing.providerDisplayName ?? 'Worker',
              subtitle:
                  '${listing.municipality} · ${timeAgo(widget.item.createdAt)}',
              badge: badge,
              color: appPrimary,
            ),
          ),
        ),
        const _TypeBadge(
            label: 'Service', color: appPrimary, icon: Icons.work_outline),
        if (!widget.readOnly &&
            widget.api.token.isNotEmpty &&
            listing.providerUserId != (widget.api.storedUser?.id ?? ''))
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showReportSheet(context,
                  api: widget.api,
                  reportedUserId: listing.providerUserId,
                  contentLabel: 'this listing'),
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.flag_outlined, size: 16, color: appMuted),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      Text(listing.title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(listing.category,
          style: const TextStyle(color: appMuted, fontSize: 13)),
      if (listing.description.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(listing.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: appMuted)),
      ],
      const SizedBox(height: 12),
      const Divider(height: 1, thickness: 0.5),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child:
                _StatItem(icon: Icons.work_outline, label: listing.category)),
        Expanded(
            child: _StatItem(
                icon: Icons.payments_outlined,
                label: 'P${listing.priceMin}–P${listing.priceMax}')),
        Expanded(
            child: _StatItem(
                icon: Icons.star_outline,
                label: '${listing.requirements.length} req.')),
      ]),
      if (!widget.readOnly) ...[
        const SizedBox(height: 12),
        _buildListingActions(context, listing),
      ],
    ]);
  }

  Widget _buildListingActions(BuildContext context, ServiceListing listing) {
    final myId = widget.api.storedUser?.id ?? '';
    final isOwn = listing.providerUserId == myId;
    if (isOwn) {
      return _GradientActionButton(
        label: 'Your Listing',
        icon: Icons.work_outline,
        onTap: _openDetail,
      );
    }
    return Row(children: [
      Expanded(
        child: _GradientActionButton(
          label: 'Message',
          icon: Icons.chat_bubble_outline,
          onTap: _openDetail,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _GradientActionButton(
          label: listing.allowDirectBooking ? 'Book Now' : 'Hire Now',
          icon: listing.allowDirectBooking
              ? Icons.bolt
              : Icons.handshake_outlined,
          onTap: listing.allowDirectBooking
              ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BookingSheet(
                        api: widget.api,
                        target: BookingTarget.fromListing(listing)),
                  )
              : _openDetail,
        ),
      ),
    ]);
  }

  // ── Job card ───────────────────────────────────────────────────────────────

  Widget _buildJobContent(BuildContext context) {
    final job = widget.item.job!;
    final badge = job.postType == 'offering_service'
        ? 'Looking For Client'
        : 'Looking For Worker';
    final badgeColor = job.postType == 'offering_service'
        ? const Color(0xFF1E88E5)
        : appPrimary;
    final slotLabel =
        job.postType == 'offering_service' ? 'clients' : 'workers';
    final priceLabel = (job.budgetMin ?? 0) > 0
        ? 'P${job.budgetMin}–P${job.budgetMax ?? job.budgetMin}'
        : 'Price not set';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: FeedHeader(
            name: job.clientFullName ?? 'Client',
            subtitle: '${job.municipality} · ${timeAgo(widget.item.createdAt)}',
            badge: badge,
            color: badgeColor,
          ),
        ),
        _TypeBadge(
            label: 'Job', color: badgeColor, icon: Icons.assignment_outlined),
        if (!widget.readOnly &&
            widget.api.token.isNotEmpty &&
            job.clientUserId != (widget.api.storedUser?.id ?? ''))
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showReportSheet(context,
                  api: widget.api,
                  reportedUserId: job.clientUserId,
                  contentLabel: 'this job post'),
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.flag_outlined, size: 16, color: appMuted),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      Text(job.title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(job.category, style: const TextStyle(color: appMuted, fontSize: 13)),
      if (job.description.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(job.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: appMuted)),
      ],
      const SizedBox(height: 12),
      const Divider(height: 1, thickness: 0.5),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child:
                _StatItem(icon: Icons.grid_view_outlined, label: job.category)),
        Expanded(
            child: _StatItem(icon: Icons.payments_outlined, label: priceLabel)),
        Expanded(
            child: _StatItem(
                icon: job.postType == 'offering_service'
                    ? Icons.person_add_alt_outlined
                    : Icons.groups_outlined,
                label:
                    '${job.acceptedOfferCount}/${job.workersNeeded} $slotLabel')),
        Expanded(
            child: _StatItem(
                icon: Icons.mail_outline, label: '${job.offerCount} offers')),
      ]),
      if (!widget.readOnly) ...[
        const SizedBox(height: 12),
        _buildJobActions(context, job),
      ],
    ]);
  }

  Widget _buildJobActions(BuildContext context, JobPost job) {
    final myId = widget.api.storedUser?.id ?? '';
    final isOwn = job.clientUserId == myId;

    if (isOwn) {
      return _GradientActionButton(
        label: 'Your Post',
        icon: Icons.assignment_outlined,
        onTap: _openDetail,
      );
    }

    final isOfferingService = job.postType == 'offering_service';

    return Row(children: [
      Expanded(
        child: _GradientActionButton(
          label: 'Message',
          icon: Icons.chat_bubble_outline,
          onTap: _openDetail,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _GradientActionButton(
          label: isOfferingService && job.allowDirectBooking
              ? 'Book Now'
              : isOfferingService
                  ? 'Inquire'
                  : 'Apply',
          icon: isOfferingService && job.allowDirectBooking
              ? Icons.bolt
              : isOfferingService
                  ? Icons.chat_bubble_outline
                  : Icons.send_outlined,
          onTap: isOfferingService && job.allowDirectBooking
              ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BookingSheet(
                        api: widget.api,
                        target: BookingTarget.fromJobPost(job)),
                  )
              : _openDetail,
        ),
      ),
    ]);
  }

  // ── Social post card ───────────────────────────────────────────────────────

  Widget _buildSocialPostContent(BuildContext context) {
    final post = widget.item.socialPost!;
    final parts = post.fullName.trim().split(' ');
    final initials = post.fullName.isEmpty
        ? '?'
        : (parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : post.fullName[0].toUpperCase());

    void openAuthor() => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(
              api: widget.api,
              userId: post.userId,
              displayName: post.fullName,
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Author header — each zone has its own tap, no outer wrapper ──
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Avatar → author profile
        GestureDetector(
          onTap: openAuthor,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [appPrimary, appSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: Container(
                color: Colors.white,
                child: post.profilePic != null
                    ? _buildProfilePic(post.profilePic!, initials)
                    : Center(
                        child: Text(initials,
                            style: const TextStyle(
                                color: appPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 15))),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Name + meta → post detail
        Expanded(
          child: GestureDetector(
            onTap: _openDetail,
            behavior: HitTestBehavior.translucent,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14.5)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: appPrimary.withAlpha(15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        post.privacy == 'Public'
                            ? Icons.public
                            : Icons.lock_outline,
                        size: 10,
                        color: appPrimary),
                    const SizedBox(width: 3),
                    Text(post.privacy,
                        style: const TextStyle(
                            color: appPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(width: 6),
                Text(timeAgo(widget.item.createdAt),
                    style: const TextStyle(color: appMuted, fontSize: 11)),
              ]),
            ]),
          ),
        ),
        // Follow button — shown when not following the author
        if (!_followingAuthor &&
            !widget.readOnly &&
            widget.api.token.isNotEmpty &&
            widget.api.storedUser?.id != post.userId)
          _followingInProgress
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () async {
                    setState(() => _followingInProgress = true);
                    try {
                      await widget.api.followUser(post.userId);
                      if (mounted) setState(() => _followingAuthor = true);
                    } finally {
                      if (mounted) setState(() => _followingInProgress = false);
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: appPrimary,
                  ),
                  child: const Text('Follow',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
        // CRUD / chevron — standalone, never inside a parent GestureDetector
        if (_canAdminManageSocialPost)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showOtherPostActions(post),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: appSurface,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.more_horiz, color: appMuted, size: 18),
                ),
              ),
            ),
          )
        else if (_canManageSocialPost)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showPostActions(post),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: appSurface,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.more_horiz, color: appMuted, size: 18),
                ),
              ),
            ),
          )
        else if (!widget.readOnly && widget.api.token.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showOtherPostActions(post),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: appSurface,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.more_horiz, color: appMuted, size: 18),
                ),
              ),
            ),
          )
        else if (!widget.readOnly)
          GestureDetector(
            onTap: _openDetail,
            child: const Icon(Icons.chevron_right, color: appMuted, size: 20),
          ),
      ]),
      // ── Body / media — tappable to open detail ──────────────────────────
      GestureDetector(
        onTap: _openDetail,
        behavior: HitTestBehavior.translucent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (post.metadata.isNotEmpty) ...[
            const SizedBox(height: 6),
            PostMetadata(metadata: post.metadata),
          ],
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: post.metadata['backgroundColor'] is int
                    ? Color(post.metadata['backgroundColor'] as int)
                    : appSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: post.metadata['backgroundColor'] is int
                              ? Colors.white
                              : null)),
                  if (post.body.length > 200 || post.body.contains('\n\n\n'))
                    GestureDetector(
                      onTap: _openDetail,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('See more',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: post.metadata['backgroundColor'] is int
                                    ? Colors.white70
                                    : appPrimary)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // Multiple media items (new posts)
          if (_postMediaItems(post).isNotEmpty) ...[
            const SizedBox(height: 10),
            _PostMediaGrid(
                items: _postMediaItems(post),
                onVideoPlay: _handlePostVideoPlay),
          ] else ...[
            // Legacy single image / video
            if (post.image != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: post.image!.startsWith('http')
                      ? Image.network(post.image!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink())
                      : Image.memory(base64Decode(post.image!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                ),
              ),
            ],
            if (post.video != null) ...[
              const SizedBox(height: 10),
              _InlineVideoPlayer(
                  base64Video: post.video!, onPlay: _handlePostVideoPlay),
            ],
          ],
          if (post.sharedSnapshot != null) ...[
            const SizedBox(height: 10),
            SharedPostPreview(snapshot: post.sharedSnapshot!),
          ],
          const SizedBox(height: 4),
        ]),
      ),
    ]);
  }

  // ── Review card ────────────────────────────────────────────────────────────

  Widget _buildReviewContent(BuildContext context) {
    final review = widget.item.review;
    if (review == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: FeedHeader(
            name: review.providerName ?? 'Worker',
            subtitle: timeAgo(widget.item.createdAt),
            badge: '${review.rating} ★',
            color: Colors.orange,
          ),
        ),
        const _TypeBadge(
            label: 'Review', color: Colors.orange, icon: Icons.star_outline),
      ]),
      const SizedBox(height: 12),
      Row(
          children: List.generate(
              5,
              (i) => Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    color: Colors.orange,
                    size: 20,
                  ))),
      const SizedBox(height: 8),
      Text(review.comment?.isEmpty ?? true
          ? 'No comment provided.'
          : '"${review.comment}"'),
      const SizedBox(height: 8),
      Text('Reviewed by: ${review.reviewerName ?? 'User'}',
          style: const TextStyle(color: appMuted, fontSize: 12)),
      const SizedBox(height: 4),
    ]);
  }
}

class PostMetadata extends StatelessWidget {
  const PostMetadata({super.key, required this.metadata});
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final entries = <({IconData icon, String label})>[
      if (metadata['tags'] is List && (metadata['tags'] as List).isNotEmpty)
        (
          icon: Icons.person_add_alt,
          label: 'With ${(metadata['tags'] as List).join(', ')}'
        ),
      if (metadata['feeling'] != null)
        (
          icon: Icons.emoji_emotions_outlined,
          label: metadata['feeling'].toString()
        ),
      if (metadata['location'] != null)
        (icon: Icons.place_outlined, label: '${metadata['location']}'),
      if (metadata['music'] != null)
        (icon: Icons.music_note_outlined, label: '${metadata['music']}'),
    ];

    final sticker = metadata['sticker']?.toString();
    final hasSticker = sticker != null && sticker.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text tags always first (notes and details above)
        if (entries.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: entries
                .map((e) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(e.icon, size: 13, color: appPrimary),
                        const SizedBox(width: 3),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            e.label,
                            style: const TextStyle(
                                fontSize: 12,
                                color: appMuted,
                                overflow: TextOverflow.ellipsis),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
        ],
        if (hasSticker && sticker.startsWith('http')) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              sticker,
              height: 80,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

// ── Shared-post preview card ─────────────────────────────────────────────────

class SharedPostPreview extends StatelessWidget {
  const SharedPostPreview({super.key, required this.snapshot});
  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final type = snapshot['type'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
      ),
      padding: const EdgeInsets.all(12),
      child: _buildContent(context, type),
    );
  }

  Widget _buildContent(BuildContext context, String type) {
    if (type == 'post') {
      final body = snapshot['body']?.toString() ?? '';
      final image = snapshot['image']?.toString();
      final video = snapshot['video']?.toString();
      final metadata = snapshot['metadata'] is Map
          ? Map<String, dynamic>.from(snapshot['metadata'] as Map)
          : <String, dynamic>{};
      final gif = snapshot['gif']?.toString();
      final mediaItems = _mediaItemsWithGif(
          rawItems: snapshot['mediaItems'],
          metadata: metadata,
          fallbackImage: image,
          fallbackVideo: video,
          fallbackGif: gif);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(snapshot['authorName']?.toString() ?? 'User',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ],
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 6),
          PostMetadata(metadata: metadata),
        ],
        if (mediaItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          _PostMediaGrid(items: mediaItems, onVideoPlay: () {}),
        ] else if (image != null && image.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _sharedImage(
              image,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ] else if (video != null && video.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _InlineVideoPlayer(base64Video: video),
            ),
          ),
        ],
      ]);
    }

    // listing / job
    if (type == 'listing' || type == 'job') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: type == 'listing' ? appPrimary : const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                (snapshot['authorName']?.toString() ?? '?')
                    .substring(0, 2)
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(snapshot['authorName']?.toString() ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              Text(
                  '${snapshot['municipality'] ?? ''} · ${snapshot['badge'] ?? ''}',
                  style: const TextStyle(color: appMuted, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(snapshot['title']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 2),
        Text(snapshot['category']?.toString() ?? '',
            style: const TextStyle(color: appMuted, fontSize: 12)),
        if ((snapshot['price']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(snapshot['price'].toString(),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ]);
    }

    // review
    if (type == 'review') {
      final rating = (snapshot['rating'] as num?)?.toInt() ?? 0;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(snapshot['authorName']?.toString() ?? 'Worker',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          children: List.generate(
              5,
              (i) => Icon(i < rating ? Icons.star : Icons.star_border,
                  color: Colors.orange, size: 16)),
        ),
        if ((snapshot['comment']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('"${snapshot['comment']}"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ],
      ]);
    }

    return const SizedBox.shrink();
  }
}

List<Map<String, dynamic>> _postMediaItems(SocialPost post) =>
    _mediaItemsWithGif(
        rawItems: post.metadata['mediaItems'],
        metadata: post.metadata,
        fallbackImage: post.image,
        fallbackVideo: post.video);

List<Map<String, dynamic>> _mediaItemsWithGif({
  required dynamic rawItems,
  required Map<String, dynamic> metadata,
  String? fallbackImage,
  String? fallbackVideo,
  String? fallbackGif,
}) {
  final items = rawItems is List
      ? List<Map<String, dynamic>>.from(rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)))
      : <Map<String, dynamic>>[];
  if (items.isEmpty) {
    if (fallbackImage?.isNotEmpty == true) {
      items.add({'type': 'image', 'url': fallbackImage!});
    }
    if (fallbackVideo?.isNotEmpty == true) {
      items.add({'type': 'video', 'url': fallbackVideo!});
    }
  }
  final gif = (metadata['gif'] ?? fallbackGif)?.toString().trim();
  if (gif != null && gif.startsWith('http')) {
    final alreadyIncluded = items.any((item) => item['url']?.toString() == gif);
    if (!alreadyIncluded) items.add({'type': 'gif', 'url': gif});
  }
  return items;
}

Widget _sharedImage(String source,
    {double? height, double? width, BoxFit fit = BoxFit.cover}) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Image.network(
      source,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  try {
    return Image.memory(
      base64Decode(source),
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  } catch (_) {
    return const SizedBox.shrink();
  }
}

// ── Share sheet ───────────────────────────────────────────────────────────────

class ShareSheet extends StatefulWidget {
  const ShareSheet(
      {super.key,
      required this.item,
      required this.api,
      required this.onShared});
  final FeedItem item;
  final MarketplaceApi api;
  final VoidCallback onShared;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final _captionCtrl = TextEditingController();
  var _posting = false;
  String? _error;

  Map<String, dynamic> get _snapshot {
    final item = widget.item;
    if (item.listing != null) {
      final l = item.listing!;
      return {
        'type': 'listing',
        'title': l.title,
        'authorName': l.providerDisplayName ?? 'Worker',
        'badge': l.providerRole == 'agency' ? 'Agency' : 'Worker',
        'municipality': l.municipality,
        'price': 'P${l.priceMin}–P${l.priceMax}',
        'category': l.category,
        'description': l.description,
      };
    }
    if (item.job != null) {
      final j = item.job!;
      return {
        'type': 'job',
        'title': j.title,
        'authorName': j.clientFullName ?? 'Client',
        'badge': j.postType == 'offering_service'
            ? 'Looking For Client'
            : 'Looking For Worker',
        'municipality': j.municipality,
        'price': 'P${j.budgetMin ?? 0}–P${j.budgetMax ?? 0}',
        'category': j.category,
        'description': j.description,
      };
    }
    if (item.socialPost != null) {
      final p = item.socialPost!;
      final mediaItems = p.metadata['mediaItems'];
      final gif = p.metadata['gif']?.toString();
      return {
        'type': 'post',
        'body': p.body,
        'authorName': p.fullName,
        'metadata': p.metadata,
        if (p.image != null) 'image': p.image,
        if (p.video != null) 'video': p.video,
        if (mediaItems is List) 'mediaItems': mediaItems,
        if (gif != null && gif.isNotEmpty) 'gif': gif,
      };
    }
    if (item.review != null) {
      final r = item.review!;
      return {
        'type': 'review',
        'rating': r.rating,
        'comment': r.comment ?? '',
        'authorName': r.providerName ?? 'Worker',
      };
    }
    return {};
  }

  Future<void> _share() async {
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await widget.api.createSocialPost(
        _captionCtrl.text.trim(),
        sharedFromType: widget.item.type,
        sharedFromId: widget.item.id,
        sharedSnapshot: _snapshot,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onShared();
      }
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('create_social_post', {
          'body': _captionCtrl.text.trim(),
          'sharedFromType': widget.item.type,
          'sharedFromId': widget.item.id,
          'sharedSnapshot': _snapshot,
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              Icon(Icons.sync, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Share queued — will post when online')),
            ]),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ));
        }
      } else {
        setState(() {
          _posting = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.api.storedUser;
    final initials = user?.initials ?? '?';
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height -
        bottomInset -
        MediaQuery.paddingOf(context).top -
        12;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('Share Post',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  _posting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : FilledButton(
                          onPressed: _share,
                          style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              minimumSize: Size.zero),
                          child: const Text('Share'),
                        ),
                ]),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: appPrimary,
                        child: Text(initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _captionCtrl,
                          maxLines: 2,
                          minLines: 1,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: "Say something about this...",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: appPrimary.withAlpha(100), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: appPrimary, width: 1.3),
                            ),
                          ),
                        ),
                      ),
                    ]),
              ),
              if (_error != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13))),
                  ]),
                ),
              const Divider(height: 16),
              // Preview of the post being shared
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SharedPostPreview(snapshot: _snapshot),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// ── Type badge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(
      {required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(70), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2)),
        ]),
      );
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: appMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: const TextStyle(color: appMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [appPrimary, appSecondary]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: appPrimary.withAlpha(36),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.count,
    this.label,
  });
  final IconData icon;
  final Color? iconColor;
  final int? count;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: iconColor ?? appMuted),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('$count',
                style: const TextStyle(color: appMuted, fontSize: 13)),
          ],
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(label!, style: const TextStyle(color: appMuted, fontSize: 13)),
          ],
        ]),
      );
}

// ─── Multi-media grid (feed display) ──────────────────────────────────────────

class _PostMediaGrid extends StatelessWidget {
  const _PostMediaGrid({required this.items, required this.onVideoPlay});
  final List<Map<String, dynamic>> items;
  final VoidCallback onVideoPlay;

  Widget _cell(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? 'image';
    final url = item['url']?.toString() ?? '';
    if (type == 'video') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _InlineVideoPlayer(base64Video: url, onPlay: onVideoPlay),
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
        constraints: const BoxConstraints(maxHeight: 320),
        child: _cell(items[0]),
      );
    }

    final width = MediaQuery.sizeOf(context).width - 72;
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: width.clamp(240.0, 420.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: _cell(items[index])),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${index + 1}/$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
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

/// Ensures the Cloudinary URL uses MP4/H.264 for Android/iOS fallback playback.
String _toCloudinaryMp4(String url) {
  if (!url.contains('res.cloudinary.com')) return url;
  if (url.contains('/upload/f_mp4,vc_h264') ||
      url.contains('/upload/vc_h264,f_mp4')) {
    return url;
  }
  return url.replaceFirst('/upload/', '/upload/f_mp4,vc_h264/');
}

Widget _buildProfilePic(String pic, String initials) {
  final fallback = Center(
    child: Text(initials,
        style: const TextStyle(
            color: appPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
  );
  if (pic.startsWith('http://') || pic.startsWith('https://')) {
    return Image.network(pic,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
  }
  try {
    return Image.memory(base64Decode(pic),
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
  } catch (_) {
    return fallback;
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({required this.base64Video, this.onPlay});
  final String base64Video;
  final VoidCallback? onPlay;

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
  bool _loading = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    final cached = VideoControllerCache.peek(widget.base64Video);
    if (cached?.isReady == true) {
      _controller = cached!.controller;
      _initialized = true;
      cached.touch();
      _attachPlaybackMonitor(cached.controller);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    if (_loading || _initialized) return;
    if (mounted) setState(() => _loading = true);
    try {
      final v = widget.base64Video;
      final ctrl = await _controllerFor(v);
      if (identical(_controller, ctrl) && _initialized) return;
      if (mounted) {
        _attachPlaybackMonitor(ctrl);
        setState(() {
          _controller = ctrl;
          _initialized = true;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[VideoPlayer] init error: $e');
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _play() async {
    if (!_initialized || _controller == null) {
      await _init();
    }
    final ctrl = _controller;
    if (!mounted || ctrl == null) return;
    final active = _activeVideoController;
    if (active != null && !identical(active, ctrl)) {
      active.pause();
    }
    _activeVideoController = ctrl;
    widget.onPlay?.call();
    await ctrl.play();
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
      final cachedFile = await _cachedPostVideoFile(source, download: false) ??
          await _cachedPostVideoFile(transformed, download: false);
      if (cachedFile != null) {
        ctrl = VideoPlayerController.file(
          cachedFile,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        await ctrl.initialize();
        return ctrl;
      }
      if (!SyncService.instance.isOnline) {
        throw Exception('Video is not cached for offline playback.');
      }
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(source),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await ctrl.initialize();
      } catch (_) {
        // Original URL failed; retry with a Cloudinary mobile-friendly transform.
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
      unawaited(_cachedPostVideoFile(transformed, download: true));
    } else {
      final payload = source.contains(',') ? source.split(',').last : source;
      final bytes = base64Decode(payload);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/post_video_${source.hashCode}.mp4');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
      }
      ctrl = VideoPlayerController.file(file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await ctrl.initialize();
    }
    return ctrl;
  }

  Future<File?> _cachedPostVideoFile(String url,
      {required bool download}) async {
    try {
      final dir =
          Directory('${(await getTemporaryDirectory()).path}/post_videos');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${_stablePostVideoKey(url)}.mp4');
      if (await file.exists() && await file.length() > 0) return file;
      if (!download || !SyncService.instance.isOnline) return null;

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        await response.pipe(file.openWrite());
        return await file.length() > 0 ? file : null;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  String _stablePostVideoKey(String url) {
    var hash = 5381;
    for (final unit in url.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x3fffffff;
    }
    return '${url.length}_$hash';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Could not load video',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    if (!_initialized || _controller == null) {
      return GestureDetector(
        onTap: _play,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : Container(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 40),
                  ),
          ),
        ),
      );
    }
    final ctrl = _controller!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: ctrl,
            builder: (_, value, __) => GestureDetector(
              onTap: () {
                if (value.isPlaying) {
                  ctrl.pause();
                } else {
                  _play();
                }
              },
              child: Container(
                color: Colors.transparent,
                child: value.isPlaying
                    ? const SizedBox.shrink()
                    : Container(
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
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
        ],
      ),
    );
  }
}
