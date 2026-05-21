import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils.dart';

class MarketplaceApi {
  static const _tokenKey = 'hanapgawa_token';
  static const _userKey = 'hanapgawa_user';
  static const _onboardingKey = 'hanapgawa_onboarding_seen';

  late final SharedPreferences _prefs;
  SessionUser? storedUser;

  String get _baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    return 'https://hanapgawa.onrender.com/api/v1';
  }

  String get token => _prefs.getString(_tokenKey) ?? '';
  bool get hasSeenOnboarding => _prefs.getBool(_onboardingKey) ?? false;
  void markOnboardingSeen() => _prefs.setBool(_onboardingKey, true);
  void clearOnboardingSeen() => _prefs.setBool(_onboardingKey, false);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_userKey);
    if (raw != null) {
      storedUser =
          SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  Future<AuthResponse> signInWithGoogle(String idToken) async =>
      AuthResponse.fromJson(await _post('/auth/google', {'idToken': idToken}));

  Future<AuthResponse> login(String email, String password) async =>
      AuthResponse.fromJson(
          await _post('/auth/login', {'email': email, 'password': password}));

  Future<RegisterResponse> register(
          String email, String password, String fullName) async =>
      RegisterResponse.fromJson(await _post('/auth/register', {
        'email': email,
        'password': password,
        'fullName': fullName,
        'role': 'user',
      }));

  Future<AuthResponse> verifyEmail(String email, String code) async =>
      AuthResponse.fromJson(
          await _post('/auth/email/verify', {'email': email, 'code': code}));

  Future<String?> resendVerificationCode(String email) async {
    final json = await _post('/auth/email/resend-code', {'email': email});
    return json['devVerificationCode']?.toString();
  }

  Future<void> persistSession(AuthResponse auth) async {
    await _prefs.setString(_tokenKey, auth.token);
    await _prefs.setString(_userKey, jsonEncode(auth.user.toJson()));
    storedUser = auth.user;
  }

  Future<void> clearSession() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
    storedUser = null;
  }

  Future<List<FeedItem>> getFeed({int limit = 40}) async {
    final json =
        await _get('/feed', auth: token.isNotEmpty, query: {'limit': '$limit'});
    return listOf(json['items'], FeedItem.fromJson);
  }

  Future<List<UserSearchResult>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    final json = await _get('/users/search', query: {'q': query.trim()});
    return listOf(json['users'], UserSearchResult.fromJson);
  }

  Future<UserProfile> getUserProfile(String userId) async {
    final json = await _get('/users/$userId/profile');
    return UserProfile.fromJson(json);
  }

  Future<bool> checkIsFollowing(String userId) async {
    final json = await _get('/users/$userId/follow-status', auth: true);
    return json['isFollowing'] == true;
  }

  Future<int> followUser(String userId) async {
    final json = await _post('/users/$userId/follow', {}, auth: true);
    return asInt(json['followerCount']);
  }

  Future<int> unfollowUser(String userId) async {
    final json = await _delete2('/users/$userId/follow', auth: true);
    return asInt(json['followerCount']);
  }

  // Returns (isNowLiked, likeCount)
  Future<(bool, int)> toggleLike(String itemType, String itemId) async {
    final json = await _post('/feed/$itemType/$itemId/like', {}, auth: true);
    return (json['liked'] == true, asInt(json['likeCount']));
  }

  Future<List<Map<String, dynamic>>> getPostLikers(
      String itemType, String itemId) async {
    final json = await _get('/feed/$itemType/$itemId/likers');
    return List<Map<String, dynamic>>.from((json['likers'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<Map<String, dynamic>>> getPostSharers(
      String itemType, String itemId) async {
    final json = await _get('/feed/$itemType/$itemId/sharers');
    return List<Map<String, dynamic>>.from((json['sharers'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<PostComment>> getPostComments(
      String itemType, String itemId) async {
    final json = await _get('/feed/$itemType/$itemId/comments');
    return listOf(json['comments'], PostComment.fromJson);
  }

  Future<PostComment> addPostComment(
      String itemType, String itemId, String body,
      {String? parentCommentId, String? gifUrl}) async {
    final json = await _post(
        '/feed/$itemType/$itemId/comments',
        {
          'body': body,
          if (parentCommentId != null) 'parentCommentId': parentCommentId,
          if (gifUrl != null) 'gifUrl': gifUrl,
        },
        auth: true);
    return PostComment.fromJson(asMap(json['comment']));
  }

  Future<PostComment> updatePostComment(String commentId, String body) async {
    final json =
        await _patch('/feed/comments/$commentId', {'body': body}, auth: true);
    return PostComment.fromJson(asMap(json['comment']));
  }

  Future<void> deletePostComment(String commentId) async =>
      _deleteVoid('/feed/comments/$commentId', auth: true);

  Future<(bool, int)> toggleCommentReaction(String commentId) async {
    final json =
        await _post('/feed/comments/$commentId/reaction', {}, auth: true);
    return (json['reacted'] == true, asInt(json['reactionCount']));
  }

  Future<void> createSocialPost(
    String body, {
    String? image,
    String? video,
    Map<String, dynamic>? metadata,
    String? privacy,
    DateTime? scheduledAt,
    String? sharedFromType,
    String? sharedFromId,
    Map<String, dynamic>? sharedSnapshot,
  }) async =>
      _post(
          '/posts',
          {
            'body': body,
            if (image != null) 'image': image,
            if (video != null) 'video': video,
            if (metadata != null) 'metadata': metadata,
            if (privacy != null) 'privacy': privacy,
            if (scheduledAt != null)
              'scheduledAt': scheduledAt.toIso8601String(),
            if (sharedFromType != null) 'sharedFromType': sharedFromType,
            if (sharedFromId != null) 'sharedFromId': sharedFromId,
            if (sharedSnapshot != null) 'sharedSnapshot': sharedSnapshot,
          },
          auth: true);

  Future<SocialPost> updateSocialPost(
      String postId, String body, String privacy) async {
    final json = await _patch(
        '/posts/$postId', {'body': body, 'privacy': privacy},
        auth: true);
    return SocialPost.fromJson(asMap(json['post']));
  }

  Future<void> deleteSocialPost(String postId) async =>
      _deleteVoid('/posts/$postId', auth: true);

  Future<List<SocialPost>> getMyPosts() async {
    final json = await _get('/posts/mine', auth: true);
    return listOf(json['posts'], SocialPost.fromJson);
  }

  Future<UserProfileData> getUserProfileData() async {
    final json = await _get('/users/me/profile-data', auth: true);
    return UserProfileData.fromJson(json);
  }

  Future<UserProfileData?> getUserProfileDataPublic(String userId) async {
    final json = await _get('/users/$userId/profile-data');
    if (json['profileData'] == null) return null;
    return UserProfileData.fromJson(asMap(json['profileData']));
  }

  Future<List<SocialPost>> getUserSocialPosts(String userId) async {
    final json = await _get('/users/$userId/social-posts');
    return listOf(json['posts'], SocialPost.fromJson);
  }

  Future<List<ProfilePhoto>> getUserPhotosPublic(String userId) async {
    final json = await _get('/users/$userId/photos');
    return listOf(json['photos'], ProfilePhoto.fromJson);
  }

  Future<void> updateUserProfileData(UserProfileData data) async =>
      _put('/users/me/profile-data', data.toJson(), auth: true);

  Future<void> updateProfilePic(String imageBase64) async =>
      _put('/users/me/profile-pic', {'profilePic': imageBase64}, auth: true);

  Future<void> deleteProfilePic() async =>
      _put('/users/me/profile-pic', {'profilePic': null}, auth: true);

  Future<void> updateCoverPic(String imageBase64) async =>
      _put('/users/me/profile-pic', {'coverPic': imageBase64}, auth: true);

  Future<void> deleteCoverPic() async =>
      _put('/users/me/profile-pic', {'coverPic': null}, auth: true);

  Future<List<ProfilePhoto>> getMyPhotos() async {
    final json = await _get('/users/me/photos', auth: true);
    return listOf(json['photos'], ProfilePhoto.fromJson);
  }

  Future<List<AppNotification>> getNotifications() async {
    final json = await _get('/notifications', auth: true);
    return listOf(json['notifications'], AppNotification.fromJson);
  }

  Future<FeedItem> getFeedItem(String postId) async {
    final json = await _get('/feed/post/$postId');
    return FeedItem.fromJson(asMap(json['item']));
  }

  Future<int> getUnreadNotificationCount() async {
    final json = await _get('/notifications/unread-count', auth: true);
    return asInt(json['count']);
  }

  Future<void> markNotificationRead(String id) async =>
      _post('/notifications/$id/read', {}, auth: true);

  Future<void> markAllNotificationsRead() async =>
      _post('/notifications/read-all', {}, auth: true);

  Future<ProfilePhoto> uploadPhoto(String imageBase64,
      {String caption = ''}) async {
    final json = await _post(
        '/users/me/photos', {'image': imageBase64, 'caption': caption},
        auth: true);
    return ProfilePhoto.fromJson(asMap(json['photo']));
  }

  Future<void> deletePhoto(String photoId) async =>
      _deleteVoid('/users/me/photos/$photoId', auth: true);

  Future<List<Booking>> getMyBookings() async {
    final json = await _get('/bookings', auth: true);
    return listOf(json['bookings'], Booking.fromJson)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Booking>> getAllBookings() async {
    final json = await _get('/admin/bookings', auth: true);
    return listOf(json['bookings'], Booking.fromJson)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createBooking(BookingPayload payload) async =>
      _post('/bookings', payload.toJson(), auth: true);

  Future<void> updateBookingStatus(String bookingId, String status,
          {String? cancellationReason}) async =>
      _patch(
          '/bookings/$bookingId/status',
          {
            'status': status,
            if (cancellationReason != null && cancellationReason.isNotEmpty)
              'cancellationReason': cancellationReason,
          },
          auth: true);

  Future<void> rescheduleBooking(String bookingId, DateTime scheduledAt,
          String rescheduleNote) async =>
      _patch(
          '/bookings/$bookingId/reschedule',
          {
            'scheduledAt': scheduledAt.toUtc().toIso8601String(),
            'rescheduleNote': rescheduleNote,
          },
          auth: true);

  Future<void> repostBooking(String bookingId, JobPostPayload payload) async =>
      _post('/bookings/$bookingId/repost', payload.toJson(), auth: true);

  Future<void> deleteBooking(String bookingId) async =>
      _deleteVoid('/bookings/$bookingId', auth: true);

  Future<List<Conversation>> getMyConversations({String search = ''}) async {
    final json = await _get('/inquiries',
        auth: true, query: search.isNotEmpty ? {'q': search} : {});
    return listOf(json['conversations'], Conversation.fromJson);
  }

  Future<List<ConversationMessage>> getConversationMessages(
      String conversationId) async {
    final json = await _get('/inquiries/$conversationId/messages', auth: true);
    return listOf(json['messages'], ConversationMessage.fromJson);
  }

  Future<ConversationMessage> sendConversationMessage(
      String conversationId, String message,
      {String? image,
      String? voiceMessage,
      int? voiceDuration,
      String? replyToMessageId,
      String? forwardedFromMessageId}) async {
    final json = await _post(
        '/inquiries/$conversationId/messages',
        {
          'message': message,
          if (image != null) 'image': image,
          if (voiceMessage != null) 'voiceMessage': voiceMessage,
          if (voiceDuration != null) 'voiceDuration': voiceDuration,
          if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
          if (forwardedFromMessageId != null)
            'forwardedFromMessageId': forwardedFromMessageId,
        },
        auth: true);
    return ConversationMessage.fromJson(asMap(json['message']));
  }

  Future<void> deleteConversationMessage(
          String conversationId, String messageId) async =>
      _deleteVoid('/inquiries/$conversationId/messages/$messageId', auth: true);

  Future<ConversationMessage> editConversationMessage(
      String conversationId, String messageId, String message) async {
    final json = await _patch(
        '/inquiries/$conversationId/messages/$messageId', {'message': message},
        auth: true);
    return ConversationMessage.fromJson(asMap(json['message']));
  }

  Future<void> deleteConversation(String conversationId) async =>
      _deleteVoid('/inquiries/$conversationId', auth: true);

  Future<List<ConversationNickname>> getConversationNicknames(
      String conversationId) async {
    final json = await _get('/inquiries/$conversationId/nicknames', auth: true);
    return listOf(json['nicknames'], ConversationNickname.fromJson);
  }

  Future<ConversationNickname?> setConversationNickname(
      String conversationId, String targetUserId, String nickname) async {
    final json = await _put('/inquiries/$conversationId/nicknames',
        {'targetUserId': targetUserId, 'nickname': nickname},
        auth: true);
    final raw = json['nickname'];
    return raw == null ? null : ConversationNickname.fromJson(asMap(raw));
  }

  Future<void> deleteConversationNickname(
          String conversationId, String targetUserId) async =>
      _deleteVoid('/inquiries/$conversationId/nicknames/$targetUserId',
          auth: true);

  Future<Map<String, dynamic>> startInquiry(
    String providerUserId,
    String initialMessage, {
    String? serviceListingId,
    String? bookingId,
  }) async {
    final json = await _post(
        '/inquiries',
        {
          'providerUserId': providerUserId,
          if (serviceListingId != null) 'serviceListingId': serviceListingId,
          if (bookingId != null) 'bookingId': bookingId,
          'initialMessage': initialMessage,
        },
        auth: true);
    return asMap(json['conversation']);
  }

  Future<List<JobPost>> getJobs({String? status}) async {
    final json = await _get('/jobs',
        auth: true, query: {if (status != null) 'status': status});
    return listOf(json['jobs'], JobPost.fromJson);
  }

  Future<void> createJobPost(JobPostPayload payload) async =>
      _post('/jobs', payload.toJson(), auth: true);

  Future<void> upsertProviderProfile(ProviderProfilePayload payload) async =>
      _post('/providers', payload.toJson(), auth: true);

  Future<void> createServiceListing(ServiceListingPayload payload) async =>
      _post('/services', payload.toJson(), auth: true);

  Future<List<SessionUser>> getAdminProviders() async {
    final json = await _get('/admin/providers', auth: true);
    return listOf(json['providers'], SessionUser.fromJson);
  }

  Future<AdminSummary> getAdminSummary() async {
    final json = await _get('/admin/summary', auth: true);
    return AdminSummary.fromJson(asMap(json['summary']));
  }

  Future<List<SessionUser>> getAdminUsers({String search = ''}) async {
    final json = await _get('/admin/users',
        auth: true,
        query: {if (search.trim().isNotEmpty) 'search': search.trim()});
    return listOf(json['users'], SessionUser.fromJson);
  }

  Future<void> updateAdminUserStatus(String userId, String status) async =>
      _patch('/admin/users/$userId/status', {'status': status}, auth: true);

  Future<void> updateProviderApproval(String userId, String status) async =>
      _patch('/admin/providers/$userId/status', {'status': status}, auth: true);

  Future<List<ReportItem>> getReports() async {
    final json = await _get('/admin/reports', auth: true);
    return listOf(json['reports'], ReportItem.fromJson);
  }

  Future<void> updateReportStatus(String reportId, String status) async =>
      _patch('/admin/reports/$reportId', {'status': status}, auth: true);

  Future<List<SocialPost>> getAdminPosts() async {
    final json = await _get('/admin/posts', auth: true);
    return listOf(json['posts'], SocialPost.fromJson);
  }

  Future<void> deleteAdminPost(String postId, {String? reason}) async =>
      _deleteVoid(
        '/admin/posts/$postId',
        auth: true,
        body: {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

  Future<List<ReviewItem>> getAdminReviews() async {
    final json = await _get('/admin/reviews', auth: true);
    return listOf(json['reviews'], ReviewItem.fromJson);
  }

  Future<void> deleteAdminReview(String reviewId) async =>
      _deleteVoid('/admin/reviews/$reviewId', auth: true);

  Future<List<ServiceCategory>> getAdminCategories() async {
    final json = await _get('/admin/categories', auth: true);
    return listOf(json['categories'], ServiceCategory.fromJson);
  }

  Future<void> createCategory({
    required String name,
    required String description,
    required String icon,
  }) async =>
      _post('/admin/categories',
          {'name': name, 'description': description, 'icon': icon},
          auth: true);

  Future<void> updateCategory(String id, {required bool active}) async =>
      _patch('/admin/categories/$id', {'active': active}, auth: true);

  Future<List<Map<String, dynamic>>> getAdminListings() async {
    final json = await _get('/admin/service-listings', auth: true);
    return List<Map<String, dynamic>>.from(json['listings'] as List? ?? []);
  }

  Future<void> deleteAdminListing(String listingId) async =>
      _deleteVoid('/admin/service-listings/$listingId', auth: true);

  Future<void> deleteAdminJob(String jobId) async =>
      _deleteVoid('/admin/jobs/$jobId', auth: true);

  Future<({JobPost jobPost, List<JobOffer> offers})> getJobDetail(
      String jobPostId) async {
    final json = await _get('/jobs/$jobPostId', auth: true);
    return (
      jobPost: JobPost.fromJson(asMap(json['jobPost'])),
      offers: listOf(json['offers'], JobOffer.fromJson),
    );
  }

  Future<List<JobOffer>> getMyOffers() async {
    final json = await _get('/jobs/offers/mine', auth: true);
    return listOf(json['offers'], JobOffer.fromJson);
  }

  Future<void> sendJobOffer(String jobPostId, String message,
          {int? proposedPrice}) async =>
      _post(
          '/jobs/$jobPostId/offers',
          {
            'message': message,
            if (proposedPrice != null) 'proposedPrice': proposedPrice,
            'media': [],
          },
          auth: true);

  Future<void> acceptJobOffer(String jobPostId, String offerId) async =>
      _patch('/jobs/$jobPostId/offers/$offerId/accept', {}, auth: true);

  Future<void> declineJobOffer(String jobPostId, String offerId) async =>
      _patch('/jobs/$jobPostId/offers/$offerId/decline', {}, auth: true);

  Future<void> updateJobPost(String jobPostId, JobPostPayload payload) async =>
      _put('/jobs/$jobPostId', payload.toJson(), auth: true);

  Future<void> deleteJobPost(String jobPostId) async =>
      _deleteVoid('/jobs/$jobPostId', auth: true);

  Future<void> reopenJobPost(String jobPostId) async =>
      _patch('/jobs/$jobPostId/reopen', {}, auth: true);

  Future<ProviderDetail> getProviderDetail(String providerUserId) async {
    final json = await _get('/providers/$providerUserId');
    return ProviderDetail.fromJson(json);
  }

  Future<List<ProviderDetail>> searchProviders({
    String? category,
    String? municipality,
    String? service,
  }) async {
    final json = await _get('/providers/search', query: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (municipality != null && municipality.isNotEmpty)
        'municipality': municipality,
      if (service != null && service.isNotEmpty) 'service': service,
    });
    return listOf(json['providers'], ProviderDetail.fromJson);
  }

  Future<List<ServiceListing>> searchServiceListings({
    String? category,
    String? municipality,
    String? keyword,
  }) async {
    final json = await _get('/services', query: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (municipality != null && municipality.isNotEmpty)
        'municipality': municipality,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
    });
    return listOf(json['listings'], ServiceListing.fromJson);
  }

  Future<void> submitReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) async =>
      _post(
          '/reviews',
          {
            'bookingId': bookingId,
            'rating': rating,
            if (comment != null && comment.isNotEmpty) 'comment': comment,
          },
          auth: true);

  Future<List<ReviewItem>> getProviderReviews(String providerUserId) async {
    final json = await _get('/reviews/provider/$providerUserId');
    return listOf(json['reviews'], ReviewItem.fromJson);
  }

  Future<List<ReviewItem>> getUserReviews(String userId) async {
    final json = await _get('/reviews/user/$userId');
    return listOf(json['reviews'], ReviewItem.fromJson);
  }

  Future<void> submitReport({
    String? providerUserId,
    String? bookingId,
    String? contentType,
    String? contentId,
    required String reason,
    required String details,
  }) async =>
      _post(
          '/reports',
          {
            if (providerUserId != null) 'providerUserId': providerUserId,
            if (bookingId != null) 'bookingId': bookingId,
            if (contentType != null) 'contentType': contentType,
            if (contentId != null) 'contentId': contentId,
            'reason': reason,
            'details': details,
          },
          auth: true);

  Future<List<String>> getCategories() async {
    final json = await _get('/categories');
    return listOf(json['categories'], (m) => m['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchGifs(String query) async {
    final json = await _get('/media/gifs/search', query: {'q': query});
    return listOf(json['gifs'], (m) => m);
  }

  Future<List<Map<String, dynamic>>> searchLocations(String query) async {
    final json = await _get('/media/locations/search', query: {'q': query});
    return listOf(json['locations'], (m) => m);
  }

  Future<List<Map<String, dynamic>>> searchMusic(String query) async {
    final json = await _get('/media/music/search', query: {'q': query});
    return listOf(json['tracks'], (m) => m);
  }

  /// Uploads a file (base64 string) directly to Cloudinary and returns the URL.
  /// Falls back to returning the base64 as-is if Cloudinary is not configured.
  Future<String> uploadToCloudinary(
      String base64Data, String resourceType) async {
    try {
      final sig = await _get('/media/cloudinary-signature', auth: true);
      final cloudName = sig['cloudName'] as String;
      final apiKey = sig['apiKey'] as String;
      final timestamp = sig['timestamp'] as String;
      final folder = sig['folder'] as String;
      final signature = sig['signature'] as String;

      final mime = resourceType == 'video' ? 'video/mp4' : 'image/jpeg';
      final dataUri = base64Data.startsWith('data:')
          ? base64Data
          : 'data:$mime;base64,$base64Data';

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload'),
      );
      request.fields['api_key'] = apiKey;
      request.fields['timestamp'] = timestamp;
      request.fields['folder'] = folder;
      request.fields['signature'] = signature;
      final bytes = base64Decode(
          dataUri.contains(',') ? dataUri.split(',').last : dataUri);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: resourceType == 'video' ? 'upload.mp4' : 'upload.jpg',
      ));

      final streamed = await request.send().timeout(const Duration(minutes: 5));
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (streamed.statusCode >= 400) return base64Data;
      return json['secure_url'] as String? ?? base64Data;
    } catch (_) {
      return base64Data;
    }
  }

  /// Uploads a video file directly from its path to Cloudinary.
  /// More efficient than [uploadToCloudinary] for videos — streams from disk
  /// rather than loading all bytes into memory.
  Future<String> uploadFileToCloudinary(
      String filePath, String resourceType) async {
    if (resourceType == 'video') {
      // Avoid long direct Cloudinary waits on mobile; backend will upload this.
      return _fileDataUri(filePath, resourceType);
    }
    try {
      final sig = await _get('/media/cloudinary-signature', auth: true);
      final cloudName = sig['cloudName'] as String;
      final apiKey = sig['apiKey'] as String;
      final timestamp = sig['timestamp'] as String;
      final folder = sig['folder'] as String;
      final signature = sig['signature'] as String;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload'),
      );
      request.fields['api_key'] = apiKey;
      request.fields['timestamp'] = timestamp;
      request.fields['folder'] = folder;
      request.fields['signature'] = signature;

      final multiFile = await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: resourceType == 'video' ? 'upload.mp4' : 'upload.jpg',
      );
      request.files.add(multiFile);

      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 400) {
        return _fileDataUri(filePath, resourceType);
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['secure_url'] as String? ??
          await _fileDataUri(filePath, resourceType);
    } catch (_) {
      return _fileDataUri(filePath, resourceType);
    }
  }

  Future<String> _fileDataUri(String filePath, String resourceType) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final mime = resourceType == 'video' ? 'video/mp4' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> searchStickers(String query) async {
    final json = await _get('/media/stickers/search', query: {'q': query});
    return listOf(json['stickers'], (m) => m);
  }

  Future<Map<String, dynamic>> createLiveKitToken(String room) async =>
      _post('/media/livekit/token', {'room': room}, auth: true);

  Future<String> aiChat(
    String message, {
    List<Map<String, dynamic>> history = const [],
  }) async {
    final json = await _post(
      '/ai/chat',
      {'message': message, 'history': history},
      auth: true,
    );
    return json['reply']?.toString() ?? 'No response.';
  }

  Future<String> aiAdminChat(
    String message, {
    List<Map<String, dynamic>> history = const [],
    String context = '',
  }) async {
    final json = await _post(
      '/ai/admin-chat',
      {'message': message, 'history': history, 'context': context},
      auth: true,
    );
    return json['reply']?.toString() ?? 'No response.';
  }

  Future<List<StoryItem>> getStories() async {
    final json = await _get('/stories');
    return listOf(json['stories'], StoryItem.fromJson);
  }

  Future<StoryItem> createStory({
    String body = '',
    String? image,
    String? video,
    Map<String, dynamic> metadata = const {},
    String privacy = 'Public',
  }) async {
    final json = await _post(
        '/stories',
        {
          'body': body,
          if (image != null) 'image': image,
          if (video != null) 'video': video,
          'metadata': metadata,
          'privacy': privacy,
        },
        auth: true);
    return StoryItem.fromJson(asMap(json['story']));
  }

  Future<void> viewStory(String storyId) async =>
      _post('/stories/$storyId/view', {}, auth: true);

  Future<List<Map<String, dynamic>>> getStoryViewers(String storyId) async {
    final json = await _get('/stories/$storyId/viewers', auth: true);
    return listOf(json['viewers'], (m) => m);
  }

  Future<void> reactToStory(String storyId, String reaction) async =>
      _post('/stories/$storyId/react', {'reaction': reaction}, auth: true);

  // HTTP helpers

  Future<Map<String, dynamic>> _get(
    String path, {
    bool auth = false,
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: query.isEmpty ? null : query);
    return _decode(await http.get(uri, headers: _headers(auth)));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async =>
      _decode(await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(auth),
        body: jsonEncode(body),
      ));

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async =>
      _decode(await http.patch(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(auth),
        body: jsonEncode(body),
      ));

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async =>
      _decode(await http.put(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(auth),
        body: jsonEncode(body),
      ));

  Future<void> _deleteVoid(String path,
      {bool auth = false, Map<String, dynamic>? body}) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(auth),
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _decode(response);
  }

  Future<Map<String, dynamic>> _delete2(String path,
      {bool auth = false}) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(auth),
    );
    return _decode(response);
  }

  Map<String, String> _headers(bool auth) => {
        'Content-Type': 'application/json',
        if (auth && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Server returned non-JSON (HTML error page, proxy page, etc.)
      throw Exception(
          'Server is not responding correctly (HTTP ${response.statusCode}). '
          'Make sure the backend server is running.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    final message = asMap(asMap(decoded['error'])['error'])['message'] ??
        asMap(decoded['error'])['message'] ??
        decoded['message'] ??
        'Request failed (${response.statusCode}).';
    throw Exception(message);
  }
}
