import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../api/marketplace_api.dart';
import '../models/models.dart';
import 'local_db.dart';

/// Monitors connectivity and processes the offline pending-action queue
/// when the device comes back online.
///
/// Uses a dual strategy:
///   1. `connectivity_plus` fires quickly when the network interface changes.
///   2. A 15-second HTTP ping to /api/v1/health confirms *actual* reachability,
///      which handles the case where the interface stays up but internet is gone
///      (e.g. Android emulator while the host PC's internet is toggled off).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _onlineController = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _onlineController.stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _pingTimer;
  MarketplaceApi? _api;

  Future<void> initialize(MarketplaceApi api) async {
    _api = api;

    // Initial reachability check via real ping
    _isOnline = await _pingBackend();

    // connectivity_plus: fast signal when interface changes
    _sub = Connectivity().onConnectivityChanged.listen((_) async {
      await _checkAndMaybeSync();
    });

    // Periodic ping every 15 s — catches internet-restored without interface change
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _checkAndMaybeSync();
    });
  }

  /// Pings the backend health endpoint and checks that postgres is connected.
  /// Returns true only when the backend is up AND its database is reachable —
  /// so "online" means the full stack is functional, not just the local server.
  Future<bool> _pingBackend() async {
    if (_api == null) return false;
    try {
      const baseUrl = 'https://hanapgawa.onrender.com/api/v1';
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 500) return false;
      // Parse the JSON body — only consider truly online if postgres is healthy
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final databases = body['databases'] as Map<String, dynamic>?;
      final postgres = databases?['postgres'] as Map<String, dynamic>?;
      return postgres?['healthy'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAndMaybeSync() async {
    final prev = _isOnline;
    _isOnline = await _pingBackend();
    if (_isOnline != prev) _onlineController.add(_isOnline);
    if (!prev && _isOnline) {
      await processQueue();
    }
  }

  /// Processes all `pending_sync` actions. Returns how many were synced.
  Future<int> processQueue() async {
    final api = _api;
    if (api == null || !_isOnline) return 0;

    final actions = await LocalDb.instance.getPendingActions();
    var synced = 0;

    for (final action in actions) {
      final id = action['id'] as int;
      final type = action['action_type'] as String;
      final payload =
          jsonDecode(action['payload_json'] as String) as Map<String, dynamic>;

      try {
        await _execute(api, type, payload);
        await LocalDb.instance.markActionSynced(id);
        synced++;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        // Auth errors will never succeed with the same token — fail permanently
        final isAuthError = msg.contains('401') ||
            msg.contains('unauthorized') ||
            msg.contains('jwt') ||
            msg.contains('token');
        if (isAuthError) {
          await LocalDb.instance.markActionPermanentlyFailed(id);
        } else {
          await LocalDb.instance.markActionFailed(id);
        }
      }
    }

    return synced;
  }

  Future<void> _execute(
      MarketplaceApi api, String type, Map<String, dynamic> p) async {
    switch (type) {
      case 'toggle_like':
        await api.toggleLike(
          p['itemType'] as String,
          p['itemId'] as String,
        );

      case 'add_comment':
        await api.addPostComment(
          p['itemType'] as String,
          p['itemId'] as String,
          p['body'] as String? ?? '',
          parentCommentId: p['parentCommentId'] as String?,
          gifUrl: p['gifUrl'] as String?,
        );

      case 'create_story':
        await api.createStory(
          body: p['body'] as String? ?? '',
          image: p['image'] as String?,
          metadata: p['metadata'] != null
              ? Map<String, dynamic>.from(p['metadata'] as Map)
              : const {},
          privacy: p['privacy'] as String? ?? 'Public',
        );

      case 'create_social_post':
        await api.createSocialPost(
          p['body'] as String? ?? '',
          image: p['image'] as String?,
          video: p['video'] as String?,
          privacy: p['privacy'] as String?,
          metadata: p['metadata'] != null
              ? Map<String, dynamic>.from(p['metadata'] as Map)
              : null,
          sharedFromType: p['sharedFromType'] as String?,
          sharedFromId: p['sharedFromId'] as String?,
        );

      case 'send_message':
        await api.sendConversationMessage(
          p['conversationId'] as String,
          p['content'] as String? ?? '',
        );

      case 'send_job_offer':
        await api.sendJobOffer(
          p['jobPostId'] as String,
          p['message'] as String? ?? '',
          proposedPrice: p['proposedPrice'] as int?,
        );

      case 'submit_review':
        await api.submitReview(
          bookingId: p['bookingId'] as String,
          rating: p['rating'] as int,
          comment: p['comment'] as String? ?? '',
        );

      case 'submit_report':
        await api.submitReport(
          providerUserId: p['providerUserId'] as String,
          reason: p['reason'] as String,
          details: p['details'] as String? ?? '',
        );

      case 'update_booking_status':
        await api.updateBookingStatus(
          p['bookingId'] as String,
          p['status'] as String,
          cancellationReason: p['cancellationReason'] as String?,
        );

      case 'reschedule_booking':
        await api.rescheduleBooking(
          p['bookingId'] as String,
          DateTime.fromMillisecondsSinceEpoch(p['scheduledAtMs'] as int),
          p['note'] as String? ?? '',
        );

      case 'create_job_post':
        await api.createJobPost(JobPostPayload(
          postType: p['postType'] as String? ?? 'looking_for_worker',
          title: p['title'] as String? ?? '',
          category: p['category'] as String? ?? '',
          municipality: p['municipality'] as String? ?? 'Bongao',
          locationDetails: p['locationDetails'] as String? ?? '',
          description: p['description'] as String? ?? '',
          budgetMin: p['budgetMin'] as int?,
          budgetMax: p['budgetMax'] as int?,
          workersNeeded: p['workersNeeded'] as int? ?? 1,
          allowDirectBooking: p['allowDirectBooking'] as bool? ?? false,
        ));

      case 'update_job_post':
        await api.updateJobPost(
          p['jobPostId'] as String,
          JobPostPayload(
            postType: p['postType'] as String? ?? 'looking_for_worker',
            title: p['title'] as String? ?? '',
            category: p['category'] as String? ?? '',
            municipality: p['municipality'] as String? ?? 'Bongao',
            locationDetails: p['locationDetails'] as String? ?? '',
            description: p['description'] as String? ?? '',
            budgetMin: p['budgetMin'] as int?,
            budgetMax: p['budgetMax'] as int?,
            workersNeeded: p['workersNeeded'] as int? ?? 1,
            allowDirectBooking: p['allowDirectBooking'] as bool? ?? false,
          ),
        );

      case 'delete_job_post':
        await api.deleteJobPost(p['jobPostId'] as String);

      case 'accept_job_offer':
        await api.acceptJobOffer(
          p['jobPostId'] as String,
          p['offerId'] as String,
        );

      case 'decline_job_offer':
        await api.declineJobOffer(
          p['jobPostId'] as String,
          p['offerId'] as String,
        );

      case 'admin_update_user':
        await api.updateAdminUserStatus(
          p['userId'] as String,
          p['status'] as String,
        );

      case 'admin_resolve_report':
        await api.updateReportStatus(
          p['reportId'] as String,
          p['status'] as String,
        );

      case 'admin_toggle_category':
        await api.updateCategory(
          p['categoryId'] as String,
          active: p['active'] as bool,
        );

      case 'admin_create_category':
        await api.createCategory(
          name: p['name'] as String,
          description: p['description'] as String? ?? '',
          icon: p['icon'] as String? ?? 'briefcase-outline',
        );

      case 'update_social_post':
        await api.updateSocialPost(
          p['postId'] as String,
          p['body'] as String? ?? '',
          p['privacy'] as String? ?? 'Public',
        );

      case 'delete_social_post':
        await api.deleteSocialPost(p['postId'] as String);

      case 'delete_comment':
        await api.deletePostComment(p['commentId'] as String);

      case 'update_profile_pic':
        await api.updateProfilePic(p['image'] as String);

      case 'delete_profile_pic':
        await api.deleteProfilePic();

      case 'update_cover_pic':
        await api.updateCoverPic(p['image'] as String);

      case 'delete_cover_pic':
        await api.deleteCoverPic();

      case 'admin_delete_post':
        await api.deleteAdminPost(p['postId'] as String);

      case 'admin_delete_review':
        await api.deleteAdminReview(p['reviewId'] as String);

      case 'admin_update_provider':
        await api.updateProviderApproval(
          p['userId'] as String,
          p['status'] as String,
        );

      case 'admin_delete_job':
        await api.deleteAdminJob(p['jobId'] as String);

      case 'admin_delete_listing':
        await api.deleteAdminListing(p['listingId'] as String);
    }
  }

  Future<void> dispose() async {
    _pingTimer?.cancel();
    await _sub?.cancel();
    await _onlineController.close();
  }

  /// Returns true if the error looks like a transient network/connectivity
  /// failure rather than a business-logic or auth error from the server.
  static bool isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('enotfound') ||
        s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('connection timed out') ||
        s.contains('connection reset') ||
        s.contains('no address associated') ||
        s.contains('connection closed before') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception');
  }
}
