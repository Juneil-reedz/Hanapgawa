import 'dart:convert';

import '../utils.dart';

class AuthResponse {
  AuthResponse({required this.token, required this.user});
  final String token;
  final SessionUser user;
  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: json['token']?.toString() ?? '',
        user: SessionUser.fromJson(asMap(json['user'])),
      );
}

class RegisterResponse {
  RegisterResponse({required this.user, this.devVerificationCode});
  final SessionUser user;
  final String? devVerificationCode;
  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      RegisterResponse(
        user: SessionUser.fromJson(asMap(json['user'])),
        devVerificationCode: json['devVerificationCode']?.toString(),
      );
}

class SessionUser {
  SessionUser({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.status,
    this.emailVerified = false,
    this.postCount = 0,
    this.reportCount = 0,
  });
  final String id;
  final String email;
  final String role;
  final String? fullName;
  final String? status;
  final bool emailVerified;
  final int postCount;
  final int reportCount;

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'client',
        fullName: json['fullName']?.toString(),
        status: json['status']?.toString(),
        emailVerified:
            json['emailVerified'] == true || json['emailVerifiedAt'] != null,
        postCount: asInt(json['postCount']) + asInt(json['socialPostCount']),
        reportCount: asInt(json['reportCount']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        if (fullName != null) 'fullName': fullName,
        if (status != null) 'status': status,
        'emailVerified': emailVerified,
        'postCount': postCount,
        'reportCount': reportCount,
      };

  String get initials {
    final name = (fullName?.isNotEmpty ?? false) ? fullName! : email;
    final first =
        name.split(' ').map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
    final char = first.isEmpty ? '?' : first[0];
    return char == '@' ? '?' : char;
  }
}

class AdminSummary {
  AdminSummary({
    required this.totalUsers,
    required this.verifiedUsers,
    required this.pendingVerifications,
    required this.activePosts,
    required this.completedJobs,
    required this.pendingReports,
    required this.suspendedUsers,
  });
  final int totalUsers;
  final int verifiedUsers;
  final int pendingVerifications;
  final int activePosts;
  final int completedJobs;
  final int pendingReports;
  final int suspendedUsers;

  factory AdminSummary.empty() => AdminSummary(
        totalUsers: 0,
        verifiedUsers: 0,
        pendingVerifications: 0,
        activePosts: 0,
        completedJobs: 0,
        pendingReports: 0,
        suspendedUsers: 0,
      );

  factory AdminSummary.fromJson(Map<String, dynamic> json) => AdminSummary(
        totalUsers: asInt(json['totalUsers']),
        verifiedUsers: asInt(json['verifiedUsers']),
        pendingVerifications: asInt(json['pendingVerifications']),
        activePosts: asInt(json['activePosts']),
        completedJobs: asInt(json['completedJobs']),
        pendingReports: asInt(json['pendingReports']),
        suspendedUsers: asInt(json['suspendedUsers']),
      );

  Map<String, dynamic> toJson() => {
        'totalUsers': totalUsers,
        'verifiedUsers': verifiedUsers,
        'pendingVerifications': pendingVerifications,
        'activePosts': activePosts,
        'completedJobs': completedJobs,
        'pendingReports': pendingReports,
        'suspendedUsers': suspendedUsers,
      };
}

class FeedItem {
  FeedItem({
    required this.type,
    required this.id,
    required this.createdAt,
    this.listing,
    this.job,
    this.review,
    this.socialPost,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
  });
  final String type;
  final String id;
  final DateTime createdAt;
  final ServiceListing? listing;
  final JobPost? job;
  final ReviewItem? review;
  final SocialPost? socialPost;
  final int likeCount;
  final int commentCount;
  final bool isLiked;

  String get searchText => [
        listing?.title,
        listing?.description,
        listing?.category,
        listing?.municipality,
        listing?.providerDisplayName,
        job?.title,
        job?.description,
        job?.category,
        job?.municipality,
        job?.clientFullName,
        review?.providerName,
        review?.comment,
        socialPost?.body,
        socialPost?.fullName,
      ].whereType<String>().join(' ').toLowerCase();

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        type: json['type']?.toString() ?? '',
        id: json['id']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
        listing: json['listing'] == null
            ? null
            : ServiceListing.fromJson(asMap(json['listing'])),
        job: json['job'] == null ? null : JobPost.fromJson(asMap(json['job'])),
        review: json['review'] == null
            ? null
            : ReviewItem.fromJson(asMap(json['review'])),
        socialPost: json['socialPost'] == null
            ? null
            : SocialPost.fromJson(asMap(json['socialPost'])),
        likeCount: asInt(json['likeCount']),
        commentCount: asInt(json['commentCount']),
        isLiked: json['isLiked'] == true,
      );
}

class PostComment {
  PostComment({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.body,
    required this.createdAt,
    this.parentCommentId,
    this.gifUrl,
    this.updatedAt,
    this.reactionCount = 0,
    this.isReacted = false,
  });
  final String id;
  final String userId;
  final String fullName;
  final String body;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? gifUrl;
  final DateTime? updatedAt;
  final int reactionCount;
  final bool isReacted;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'User',
        body: json['body']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
        parentCommentId: json['parentCommentId']?.toString(),
        gifUrl: json['gifUrl']?.toString(),
        updatedAt:
            json['updatedAt'] == null ? null : parseDate(json['updatedAt']),
        reactionCount: asInt(json['reactionCount']),
        isReacted: json['isReacted'] == true,
      );

  PostComment copyWith({
    String? body,
    DateTime? updatedAt,
    int? reactionCount,
    bool? isReacted,
  }) =>
      PostComment(
        id: id,
        userId: userId,
        fullName: fullName,
        body: body ?? this.body,
        createdAt: createdAt,
        parentCommentId: parentCommentId,
        gifUrl: gifUrl,
        updatedAt: updatedAt ?? this.updatedAt,
        reactionCount: reactionCount ?? this.reactionCount,
        isReacted: isReacted ?? this.isReacted,
      );
}

class UserSearchResult {
  UserSearchResult({
    required this.id,
    required this.fullName,
    required this.role,
    required this.status,
  });
  final String id;
  final String fullName;
  final String role;
  final String status;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        id: json['id']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'User',
        role: json['role']?.toString() ?? 'client',
        status: json['status']?.toString() ?? '',
      );

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  }
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.posts,
    required this.followerCount,
    required this.followingCount,
  });
  final String id;
  final String fullName;
  final String role;
  final String status;
  final DateTime createdAt;
  final List<JobPost> posts;
  final int followerCount;
  final int followingCount;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user'] ?? json);
    return UserProfile(
      id: user['id']?.toString() ?? '',
      fullName: user['fullName']?.toString() ?? 'User',
      role: user['role']?.toString() ?? 'client',
      status: user['status']?.toString() ?? '',
      createdAt: parseDate(user['createdAt']),
      posts: listOf(json['posts'], JobPost.fromJson),
      followerCount: asInt(json['followerCount']),
      followingCount: asInt(json['followingCount']),
    );
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  }
}

class SocialPost {
  SocialPost({
    required this.id,
    required this.userId,
    required this.fullName,
    this.profilePic,
    this.image,
    this.video,
    this.metadata = const {},
    this.privacy = 'Public',
    this.scheduledAt,
    required this.body,
    required this.createdAt,
    this.sharedFromType,
    this.sharedFromId,
    this.sharedSnapshot,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
  });
  final String id;
  final String userId;
  final String fullName;
  final String? profilePic;
  final String? image;
  final String? video;
  final Map<String, dynamic> metadata;
  final String privacy;
  final DateTime? scheduledAt;
  final String body;
  final DateTime createdAt;
  final String? sharedFromType;
  final String? sharedFromId;
  final Map<String, dynamic>? sharedSnapshot;
  final int likeCount;
  final int commentCount;
  final bool isLiked;

  factory SocialPost.fromJson(Map<String, dynamic> json) => SocialPost(
        id: json['id']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'User',
        profilePic: json['profilePic']?.toString(),
        image: json['image']?.toString(),
        video: json['video']?.toString(),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
        privacy: json['privacy']?.toString() ?? 'Public',
        scheduledAt:
            json['scheduledAt'] == null ? null : parseDate(json['scheduledAt']),
        body: json['body']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
        sharedFromType: json['sharedFromType']?.toString(),
        sharedFromId: json['sharedFromId']?.toString(),
        sharedSnapshot: json['sharedSnapshot'] is Map
            ? Map<String, dynamic>.from(json['sharedSnapshot'] as Map)
            : null,
        likeCount: asInt(json['likeCount']),
        commentCount: asInt(json['commentCount']),
        isLiked: json['isLiked'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'fullName': fullName,
        'profilePic': profilePic,
        'image': image,
        'video': video,
        'metadata': metadata,
        'privacy': privacy,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'sharedFromType': sharedFromType,
        'sharedFromId': sharedFromId,
        'sharedSnapshot': sharedSnapshot,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'isLiked': isLiked,
      };
}

class ProfilePhoto {
  ProfilePhoto({
    required this.id,
    required this.image,
    required this.createdAt,
    this.caption = '',
  });
  final String id;
  final String image;
  final String caption;
  final DateTime createdAt;

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) => ProfilePhoto(
        id: json['id']?.toString() ?? '',
        image: json['image']?.toString() ?? '',
        caption: json['caption']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
      );
}

class UserProfileData {
  UserProfileData({
    this.bio,
    this.address,
    this.school,
    this.birthday,
    this.work,
    this.currentCity,
    this.hometown,
    this.relationshipStatus,
    this.featured = const [],
    this.profilePic,
    this.coverPic,
  });
  final String? bio;
  final String? address;
  final String? school;
  final String? birthday;
  final String? work;
  final String? currentCity;
  final String? hometown;
  final String? relationshipStatus;
  final List<String> featured;
  final String? profilePic;
  final String? coverPic;

  factory UserProfileData.fromJson(Map<String, dynamic> json) {
    final profile = asMap(json['profileData'] ?? json);
    return UserProfileData(
      bio: profile['bio']?.toString(),
      address: profile['address']?.toString(),
      school: profile['school']?.toString(),
      birthday: profile['birthday']?.toString(),
      work: profile['work']?.toString(),
      currentCity: profile['currentCity']?.toString(),
      hometown: profile['hometown']?.toString(),
      relationshipStatus: profile['relationshipStatus']?.toString(),
      featured: (profile['featured'] is List)
          ? (profile['featured'] as List)
              .map((item) => item.toString())
              .toList()
          : const [],
      profilePic: profile['profilePic']?.toString(),
      coverPic: profile['coverPic']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bio': bio ?? '',
        'address': address ?? '',
        'school': school ?? '',
        'birthday': birthday ?? '',
        'work': work ?? '',
        'currentCity': currentCity ?? '',
        'hometown': hometown ?? '',
        'relationshipStatus': relationshipStatus ?? '',
        'featured': featured,
      };
}

class ServiceListing {
  ServiceListing({
    required this.id,
    required this.providerUserId,
    required this.providerRole,
    this.providerDisplayName,
    required this.title,
    required this.category,
    required this.municipality,
    required this.description,
    required this.priceMin,
    required this.priceMax,
    required this.requirements,
    this.allowDirectBooking = false,
  });
  final String id;
  final String providerUserId;
  final String providerRole;
  final String? providerDisplayName;
  final String title;
  final String category;
  final String municipality;
  final String description;
  final int priceMin;
  final int priceMax;
  final List<String> requirements;
  final bool allowDirectBooking;

  factory ServiceListing.fromJson(Map<String, dynamic> json) => ServiceListing(
        id: json['id']?.toString() ?? '',
        providerUserId: json['providerUserId']?.toString() ?? '',
        providerRole: json['providerRole']?.toString() ?? 'worker',
        providerDisplayName: json['providerDisplayName']?.toString(),
        title: json['title']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        municipality: json['municipality']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priceMin: asInt(json['priceMin']),
        priceMax: asInt(json['priceMax']),
        requirements: stringList(json['requirements']),
        allowDirectBooking: json['allowDirectBooking'] == true,
      );
}

class JobPost {
  JobPost({
    required this.id,
    required this.clientUserId,
    this.clientFullName,
    required this.postType,
    required this.title,
    required this.category,
    required this.municipality,
    required this.description,
    this.locationDetails,
    this.budgetMin,
    this.budgetMax,
    this.scheduledAt,
    required this.status,
    required this.offerCount,
    this.pendingOfferCount = 0,
    required this.createdAt,
    this.allowDirectBooking = false,
  });
  final String id;
  final String clientUserId;
  final String? clientFullName;
  final String postType;
  final String title;
  final String category;
  final String municipality;
  final String description;
  final String? locationDetails;
  final int? budgetMin;
  final int? budgetMax;
  final DateTime? scheduledAt;
  final String status;
  final int offerCount;
  final int pendingOfferCount;
  final DateTime createdAt;
  final bool allowDirectBooking;

  factory JobPost.fromJson(Map<String, dynamic> json) => JobPost(
        id: json['id']?.toString() ?? '',
        clientUserId: json['clientUserId']?.toString() ?? '',
        clientFullName: json['clientFullName']?.toString(),
        postType: json['postType']?.toString() ?? 'looking_for_worker',
        title: json['title']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        municipality: json['municipality']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        locationDetails: json['locationDetails']?.toString(),
        budgetMin: nullableInt(json['budgetMin']),
        budgetMax: nullableInt(json['budgetMax']),
        scheduledAt: json['scheduledAt'] == null
            ? null
            : DateTime.tryParse(json['scheduledAt'].toString()),
        status: json['status']?.toString() ?? 'open',
        offerCount: asInt(json['offerCount']),
        pendingOfferCount: asInt(json['pendingOfferCount']),
        createdAt: parseDate(json['createdAt']),
        allowDirectBooking: json['allowDirectBooking'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientUserId': clientUserId,
        'clientFullName': clientFullName,
        'postType': postType,
        'title': title,
        'category': category,
        'municipality': municipality,
        'description': description,
        'locationDetails': locationDetails,
        'budgetMin': budgetMin,
        'budgetMax': budgetMax,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'status': status,
        'offerCount': offerCount,
        'pendingOfferCount': pendingOfferCount,
        'createdAt': createdAt.toIso8601String(),
        'allowDirectBooking': allowDirectBooking,
      };
}

class ReviewItem {
  ReviewItem({
    this.id,
    required this.rating,
    this.comment,
    this.providerName,
    this.reviewerName,
    this.bookingId,
    this.reviewedName,
  });
  final String? id;
  final int rating;
  final String? comment;
  final String? providerName;
  final String? reviewerName;
  final String? bookingId;
  final String? reviewedName;
  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
        id: json['id']?.toString(),
        rating: asInt(json['rating']),
        comment: json['comment']?.toString(),
        providerName: json['providerName']?.toString(),
        reviewerName: json['reviewerName']?.toString(),
        bookingId: json['bookingId']?.toString(),
        reviewedName: json['reviewedName']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rating': rating,
        'comment': comment,
        'providerName': providerName,
        'reviewerName': reviewerName,
        'bookingId': bookingId,
        'reviewedName': reviewedName,
      };
}

class Booking {
  Booking({
    required this.id,
    required this.clientUserId,
    required this.providerUserId,
    String? workerUserId,
    this.clientName,
    this.providerName,
    String? workerName,
    this.serviceListingId,
    this.jobPostId,
    required this.serviceCategory,
    required this.municipality,
    required this.locationDetails,
    required this.notes,
    this.scheduledAt,
    this.rescheduleNote,
    this.rescheduledAt,
    required this.status,
    this.repostedJobId,
    this.cancellationReason,
    required this.createdAt,
    this.fromOffer = false,
    String? source,
  })  : workerUserId = workerUserId ?? providerUserId,
        workerName = workerName ?? providerName,
        source = source ?? (fromOffer ? 'job_application' : 'direct_booking');
  final String id;
  final String clientUserId;
  final String providerUserId;
  final String workerUserId;
  final String? clientName;
  final String? providerName;
  final String? workerName;
  final String? serviceListingId;
  final String? jobPostId;
  final String serviceCategory;
  final String municipality;
  final String locationDetails;
  final String notes;
  final DateTime? scheduledAt;
  final String? rescheduleNote;
  final DateTime? rescheduledAt;
  final String status;
  final String? repostedJobId;
  final String? cancellationReason;
  final DateTime createdAt;
  final bool fromOffer;
  final String source;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id']?.toString() ?? '',
        clientUserId: json['clientUserId']?.toString() ?? '',
        providerUserId: json['providerUserId']?.toString() ?? '',
        workerUserId: json['workerUserId']?.toString(),
        clientName: json['clientName']?.toString(),
        providerName: json['providerName']?.toString(),
        workerName: json['workerName']?.toString(),
        serviceListingId: json['serviceListingId']?.toString(),
        jobPostId: json['jobPostId']?.toString(),
        serviceCategory: json['serviceCategory']?.toString() ?? '',
        municipality: json['municipality']?.toString() ?? '',
        locationDetails: json['locationDetails']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        scheduledAt:
            json['scheduledAt'] == null ? null : parseDate(json['scheduledAt']),
        rescheduleNote: json['rescheduleNote']?.toString(),
        rescheduledAt: json['rescheduledAt'] == null
            ? null
            : parseDate(json['rescheduledAt']),
        status: json['status']?.toString() ?? 'pending',
        repostedJobId: json['repostedJobId']?.toString(),
        cancellationReason: json['cancellationReason']?.toString(),
        createdAt: parseDate(json['createdAt']),
        fromOffer: json['fromOffer'] == true,
        source: json['source']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientUserId': clientUserId,
        'providerUserId': providerUserId,
        'workerUserId': workerUserId,
        'clientName': clientName,
        'providerName': providerName,
        'workerName': workerName,
        'serviceListingId': serviceListingId,
        'jobPostId': jobPostId,
        'serviceCategory': serviceCategory,
        'municipality': municipality,
        'locationDetails': locationDetails,
        'notes': notes,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'rescheduleNote': rescheduleNote,
        'rescheduledAt': rescheduledAt?.toIso8601String(),
        'status': status,
        'repostedJobId': repostedJobId,
        if (cancellationReason != null)
          'cancellationReason': cancellationReason,
        'fromOffer': fromOffer,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };
}

class Conversation {
  Conversation({
    required this.id,
    required this.clientUserId,
    this.clientName,
    required this.providerUserId,
    this.providerName,
    required this.lastMessagePreview,
    required this.updatedAt,
    this.lastSenderId,
    this.otherNickname,
  });
  final String id;
  final String clientUserId;
  final String? clientName;
  final String providerUserId;
  final String? providerName;
  final String lastMessagePreview;
  final DateTime updatedAt;
  final String? lastSenderId;
  final String? otherNickname;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id']?.toString() ?? '',
        clientUserId: json['clientUserId']?.toString() ?? '',
        clientName: json['clientName']?.toString(),
        providerUserId: json['providerUserId']?.toString() ?? '',
        providerName: json['providerName']?.toString(),
        lastMessagePreview: json['lastMessagePreview']?.toString() ?? '',
        updatedAt: parseDate(json['updatedAt']),
        lastSenderId: json['lastSenderId']?.toString(),
        otherNickname: json['otherNickname']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientUserId': clientUserId,
        'clientName': clientName,
        'providerUserId': providerUserId,
        'providerName': providerName,
        'lastMessagePreview': lastMessagePreview,
        'updatedAt': updatedAt.toIso8601String(),
        if (lastSenderId != null) 'lastSenderId': lastSenderId,
        if (otherNickname != null) 'otherNickname': otherNickname,
      };

  Conversation withOtherNickname(String? nickname) => Conversation(
        id: id,
        clientUserId: clientUserId,
        clientName: clientName,
        providerUserId: providerUserId,
        providerName: providerName,
        lastMessagePreview: lastMessagePreview,
        updatedAt: updatedAt,
        lastSenderId: lastSenderId,
        otherNickname: nickname,
      );
}

class ConversationNickname {
  ConversationNickname({
    required this.id,
    required this.conversationId,
    required this.targetUserId,
    required this.nickname,
    this.targetName,
    this.setByUserId,
  });
  final String id;
  final String conversationId;
  final String targetUserId;
  final String nickname;
  final String? targetName;
  final String? setByUserId;

  factory ConversationNickname.fromJson(Map<String, dynamic> json) =>
      ConversationNickname(
        id: json['id']?.toString() ?? '',
        conversationId: json['conversationId']?.toString() ?? '',
        targetUserId: json['targetUserId']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        targetName: json['targetName']?.toString(),
        setByUserId: json['setByUserId']?.toString(),
      );
}

class ConversationMessage {
  ConversationMessage({
    required this.id,
    required this.senderUserId,
    required this.message,
    required this.createdAt,
    this.image,
    this.voiceMessage,
    this.voiceDuration = 0,
    this.replyToMessageId,
    this.forwardedFromMessageId,
    this.isSystem = false,
  });
  final String id;
  final String senderUserId;
  final String message;
  final DateTime createdAt;
  final String? image;
  final String? voiceMessage;
  final int voiceDuration;
  final String? replyToMessageId;
  final String? forwardedFromMessageId;
  final bool isSystem;

  factory ConversationMessage.fromJson(Map<String, dynamic> json) =>
      ConversationMessage(
        id: json['id']?.toString() ?? '',
        senderUserId: json['senderUserId']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
        image: json['image']?.toString(),
        voiceMessage: json['voiceMessage']?.toString(),
        voiceDuration: asInt(json['voiceDuration']),
        replyToMessageId: json['replyToMessageId']?.toString(),
        forwardedFromMessageId: json['forwardedFromMessageId']?.toString(),
        isSystem: json['isSystem'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderUserId': senderUserId,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        if (image != null) 'image': image,
        if (voiceMessage != null) 'voiceMessage': voiceMessage,
        'voiceDuration': voiceDuration,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (forwardedFromMessageId != null)
          'forwardedFromMessageId': forwardedFromMessageId,
        'isSystem': isSystem,
      };
}

class StoryItem {
  StoryItem({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    this.profilePic,
    this.image,
    this.video,
    this.metadata = const {},
    this.privacy = 'Public',
    this.viewedByMe = false,
  });
  final String id;
  final String userId;
  final String fullName;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? profilePic;
  final String? image;
  final String? video;
  final Map<String, dynamic> metadata;
  final String privacy;
  final bool viewedByMe;

  factory StoryItem.fromJson(Map<String, dynamic> json) => StoryItem(
        id: json['id']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'User',
        body: json['body']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
        expiresAt: parseDate(json['expiresAt']),
        profilePic: json['profilePic']?.toString(),
        image: json['image']?.toString(),
        video: json['video']?.toString(),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : json['metadata'] is String
                ? _parseMetadataString(json['metadata'] as String)
                : const {},
        privacy: json['privacy']?.toString() ?? 'Public',
        viewedByMe: json['viewedByMe'] == true,
      );
}

Map<String, dynamic> _parseMetadataString(String s) {
  try {
    final decoded = jsonDecode(s);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}

class ReportItem {
  ReportItem({
    required this.id,
    required this.reason,
    required this.details,
    required this.status,
    this.reporterUserId,
    this.reporterName,
    this.providerUserId,
    this.bookingId,
    this.contentType,
    this.contentId,
    this.reportedContent,
  });
  final String id;
  final String reason;
  final String details;
  final String status;
  final String? reporterUserId;
  final String? reporterName;
  final String? providerUserId;
  final String? bookingId;
  final String? contentType;
  final String? contentId;
  final Map<String, dynamic>? reportedContent;
  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        id: json['id']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        reporterUserId: json['reporterUserId']?.toString(),
        reporterName: json['reporterName']?.toString(),
        providerUserId: json['providerUserId']?.toString(),
        bookingId: json['bookingId']?.toString(),
        contentType: json['contentType']?.toString(),
        contentId: json['contentId']?.toString(),
        reportedContent: json['reportedContent'] is Map
            ? Map<String, dynamic>.from(json['reportedContent'] as Map)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'reason': reason,
        'details': details,
        'status': status,
        'reporterUserId': reporterUserId,
        'reporterName': reporterName,
        'providerUserId': providerUserId,
        'bookingId': bookingId,
        'contentType': contentType,
        'contentId': contentId,
        if (reportedContent != null) 'reportedContent': reportedContent,
      };
}

class ServiceCategory {
  ServiceCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.active,
  });
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool active;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) =>
      ServiceCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        icon: json['icon']?.toString() ?? 'briefcase-outline',
        active: json['active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'active': active,
      };
}

class JobOffer {
  JobOffer({
    required this.id,
    required this.jobPostId,
    required this.providerUserId,
    this.providerName,
    required this.message,
    this.proposedPrice,
    required this.status,
    required this.createdAt,
    this.jobTitle,
    this.jobCategory,
    this.jobMunicipality,
  });
  final String id;
  final String jobPostId;
  final String providerUserId;
  final String? providerName;
  final String message;
  final int? proposedPrice;
  final String status;
  final DateTime createdAt;
  final String? jobTitle;
  final String? jobCategory;
  final String? jobMunicipality;

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
        id: json['id']?.toString() ?? '',
        jobPostId: json['jobPostId']?.toString() ?? '',
        providerUserId: json['providerUserId']?.toString() ?? '',
        providerName: json['providerName']?.toString(),
        message: json['message']?.toString() ?? '',
        proposedPrice: nullableInt(json['proposedPrice']),
        status: json['status']?.toString() ?? 'pending',
        createdAt: parseDate(json['createdAt']),
        jobTitle: json['jobTitle']?.toString(),
        jobCategory: json['jobCategory']?.toString(),
        jobMunicipality: json['jobMunicipality']?.toString(),
      );
}

class ProviderDetail {
  ProviderDetail({
    required this.id,
    required this.providerUserId,
    this.displayName,
    this.fullName,
    this.email,
    required this.category,
    required this.municipality,
    required this.services,
    required this.listings,
    required this.reviews,
    this.approvalStatus,
  });
  final String id;
  final String providerUserId;
  final String? displayName;
  final String? fullName;
  final String? email;
  final String category;
  final String municipality;
  final List<String> services;
  final List<ServiceListing> listings;
  final List<ReviewItem> reviews;
  final String? approvalStatus;

  String get name => displayName ?? fullName ?? email ?? 'Provider';

  double get averageRating {
    if (reviews.isEmpty) return 0;
    return reviews.map((r) => r.rating).reduce((a, b) => a + b) /
        reviews.length;
  }

  factory ProviderDetail.fromJson(Map<String, dynamic> json) {
    final profile = asMap(json['profile'] ?? json);
    final user = asMap(json['user'] ?? json);
    return ProviderDetail(
      id: profile['id']?.toString() ?? '',
      providerUserId:
          profile['providerUserId']?.toString() ?? user['id']?.toString() ?? '',
      displayName: profile['displayName']?.toString(),
      fullName: user['fullName']?.toString(),
      email: user['email']?.toString(),
      category: profile['category']?.toString() ?? '',
      municipality: profile['municipality']?.toString() ?? '',
      services: stringList(profile['services']),
      listings: listOf(json['listings'], ServiceListing.fromJson),
      reviews: listOf(json['reviews'], ReviewItem.fromJson),
      approvalStatus: profile['approvalStatus']?.toString() ??
          profile['status']?.toString(),
    );
  }
}

// Payloads

class JobPostPayload {
  JobPostPayload({
    required this.postType,
    required this.title,
    required this.category,
    required this.municipality,
    required this.locationDetails,
    required this.description,
    this.budgetMin,
    this.budgetMax,
    this.allowDirectBooking = false,
  });
  final String postType;
  final String title;
  final String category;
  final String municipality;
  final String locationDetails;
  final String description;
  final int? budgetMin;
  final int? budgetMax;
  final bool allowDirectBooking;
  Map<String, dynamic> toJson() => {
        'postType': postType,
        'title': title,
        'category': category,
        'municipality': municipality,
        'locationDetails': locationDetails,
        'description': description,
        if (budgetMin != null) 'budgetMin': budgetMin,
        if (budgetMax != null) 'budgetMax': budgetMax,
        'allowDirectBooking': allowDirectBooking,
      };
}

class BookingTarget {
  BookingTarget({
    required this.providerUserId,
    this.serviceListingId,
    required this.category,
    required this.municipality,
    required this.title,
    this.displayName,
    this.allowDirectBooking = false,
  });
  final String providerUserId;
  final String? serviceListingId;
  final String category;
  final String municipality;
  final String title;
  final String? displayName;
  final bool allowDirectBooking;

  factory BookingTarget.fromListing(ServiceListing l) => BookingTarget(
        providerUserId: l.providerUserId,
        serviceListingId: l.id,
        category: l.category,
        municipality: l.municipality,
        title: l.title,
        displayName: l.providerDisplayName,
        allowDirectBooking: l.allowDirectBooking,
      );

  factory BookingTarget.fromJobPost(JobPost j) => BookingTarget(
        providerUserId: j.clientUserId,
        serviceListingId: j.id,
        category: j.category,
        municipality: j.municipality,
        title: j.title,
        displayName: j.clientFullName,
        allowDirectBooking: j.allowDirectBooking,
      );
}

class BookingPayload {
  BookingPayload({
    required this.providerUserId,
    this.serviceListingId,
    required this.serviceCategory,
    required this.municipality,
    required this.locationDetails,
    required this.notes,
    this.scheduledAt,
  });
  final String providerUserId;
  final String? serviceListingId;
  final String serviceCategory;
  final String municipality;
  final String locationDetails;
  final String notes;
  final DateTime? scheduledAt;
  Map<String, dynamic> toJson() => {
        'workerUserId': providerUserId,
        if (serviceListingId != null) 'serviceListingId': serviceListingId,
        'serviceCategory': serviceCategory,
        'municipality': municipality,
        'locationDetails': locationDetails,
        'notes': notes,
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
      };
}

class ProviderProfilePayload {
  ProviderProfilePayload({
    required this.displayName,
    required this.category,
    required this.municipality,
    required this.services,
  });
  final String displayName;
  final String category;
  final String municipality;
  final List<String> services;
  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'category': category,
        'municipality': municipality,
        'services': services,
        'portfolio': [],
      };
}

class ServiceListingPayload {
  ServiceListingPayload({
    required this.title,
    required this.category,
    required this.municipality,
    required this.description,
    required this.priceMin,
    required this.priceMax,
    required this.estimatedDuration,
    required this.requirements,
    required this.availability,
    this.allowDirectBooking = false,
  });
  final String title;
  final String category;
  final String municipality;
  final String description;
  final int priceMin;
  final int priceMax;
  final String estimatedDuration;
  final List<String> requirements;
  final List<String> availability;
  final bool allowDirectBooking;
  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'municipality': municipality,
        'description': description,
        'priceMin': priceMin,
        'priceMax': priceMax,
        'estimatedDuration': estimatedDuration,
        'requirements': requirements,
        'availability': availability,
        'media': [],
        'allowDirectBooking': allowDirectBooking,
      };
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.actorName,
    required this.title,
    required this.body,
    required this.createdAt,
    this.actorId,
    this.linkType,
    this.linkId,
    this.isRead = false,
  });
  final String id;
  final String type;
  final String? actorId;
  final String actorName;
  final String title;
  final String body;
  final String? linkType;
  final String? linkId;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        actorId: json['actorId']?.toString(),
        actorName: json['actorName']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        linkType: json['linkType']?.toString(),
        linkId: json['linkId']?.toString(),
        isRead: json['readAt'] != null,
        createdAt: parseDate(json['createdAt']),
      );
}
