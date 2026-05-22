import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/info_line.dart';
import '../../shared/widgets/report_sheet.dart';
import '../dashboard/stats_row.dart';
import '../discover/feed_card.dart';
import '../discover/provider_detail_screen.dart';
import '../jobs/jobs_screen.dart';
import '../../shared/widgets/info_pill.dart';
import '../../shared/widgets/skeleton.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    this.openDashboard,
    this.onLogout,
    this.viewingUserId,
    this.preloadedName,
    this.refreshKey = 0,
  });
  final MarketplaceApi api;
  final VoidCallback? openDashboard;
  final Future<void> Function()? onLogout;
  final String? viewingUserId;
  final String? preloadedName;
  final int refreshKey;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper();

  @override
  Path getClip(Size size) {
    final shortest = size.shortestSide;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: shortest,
      height: shortest,
    );
    return Path()..addOval(rect);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfileData? _profileData;
  var _posts = <SocialPost>[];
  var _photos = <ProfilePhoto>[];
  var _myJobPosts = <JobPost>[];
  var _reviews = <ReviewItem>[];
  var _bookingCount = 0;
  var _loading = false;
  var _refreshing = false;
  var _uploadingPic = false;
  var _uploadingCover = false;
  var _uploadingPhoto = false;

  // Visitor-mode state
  UserProfile? _visitedUserProfile;
  var _isFollowing = false;
  var _followerCount = 0;
  var _followLoading = false;
  var _loggingOut = false;

  bool get _isOwnProfile => widget.viewingUserId == null;

  Future<void> _handleLogout() async {
    if (_loggingOut || widget.onLogout == null) return;
    setState(() => _loggingOut = true);
    try {
      await widget.onLogout!();
    } catch (e) {
      if (mounted) {
        setState(() => _loggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  bool get _isAdmin => _isOwnProfile && widget.api.storedUser?.role == 'admin';
  bool get _isViewingAsAdmin => widget.api.storedUser?.role == 'admin';

  String get _displayName {
    if (_isOwnProfile) return widget.api.storedUser?.fullName ?? 'No name set';
    return _visitedUserProfile?.fullName ?? widget.preloadedName ?? '';
  }

  String get _displayInitials {
    if (_isOwnProfile) return widget.api.storedUser?.initials ?? '?';
    final name = _visitedUserProfile?.fullName ?? widget.preloadedName ?? '';
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_isAdmin) return;

    // 1. Load own profile from cache immediately
    if (_isOwnProfile && _profileData == null) {
      final myId = widget.api.storedUser?.id ?? '';
      final cached = await LocalDb.instance.getCachedOwnProfile(myId);
      if (cached != null && mounted) {
        try {
          setState(() {
            _profileData = UserProfileData.fromJson(
                cached['profileData'] as Map<String, dynamic>? ?? {});
            _bookingCount = cached['bookingCount'] as int? ?? 0;
            _posts = (cached['posts'] as List? ?? [])
                .map((e) => SocialPost.fromJson(e as Map<String, dynamic>))
                .toList();
            _photos = (cached['photos'] as List? ?? [])
                .map((e) => ProfilePhoto.fromJson(e as Map<String, dynamic>))
                .toList();
            _myJobPosts = (cached['jobPosts'] as List? ?? [])
                .map((e) => JobPost.fromJson(e as Map<String, dynamic>))
                .toList();
            _reviews = (cached['reviews'] as List? ?? [])
                .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        } catch (_) {
          if (mounted) setState(() => _loading = true);
        }
      } else if (mounted) {
        setState(() => _loading = true);
      }
    } else if (!_isOwnProfile && _visitedUserProfile == null) {
      if (mounted) setState(() => _loading = true);
    }
    if (mounted) setState(() => _refreshing = true);

    // 2. Fetch fresh from network
    try {
      if (_isOwnProfile) {
        final myId = widget.api.storedUser?.id ?? '';
        final results = await Future.wait([
          widget.api.getUserProfileData(),
          widget.api.getMyBookings(),
          widget.api.getMyPosts(),
          widget.api.getMyPhotos(),
          widget.api.getJobs(),
          if (myId.isNotEmpty)
            widget.api.getUserReviews(myId)
          else
            Future.value(<ReviewItem>[]),
        ]);
        if (mounted) {
          final allJobs = results[4] as List<JobPost>;
          final profileData = results[0] as UserProfileData;
          final bookings = results[1] as List<Booking>;
          final posts = results[2] as List<SocialPost>;
          final photos = results[3] as List<ProfilePhoto>;
          final jobPosts = allJobs.where((j) => j.clientUserId == myId).toList();
          final reviews = results[5] as List<ReviewItem>;
          setState(() {
            _profileData = profileData;
            _bookingCount = bookings.length;
            _posts = posts;
            _photos = photos;
            _myJobPosts = jobPosts;
            _reviews = reviews;
            _loading = false;
            _refreshing = false;
          });
          // Cache for next offline load — strip large base64 image blobs to
          // avoid SQLite CursorWindow overflow (~2 MB limit).
          final profileJson = profileData.toJson()
            ..remove('profilePic')
            ..remove('coverPic');
          unawaited(LocalDb.instance.cacheOwnProfile(myId, {
            'profileData': profileJson,
            'bookingCount': bookings.length,
            'posts': posts.map((p) {
              final m = p.toJson();
              m.remove('profilePic'); // base64 — shown fresh from network
              m.remove('image');      // Cloudinary URL is fine but skip to be safe with large payloads
              return m;
            }).toList(),
            'photos': photos.map((p) => {
              'id': p.id,
              'caption': p.caption,
              'createdAt': p.createdAt.toIso8601String(),
            }).toList(),
            'jobPosts': jobPosts.map((j) => j.toJson()).toList(),
            'reviews': reviews.map((r) => r.toJson()).toList(),
          }));
        }
      } else {
        final results = await Future.wait([
          widget.api.getUserProfile(widget.viewingUserId!),
          widget.api.getUserProfileDataPublic(widget.viewingUserId!),
          widget.api.getUserSocialPosts(widget.viewingUserId!),
          widget.api.getUserPhotosPublic(widget.viewingUserId!),
          widget.api.getUserReviews(widget.viewingUserId!),
        ]);
        bool isFollowing = false;
        if (widget.api.token.isNotEmpty && !_isViewingAsAdmin) {
          isFollowing = await widget.api.checkIsFollowing(widget.viewingUserId!);
        }
        if (mounted) {
          final vp = results[0] as UserProfile;
          setState(() {
            _visitedUserProfile = vp;
            _followerCount = vp.followerCount;
            _profileData = results[1] as UserProfileData?;
            _posts = results[2] as List<SocialPost>;
            _photos = results[3] as List<ProfilePhoto>;
            _reviews = results[4] as List<ReviewItem>;
            _isFollowing = isFollowing;
            _loading = false;
            _refreshing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  Future<void> _deleteJobPost(JobPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job post?'),
        content: const Text('This job post will be permanently removed.'),
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
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance
          .queueAction('delete_job_post', {'jobPostId': post.id});
      if (!mounted) return;
      setState(() => _myJobPosts.removeWhere((j) => j.id == post.id));
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
      await widget.api.deleteJobPost(post.id);
      if (!mounted) return;
      setState(() => _myJobPosts.removeWhere((j) => j.id == post.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Job post deleted.')));
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('delete_job_post', {'jobPostId': post.id});
        if (!mounted) return;
        setState(() => _myJobPosts.removeWhere((j) => j.id == post.id));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700));
    }
  }

  void _openJobPostDetail(BuildContext context, JobPost post) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          api: widget.api,
          job: post,
          onRefresh: _load,
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (widget.api.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to follow users.')));
      return;
    }
    setState(() => _followLoading = true);
    try {
      final count = _isFollowing
          ? await widget.api.unfollowUser(widget.viewingUserId!)
          : await widget.api.followUser(widget.viewingUserId!);
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          _followerCount = count;
          _followLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _followLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _showFollowList({required bool followers}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FollowListSheet(
        api: widget.api,
        title: followers ? 'Followers' : 'Following',
        fetch: followers ? widget.api.getMyFollowers : widget.api.getMyFollowing,
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Uploading photo...'),
        ]),
        duration: Duration(minutes: 1),
      ),
    );
    try {
      final bytes = await file.readAsBytes();
      final photo = await widget.api.uploadPhoto(base64Encode(bytes));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _photos = [photo, ..._photos]);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo added!'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5)));
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Future<void> _deletePhoto(ProfilePhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This photo will be permanently removed.'),
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
    try {
      await widget.api.deletePhoto(photo.id);
      if (mounted) {
        setState(() => _photos.removeWhere((p) => p.id == photo.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo deleted.'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5)));
      }
    }
  }

  void _viewFullImage(String? base64Image, String title) {
    if (base64Image == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title, style: const TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(
                base64Decode(base64Image),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _arrangePickedImage(
    Uint8List bytes, {
    required String title,
    required double aspectRatio,
    bool circle = false,
  }) async {
    final boundaryKey = GlobalKey();
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            circle
                ? 'Pinch to zoom and drag to arrange your profile photo.'
                : 'Pinch to zoom and drag to arrange your cover photo.',
            style: const TextStyle(color: appMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: boundaryKey,
            child: ClipPath(
              clipper: circle ? const _CircleClipper() : null,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ColoredBox(
                  color: Colors.black12,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final boundary = boundaryKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
              if (boundary == null) return;
              final image = await boundary.toImage(pixelRatio: 3);
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (ctx.mounted && data != null) {
                Navigator.pop(ctx, data.buffer.asUint8List());
              }
            },
            child: const Text('Use photo'),
          ),
        ],
      ),
    );
  }

  void _showProfilePicOptions() {
    final profilePic = _profileData?.profilePic;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Profile Photo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (profilePic != null)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View photo'),
              onTap: () {
                Navigator.pop(ctx);
                _viewFullImage(profilePic, 'Profile Photo');
              },
            ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Change photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickProfilePic();
            },
          ),
          if (profilePic != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete photo',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteProfilePic();
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showCoverPhotoOptions() {
    final coverPic = _profileData?.coverPic;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Cover Photo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (coverPic != null)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View photo'),
              onTap: () {
                Navigator.pop(ctx);
                _viewFullImage(coverPic, 'Cover Photo');
              },
            ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Change photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickCoverPhoto();
            },
          ),
          if (coverPic != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete photo',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCoverPic();
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _deleteProfilePic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile photo?'),
        content: const Text('Your profile photo will be removed.'),
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
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('delete_profile_pic', {});
      if (!mounted) return;
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
    setState(() => _uploadingPic = true);
    try {
      await widget.api.deleteProfilePic();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('delete_profile_pic', {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Delete queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _uploadingPic = false);
    }
  }

  Future<void> _deleteCoverPic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cover photo?'),
        content: const Text('Your cover photo will be removed.'),
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
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('delete_cover_pic', {});
      if (!mounted) return;
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
    setState(() => _uploadingCover = true);
    try {
      await widget.api.deleteCoverPic();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cover photo removed.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('delete_cover_pic', {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Delete queued — will sync when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickProfilePic() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 70,
    );
    if (file == null || !mounted) return;
    final pickedBytes = await file.readAsBytes();
    final bytes = await _arrangePickedImage(
      pickedBytes,
      title: 'Arrange profile photo',
      aspectRatio: 1,
      circle: true,
    );
    if (bytes == null || !mounted) return;
    final image = base64Encode(bytes);
    if (!mounted) return;

    if (!SyncService.instance.isOnline) {
      await LocalDb.instance
          .queueAction('update_profile_pic', {'image': image});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.sync, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Photo queued — will upload when online'),
        ]),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _uploadingPic = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Uploading profile photo...'),
      ]),
      duration: Duration(minutes: 1),
    ));
    try {
      await widget.api.updateProfilePic(image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile photo updated!'),
        duration: Duration(seconds: 3),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('update_profile_pic', {'image': image});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Photo queued — will upload when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5)));
      }
    } finally {
      if (mounted) setState(() => _uploadingPic = false);
    }
  }

  Future<void> _pickCoverPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 600,
      imageQuality: 75,
    );
    if (file == null || !mounted) return;
    final pickedBytes = await file.readAsBytes();
    final bytes = await _arrangePickedImage(
      pickedBytes,
      title: 'Arrange cover photo',
      aspectRatio: 16 / 7,
    );
    if (bytes == null || !mounted) return;
    final image = base64Encode(bytes);
    if (!mounted) return;

    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('update_cover_pic', {'image': image});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.sync, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Photo queued — will upload when online'),
        ]),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _uploadingCover = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Uploading cover photo...'),
      ]),
      duration: Duration(minutes: 1),
    ));
    try {
      await widget.api.updateCoverPic(image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cover photo updated!'),
        duration: Duration(seconds: 3),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance
            .queueAction('update_cover_pic', {'image': image});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Photo queued — will upload when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5)));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  void _viewPhoto(ProfilePhoto photo) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: _isOwnProfile
                ? [
                    IconButton(
                      icon:
                          const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        _deletePhoto(photo);
                      },
                    ),
                  ]
                : [],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(
                base64Decode(photo.image),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openEditSheet() {
    final d = _profileData;
    final bio = TextEditingController(text: d?.bio ?? '');
    final address = TextEditingController(text: d?.address ?? '');
    final school = TextEditingController(text: d?.school ?? '');
    final birthday = TextEditingController(text: d?.birthday ?? '');
    final work = TextEditingController(text: d?.work ?? '');
    final currentCity = TextEditingController(text: d?.currentCity ?? '');
    final hometown = TextEditingController(text: d?.hometown ?? '');
    final relationship =
        TextEditingController(text: d?.relationshipStatus ?? '');
    final featured = TextEditingController(text: d?.featured.join('\n') ?? '');
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 18, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Edit Profile',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  TextField(
                      controller: bio,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Bio')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Address')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: school,
                      decoration: const InputDecoration(labelText: 'School')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: birthday,
                      decoration: const InputDecoration(labelText: 'Birthday')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: work,
                      decoration: const InputDecoration(labelText: 'Work')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: currentCity,
                      decoration:
                          const InputDecoration(labelText: 'Current city')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: hometown,
                      decoration: const InputDecoration(labelText: 'Hometown')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: relationship,
                      decoration: const InputDecoration(
                          labelText: 'Relationship status')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: featured,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Featured highlights',
                          hintText: 'One photo/post highlight per line')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            try {
                              await widget.api
                                  .updateUserProfileData(UserProfileData(
                                bio: bio.text.trim(),
                                address: address.text.trim(),
                                school: school.text.trim(),
                                birthday: birthday.text.trim(),
                                work: work.text.trim(),
                                currentCity: currentCity.text.trim(),
                                hometown: hometown.text.trim(),
                                relationshipStatus: relationship.text.trim(),
                                featured: featured.text
                                    .split('\n')
                                    .map((line) => line.trim())
                                    .where((line) => line.isNotEmpty)
                                    .toList(),
                              ));
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile updated!'),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                                await _load();
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setSheetState(() => saving = false);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(friendlyError(e)),
                                        backgroundColor: Colors.red.shade700,
                                        duration: const Duration(seconds: 5)));
                              }
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _logoutOverlay() => Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(30),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Logging out…',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_isAdmin) {
      final screen = _buildAdminProfile(context);
      if (!_loggingOut) return screen;
      return Stack(children: [screen, _logoutOverlay()]);
    }

    final coverPic = _profileData?.coverPic;
    final profilePic = _profileData?.profilePic;
    final initials = _displayInitials;

    final screen = Scaffold(
      appBar: _isOwnProfile
          ? null
          : AppBar(
              title: Text(_displayName.isEmpty ? 'Profile' : _displayName)),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: SafeArea(
        top: _isOwnProfile,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 232,
                child: Stack(
                  children: [
                    // Cover photo
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: (_isOwnProfile && !_uploadingCover)
                            ? _showCoverPhotoOptions
                            : null,
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: _uploadingCover
                              ? _defaultCover(
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white)))
                              : coverPic != null
                                  ? Image.memory(
                                      base64Decode(coverPic),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _defaultCover(),
                                    )
                                  : _defaultCover(),
                        ),
                      ),
                    ),
                    // Camera hint (own profile only)
                    if (_isOwnProfile)
                      Positioned(
                        top: 148,
                        right: 10,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.camera_alt_outlined,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    // Profile pic
                    Positioned(
                      top: 128,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: (_isOwnProfile && !_uploadingPic)
                              ? _showProfilePicOptions
                              : null,
                          child: Stack(
                            children: [
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 4),
                                  color: appPrimary,
                                ),
                                child: ClipOval(
                                  child: _uploadingPic
                                      ? Container(
                                          color: appPrimary,
                                          child: const Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white)))
                                      : profilePic != null
                                          ? Image.memory(
                                              base64Decode(profilePic),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _initialsWidget(initials),
                                            )
                                          : _initialsWidget(initials),
                                ),
                              ),
                              if (_isOwnProfile)
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                        color: appPrimary,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.camera_alt,
                                        size: 13, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _displayName.isEmpty ? 'Loading...' : _displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (_isOwnProfile)
                      Text(widget.api.storedUser?.email ?? '',
                          style: const TextStyle(color: appMuted, fontSize: 13))
                    else if (_visitedUserProfile != null)
                      Text(
                        _visitedUserProfile!.role[0].toUpperCase() +
                            _visitedUserProfile!.role.substring(1),
                        style: const TextStyle(color: appMuted, fontSize: 13),
                      ),
                    const SizedBox(height: 16),
                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StatCard(
                            label: 'Posts', value: _posts.length.toString()),
                        const SizedBox(width: 8),
                        StatCard(
                            label: 'Photos', value: _photos.length.toString()),
                        const SizedBox(width: 8),
                        if (_isOwnProfile)
                          StatCard(
                              label: 'Job Posts',
                              value: _myJobPosts.length.toString())
                        else
                          StatCard(
                              label: 'Followers',
                              value: _followerCount.toString()),
                      ],
                    ),
                    if (_isOwnProfile) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showFollowList(followers: true),
                            child: StatCard(
                              label: 'Followers',
                              value: (_profileData?.followerCount ?? 0).toString(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showFollowList(followers: false),
                            child: StatCard(
                              label: 'Following',
                              value: (_profileData?.followingCount ?? 0).toString(),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Action buttons
                    if (_isOwnProfile) ...[
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openEditSheet,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit Profile'),
                          ),
                        ),
                        if (widget.openDashboard != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.openDashboard,
                              icon: const Icon(Icons.grid_view_outlined,
                                  size: 16),
                              label: const Text('Dashboard'),
                            ),
                          ),
                        ],
                      ]),
                    ] else ...[
                      // Visitor: follow/unfollow
                      if (!_isViewingAsAdmin &&
                          widget.api.storedUser?.id != widget.viewingUserId)
                        SizedBox(
                          width: double.infinity,
                          child: _followLoading
                              ? const Center(
                                  child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)))
                              : FilledButton.icon(
                                  onPressed: _toggleFollow,
                                  icon: Icon(_isFollowing
                                      ? Icons.person_remove_outlined
                                      : Icons.person_add_outlined),
                                  label: Text(
                                      _isFollowing ? 'Unfollow' : 'Follow'),
                                  style: _isFollowing
                                      ? FilledButton.styleFrom(
                                          backgroundColor: Colors.grey.shade300,
                                          foregroundColor: Colors.black87)
                                      : null,
                                ),
                        ),
                      // View service profile if worker/agency
                      if (['worker', 'agency']
                          .contains(_visitedUserProfile?.role)) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ProviderDetailScreen(
                                    api: widget.api,
                                    providerUserId: widget.viewingUserId!),
                              ),
                            ),
                            icon: const Icon(Icons.work_outline, size: 16),
                            label: const Text('View Service Profile'),
                          ),
                        ),
                      ],
                      if (widget.viewingUserId != null &&
                          widget.api.storedUser?.id != widget.viewingUserId &&
                          !_isViewingAsAdmin &&
                          widget.api.token.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => showReportSheet(
                              context,
                              api: widget.api,
                              reportedUserId: widget.viewingUserId!,
                              contentLabel: 'this user',
                            ),
                            icon: const Icon(Icons.flag_outlined, size: 16),
                            label: const Text('Report user'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              side: BorderSide(color: Colors.red.shade300),
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    _buildIntroCard(context),
                    const SizedBox(height: 12),
                    _buildAboutCard(context),
                    const SizedBox(height: 12),
                    _buildFeaturedSection(context),
                    const SizedBox(height: 12),
                    _buildStatsCard(context),
                    const SizedBox(height: 12),
                    _buildReviewsCard(context),
                    const SizedBox(height: 12),
                    _buildJobPostsSection(context),
                    const SizedBox(height: 16),
                    // Photo library
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Photos',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (_isOwnProfile)
                          _uploadingPhoto
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  onPressed: _pickAndUploadPhoto,
                                  icon: const Icon(
                                      Icons.add_photo_alternate_outlined),
                                  color: appPrimary,
                                  tooltip: 'Add photo',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const SkeletonProfilePhotos()
                    else if (_photos.isEmpty)
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_outlined,
                                  size: 32, color: Colors.grey.shade400),
                              const SizedBox(height: 6),
                              Text(
                                _isOwnProfile
                                    ? 'No photos yet. Tap + to add one.'
                                    : 'No photos yet.',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: _photos.length,
                        itemBuilder: (context, index) {
                          final photo = _photos[index];
                          return GestureDetector(
                            onTap: () => _viewPhoto(photo),
                            onLongPress: _isOwnProfile
                                ? () => _deletePhoto(photo)
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(photo.image),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.broken_image_outlined,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    // Posts
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isOwnProfile ? 'My Posts' : 'Posts',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loading) const SkeletonProfilePosts(),
                    if (!_loading && _posts.isEmpty)
                      EmptyState(
                          icon: Icons.newspaper_outlined,
                          title: 'No posts yet.',
                          subtitle: _isOwnProfile
                              ? 'Share something from the Explore tab.'
                              : 'This user has not posted yet.'),
                    ..._posts.map((post) => _PostCard(
                          post: post,
                          api: widget.api,
                          reload: _load,
                        )),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      )),
        ],
      ),
    );
    if (!_loggingOut) return screen;
    return Stack(children: [screen, _logoutOverlay()]);
  }

  Widget _buildStatsCard(BuildContext context) {
    final reactions = _posts.fold<int>(0, (sum, p) => sum + p.likeCount);
    final comments = _posts.fold<int>(0, (sum, p) => sum + p.commentCount);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.insights_outlined, color: appPrimary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Stats',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: StatCard(label: 'Reactions', value: reactions.toString())),
          const SizedBox(width: 8),
          Expanded(
              child: StatCard(label: 'Comments', value: comments.toString())),
          const SizedBox(width: 8),
          Expanded(
              child: StatCard(
                  label: _isOwnProfile ? 'Bookings' : 'Followers',
                  value: _isOwnProfile
                      ? _bookingCount.toString()
                      : _followerCount.toString())),
        ]),
        if (_isOwnProfile && _myJobPosts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: StatCard(
                    label: 'Job Posts', value: _myJobPosts.length.toString())),
            const SizedBox(width: 8),
            Expanded(
                child: StatCard(
                    label: 'Photos', value: _photos.length.toString())),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ]),
    );
  }

  double get _averageReviewRating {
    if (_reviews.isEmpty) return 0;
    return _reviews.fold<int>(0, (sum, review) => sum + review.rating) /
        _reviews.length;
  }

  Widget _buildReviewsCard(BuildContext context) {
    final average = _averageReviewRating;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.star_outline, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Text(
            'Ratings',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          if (_reviews.isNotEmpty)
            Text('${average.toStringAsFixed(1)} / 5',
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        if (_reviews.isEmpty)
          const EmptyState(
              icon: Icons.star_outline,
              title: 'No ratings yet.',
              subtitle: 'Completed booking reviews will appear here.')
        else ...[
          Row(children: [
            Expanded(
                child: StatCard(
                    label: 'Average', value: average.toStringAsFixed(1))),
            const SizedBox(width: 8),
            Expanded(
                child: StatCard(
                    label: 'Reviews', value: _reviews.length.toString())),
          ]),
          const SizedBox(height: 12),
          ..._reviews.take(3).map((review) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ...List.generate(
                          5,
                          (index) => Icon(
                            index < review.rating
                                ? Icons.star
                                : Icons.star_border,
                            size: 16,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(review.reviewerName ?? 'User',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ]),
                      if ((review.comment ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(review.comment!,
                            style:
                                const TextStyle(color: appMuted, fontSize: 13)),
                      ],
                    ]),
              )),
        ],
      ]),
    );
  }

  Widget _buildJobPostsSection(BuildContext context) {
    if (!_isOwnProfile &&
        (_visitedUserProfile?.posts.isEmpty ?? true) &&
        _myJobPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    final jobPosts = _isOwnProfile
        ? _myJobPosts
        : (_visitedUserProfile?.posts ?? const <JobPost>[]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          const Icon(Icons.work_outline, color: appPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOwnProfile ? 'My Job Posts' : 'Job Posts',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Text('${jobPosts.length}',
              style: const TextStyle(color: appMuted, fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 10),
      if (_loading)
        const SkeletonProfileJobPosts()
      else if (jobPosts.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: appBorder),
          ),
          child: Text(
            _isOwnProfile
                ? 'No job posts yet. Post a job from the Jobs tab.'
                : 'No job posts yet.',
            style: const TextStyle(color: appMuted),
          ),
        )
      else
        SizedBox(
          height: 215,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(right: 4, bottom: 2),
            itemCount: jobPosts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: 240,
              child: _JobPostCard(
                post: jobPosts[i],
                canDelete: _isOwnProfile,
                onDelete:
                    _isOwnProfile ? () => _deleteJobPost(jobPosts[i]) : null,
                onTap: () => _openJobPostDetail(context, jobPosts[i]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _buildIntroCard(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Intro',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          if (_profileData?.bio?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(_profileData!.bio!, textAlign: TextAlign.left),
          ] else
            const Text('Add a short bio so people know who you are.',
                style: TextStyle(color: appMuted)),
          const SizedBox(height: 12),
          InfoLine(
              icon: Icons.work_outline,
              label: 'Work',
              value: _valueOrEmpty(_profileData?.work)),
          InfoLine(
              icon: Icons.school_outlined,
              label: 'Education',
              value: _valueOrEmpty(_profileData?.school)),
          InfoLine(
              icon: Icons.location_city_outlined,
              label: 'Current city',
              value: _valueOrEmpty(_profileData?.currentCity)),
          InfoLine(
              icon: Icons.home_outlined,
              label: 'Hometown',
              value: _valueOrEmpty(_profileData?.hometown)),
          InfoLine(
              icon: Icons.favorite_border,
              label: 'Relationship',
              value: _valueOrEmpty(_profileData?.relationshipStatus)),
        ]),
      );

  Widget _buildAboutCard(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('About',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_isOwnProfile)
            InfoLine(
                icon: Icons.mail_outline,
                label: 'Email',
                value: widget.api.storedUser?.email ?? ''),
          InfoLine(
              icon: Icons.place_outlined,
              label: 'Address',
              value: _valueOrEmpty(_profileData?.address)),
          InfoLine(
              icon: Icons.card_giftcard_outlined,
              label: 'Birthday',
              value: _valueOrEmpty(_profileData?.birthday)),
          InfoLine(
              icon: Icons.link_outlined,
              label: 'Profile URL',
              value:
                  'hanapgawa.app/profile/${_isOwnProfile ? widget.api.storedUser?.id ?? 'me' : widget.viewingUserId}'),
        ]),
      );

  Widget _buildFeaturedSection(BuildContext context) {
    final featured = _profileData?.featured ?? const <String>[];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Featured',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (featured.isEmpty)
          Text(
              _isOwnProfile
                  ? 'Highlight selected photos, posts, or achievements from Edit Profile.'
                  : 'No featured highlights yet.',
              style: const TextStyle(color: appMuted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: featured
                .map((item) => Chip(
                    avatar: const Icon(Icons.star_outline, size: 16),
                    label: Text(item)))
                .toList(),
          ),
      ]),
    );
  }

  String _valueOrEmpty(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not filled out';

  Widget _defaultCover({Widget? child}) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [appPrimary, appSecondary, Color(0xFFC8AAAA)]),
        ),
        child: child,
      );

  Widget _initialsWidget(String initials) => Container(
        color: appPrimary,
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 32),
          ),
        ),
      );

  Widget _buildAdminProfile(BuildContext context) {
    final user = widget.api.storedUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Profile'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [appPrimary, Color(0xFF7A4BDB)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: appPrimary.withAlpha(50),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.initials ?? 'A',
                      style: const TextStyle(
                          color: appPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.fullName ?? 'HanapGawa Admin',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(user?.email ?? '',
                      style: const TextStyle(color: Color(0xDFFFFFFF))),
                  const SizedBox(height: 14),
                  const Wrap(spacing: 8, runSpacing: 8, children: [
                    _AdminBadge(icon: Icons.shield_outlined, label: 'Admin'),
                    _AdminBadge(
                        icon: Icons.visibility_outlined, label: 'Monitor'),
                    _AdminBadge(icon: Icons.gavel_outlined, label: 'Moderate'),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Responsibilities',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    SizedBox(height: 10),
                    InfoLine(
                        icon: Icons.people_outline,
                        label: 'Users',
                        value: 'Manage users and account status'),
                    InfoLine(
                        icon: Icons.report_outlined,
                        label: 'Reports',
                        value: 'Handle complaints and violations'),
                    InfoLine(
                        icon: Icons.category_outlined,
                        label: 'Categories',
                        value: 'Maintain service categories'),
                  ]),
            ),
            AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Marketplace Restrictions',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    const Text(
                      'This account manages HanapGawa only. It cannot post jobs, offer services, book workers, apply to jobs, or receive marketplace reviews.',
                      style: TextStyle(color: appMuted, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: widget.openDashboard,
                      icon: const Icon(Icons.dashboard_outlined),
                      label: const Text('Open Admin Dashboard'),
                    ),
                  ]),
            ),
            if (widget.onLogout != null)
              OutlinedButton.icon(
                onPressed: _loggingOut ? null : _handleLogout,
                icon: _loggingOut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.logout),
                label: Text(_loggingOut ? 'Logging out…' : 'Logout'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(34),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withAlpha(60)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _JobPostCard extends StatelessWidget {
  const _JobPostCard({
    required this.post,
    this.canDelete = false,
    this.onDelete,
    this.onTap,
  });
  final JobPost post;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withAlpha(15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  post.postType == 'offering_service'
                      ? 'Offering Service'
                      : 'Hiring',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              if (canDelete && onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                ),
            ]),
            const SizedBox(height: 8),
            Text(post.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(post.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: appMuted, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              InfoPill(icon: Icons.work_outline, label: post.category),
              InfoPill(icon: Icons.place_outlined, label: post.municipality),
              if (post.budgetMin != null)
                InfoPill(
                    icon: Icons.payments_outlined,
                    label: 'P${post.budgetMin} – P${post.budgetMax ?? 0}'),
            ]),
            const SizedBox(height: 8),
            Text(timeAgo(post.createdAt),
                style: const TextStyle(color: appMuted, fontSize: 12)),
          ]),
        ),
      );
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.api,
    required this.reload,
  });
  final SocialPost post;
  final MarketplaceApi api;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) => FeedCard(
        item: FeedItem(
          type: 'post',
          id: post.id,
          createdAt: post.createdAt,
          socialPost: post,
          likeCount: post.likeCount,
          commentCount: post.commentCount,
          isLiked: post.isLiked,
        ),
        api: api,
        reload: reload,
      );
}

class _FollowListSheet extends StatefulWidget {
  const _FollowListSheet({
    required this.api,
    required this.title,
    required this.fetch,
  });
  final MarketplaceApi api;
  final String title;
  final Future<List<UserSearchResult>> Function() fetch;

  @override
  State<_FollowListSheet> createState() => _FollowListSheetState();
}

class _FollowListSheetState extends State<_FollowListSheet> {
  List<UserSearchResult> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.fetch().then((users) {
      if (mounted) setState(() { _users = users; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Icon(widget.title == 'Followers'
                  ? Icons.people_outline
                  : Icons.person_outline, color: appPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? Center(
                        child: Text(
                          widget.title == 'Followers'
                              ? 'No followers yet.'
                              : 'Not following anyone yet.',
                          style: const TextStyle(color: appMuted),
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return ListTile(
                            leading: _UserAvatar(u),
                            title: Text(u.fullName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            subtitle: Text(
                              _subtitle(u),
                              style: const TextStyle(
                                  color: appMuted, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ProfileScreen(
                                    api: widget.api,
                                    viewingUserId: u.id,
                                    preloadedName: u.fullName,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _subtitle(UserSearchResult u) {
    final parts = <String>[];
    if (u.role != 'client') {
      parts.add(u.role[0].toUpperCase() + u.role.substring(1));
    }
    if (u.followers > 0) parts.add('${u.followers} followers');
    return parts.isEmpty ? 'HanapGawa user' : parts.join(' · ');
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar(this.user);
  final UserSearchResult user;

  @override
  Widget build(BuildContext context) {
    final pic = user.profilePic;
    final initials = () {
      final parts = user.fullName.trim().split(' ');
      if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      return parts.first.isEmpty ? '?' : parts.first[0].toUpperCase();
    }();
    return CircleAvatar(
      radius: 22,
      backgroundColor: appPrimary,
      backgroundImage: pic != null && pic.isNotEmpty
          ? MemoryImage(base64Decode(pic))
          : null,
      child: pic == null || pic.isEmpty
          ? Text(initials,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700))
          : null,
    );
  }
}
