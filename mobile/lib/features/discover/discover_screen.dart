import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../notifications/notification_screen.dart';
import '../saved/saved_screen.dart';
import '../settings/help_screen.dart';
import 'feed_card.dart';
import 'user_profile_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen(
      {super.key,
      required this.api,
      required this.onLogout,
      this.readOnly = false});
  final MarketplaceApi api;
  final Future<void> Function() onLogout;
  final bool readOnly;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Feed state
  final _search = TextEditingController();
  var _items = <FeedItem>[];
  var _loading = true;
  var _message = '';
  Timer? _feedTimer;
  var _stories = <StoryItem>[];
  var _showSearch = false;

  // Notification state
  var _unreadCount = 0;
  Timer? _notifTimer;

  // User search state
  var _userResults = <UserSearchResult>[];
  var _userSearchLoading = false;
  Timer? _searchDebounce;

  // Feed category filter
  var _selectedCategory = 'All';

  var _loggingOut = false;

  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _loadStories();
    _feedTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadFeed(showSpinner: false);
      _loadStories();
    });
    if (widget.api.token.isNotEmpty) {
      _loadUnreadCount();
      _notifTimer = Timer.periodic(
          const Duration(seconds: 30), (_) => _loadUnreadCount());
    }
    _connectivitySub = SyncService.instance.onlineStream.listen((_) {
      if (SyncService.instance.isOnline) _loadFeed(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _feedTimer?.cancel();
    _notifTimer?.cancel();
    _searchDebounce?.cancel();
    _connectivitySub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    if (widget.api.token.isEmpty) return;
    try {
      final count = await widget.api.getUnreadNotificationCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  List<FeedItem> get _filtered {
    final keyword = _search.text.trim().toLowerCase();
    if (keyword.isEmpty) return _items;
    return _items.where((item) => item.searchText.contains(keyword)).toList();
  }

  List<FeedItem> get _categoryFiltered {
    final base = _filtered;
    switch (_selectedCategory) {
      case 'Posts':
        return base.where((i) => i.socialPost != null).toList();
      case 'Reviews':
        return base.where((i) => i.review != null).toList();
      default:
        return base;
    }
  }

  bool get _isSearching => _search.text.trim().isNotEmpty;

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _search.clear();
        _userResults = [];
      }
    });
  }

  Future<void> _loadFeed({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);

    if (!SyncService.instance.isOnline) {
      // Offline: load from local cache
      await _loadFeedFromCache();
      return;
    }

    try {
      final items = await widget.api.getFeed();
      if (!mounted) return;
      final socialItems = items
          .where((item) => item.socialPost != null || item.review != null)
          .toList();

      // If the API returned empty (e.g. backend DB unreachable), prefer cache
      // so previously loaded posts remain visible instead of "No posts yet."
      if (socialItems.isEmpty) {
        final fromCache = await _loadFeedFromCache(suppressSpinner: true);
        if (fromCache) return;
      }

      setState(() {
        _items = socialItems;
        _message = socialItems.isEmpty ? 'No posts yet.' : '';
        _loading = false;
      });
      // Cache successful results for offline use
      _cacheFeedInBackground(socialItems);
    } catch (error) {
      if (!mounted) return;
      // Network failed — fall back to cache
      final fromCache = await _loadFeedFromCache(suppressSpinner: true);
      if (!fromCache && mounted) {
        setState(() {
          _message = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  Future<bool> _loadFeedFromCache({bool suppressSpinner = false}) async {
    try {
      final cached = await LocalDb.instance.getCachedFeed();
      if (!mounted) return false;
      if (cached.isEmpty) {
        setState(() {
          _message = 'No cached posts. Connect to load the feed.';
          _loading = false;
        });
        return false;
      }
      final items = cached
          .map((json) {
            try {
              return FeedItem.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<FeedItem>()
          .toList();
      setState(() {
        _items = items;
        _message = '';
        _loading = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _cacheFeedInBackground(List<FeedItem> items) {
    final rawList = items
        .map((item) {
          try {
            // Reconstruct a minimal JSON representation keyed on id + type
            final base = <String, dynamic>{
              'id': item.id,
              'type': item.type,
              'createdAt': item.createdAt.millisecondsSinceEpoch,
              'likeCount': item.likeCount,
              'commentCount': item.commentCount,
              'isLiked': item.isLiked,
            };
            if (item.socialPost != null) {
              base['socialPost'] = _encodePost(item.socialPost!);
            }
            if (item.review != null) {
              base['review'] = {
                'id': item.review!.id,
                'rating': item.review!.rating,
                'comment': item.review!.comment,
                'providerName': item.review!.providerName,
                'reviewerName': item.review!.reviewerName,
              };
            }
            return base;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    LocalDb.instance.cacheFeedItems(rawList);
    LocalDb.instance.clearOldFeedCache();
  }

  Map<String, dynamic> _encodePost(SocialPost p) => {
        'id': p.id,
        'userId': p.userId,
        'fullName': p.fullName,
        'body': p.body,
        'privacy': p.privacy,
        'createdAt': p.createdAt.toIso8601String(),
        if (p.image != null) 'image': p.image,
        if (p.profilePic != null) 'profilePic': p.profilePic,
        'metadata': p.metadata,
        'likeCount': p.likeCount,
        'commentCount': p.commentCount,
      };

  Future<void> _loadStories() async {
    try {
      final stories = await widget.api.getStories();
      if (mounted) setState(() => _stories = stories);
    } catch (_) {}
  }

  Future<void> _refreshDiscover() async {
    await Future.wait([_loadFeed(), _loadStories()]);
  }

  void _onSearchChanged(String val) {
    setState(() {});
    _searchDebounce?.cancel();
    if (val.trim().length >= 2) {
      _searchDebounce = Timer(
          const Duration(milliseconds: 500), () => _runUserSearch(val.trim()));
    } else {
      setState(() => _userResults = []);
    }
  }

  Future<void> _runUserSearch(String q) async {
    setState(() => _userSearchLoading = true);
    try {
      final results = await widget.api.searchUsers(q);
      if (mounted) {
        setState(() {
          _userResults = results;
          _userSearchLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _userSearchLoading = false);
    }
  }

  void _openPostSheet() {
    if (widget.api.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to create a post.')));
      return;
    }
    final outerMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _PostComposeSheet(
        api: widget.api,
        onPosted: ({bool queued = false}) {
          _loadFeed();
          outerMessenger.showSnackBar(SnackBar(
            content: queued
                ? const Row(children: [
                    Icon(Icons.sync, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Post queued — will publish when online'),
                  ])
                : const Text('Post published!'),
            backgroundColor: queued ? Colors.orange : null,
            duration: const Duration(seconds: 3),
          ));
        },
      ),
    );
  }

  void _openStoryComposer() {
    if (widget.api.token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log in to add to My Day.')));
      return;
    }
    final outerMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StoryComposeSheet(
        api: widget.api,
        onPosted: ({bool queued = false}) {
          _loadStories();
          if (queued) {
            outerMessenger.showSnackBar(const SnackBar(
              content: Row(children: [
                Icon(Icons.sync, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('My Day queued — will post when online'),
              ]),
              backgroundColor: Colors.orange,
            ));
          }
        },
      ),
    );
  }

  // Stories grouped by userId, preserving insertion order of first story per user.
  List<List<StoryItem>> get _groupedStories {
    final map = <String, List<StoryItem>>{};
    for (final s in _stories) {
      (map[s.userId] ??= []).add(s);
    }
    return map.values.toList();
  }

  Future<void> _openStoryGroup(List<StoryItem> group, int initialIndex) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StoryViewer(
        api: widget.api,
        stories: group,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.api.storedUser;
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [appPrimary, appSecondary, Color(0xFFC8AAAA)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Avatar(label: user?.initials ?? '?'),
                  const SizedBox(height: 10),
                  Text(
                    user?.fullName ?? 'Guest',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                  if (user?.email != null)
                    Text(
                      user!.email,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('Saved'),
              subtitle: const Text('Your bookmarked posts'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const SavedScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              subtitle: const Text('How-to guide & FAQs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: _loggingOut
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.logout, color: Colors.red),
              title: Text(_loggingOut ? 'Logging out…' : 'Log Out',
                  style: TextStyle(
                      color: _loggingOut ? Colors.grey : Colors.red)),
              onTap: _loggingOut
                  ? null
                  : () async {
                      Navigator.pop(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _loggingOut = true);
                      try {
                        await widget.onLogout();
                      } catch (e) {
                        if (mounted) {
                          setState(() => _loggingOut = false);
                          messenger.showSnackBar(SnackBar(
                            content: Text(friendlyError(e)),
                            backgroundColor: Colors.red.shade700,
                          ));
                        }
                      }
                    },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu)),
        titleSpacing: 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            'assets/hanapgawa-wordmark.png',
            height: 34,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('HanapGawa'),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            tooltip: _showSearch ? 'Close search' : 'Search',
            onPressed: _toggleSearch,
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationScreen(api: widget.api),
                    ),
                  );
                  _loadUnreadCount();
                },
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search posts or people...',
                      suffixIcon: _search.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() => _userResults = []);
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton(
              onPressed: _openPostSheet,
              tooltip: 'Create post',
              child: const Icon(Icons.post_add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _message.isNotEmpty && !_isSearching
              ? EmptyState(
                  icon: Icons.newspaper_outlined,
                  title: _message,
                  action: OutlinedButton(
                      onPressed: _loadFeed, child: const Text('Retry')),
                )
              : _isSearching
                  ? _buildSearchResults()
                  : _buildFeed(),
    );
  }

  Widget _buildCategoryChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final cat in const ['All', 'Posts'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  selectedColor: appPrimary,
                  labelStyle: TextStyle(
                    color: _selectedCategory == cat
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _selectedCategory == cat
                        ? appPrimary
                        : Colors.grey.shade300,
                  ),
                  backgroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed() {
    final items = _categoryFiltered;
    final leadingCount = widget.readOnly ? 1 : 2;
    return RefreshIndicator(
      onRefresh: _refreshDiscover,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: items.length + leadingCount,
        itemBuilder: (context, index) {
          if (!widget.readOnly && index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 0, 4),
              child: _CircularStoryRow(
                groups: _groupedStories,
                onCreate: _openStoryComposer,
                onOpen: _openStoryGroup,
                userInitials: widget.api.storedUser?.initials ?? '?',
                myUserId: widget.api.storedUser?.id ?? '',
              ),
            );
          }
          if (index == leadingCount - 1) return _buildCategoryChips();
          final item = items[index - leadingCount];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FeedCard(
                item: item,
                api: widget.api,
                reload: _loadFeed,
                readOnly: widget.readOnly),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults() {
    final posts = _filtered;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_userSearchLoading) const LinearProgressIndicator(),
        if (_userResults.isNotEmpty) ...[
          _SectionHeader(label: 'People (${_userResults.length})'),
          ..._userResults.map((u) => _UserSearchTile(
                user: u,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => UserProfileScreen(
                        api: widget.api, userId: u.id, displayName: u.fullName),
                  ),
                ),
              )),
          const SizedBox(height: 8),
        ],
        _SectionHeader(label: 'Posts (${posts.length})'),
        if (posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
                icon: Icons.search_off_outlined, title: 'No matching posts'),
          )
        else
          ...posts.map((item) => FeedCard(
              item: item,
              api: widget.api,
              reload: _loadFeed,
              readOnly: widget.readOnly)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: appMuted, fontWeight: FontWeight.w700),
        ),
      );
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({required this.user, required this.onTap});
  final UserSearchResult user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(
          backgroundColor: appPrimary,
          child: Text(
            user.initials,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(user.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: const Icon(Icons.chevron_right, color: appMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

class _CircularStoryRow extends StatelessWidget {
  const _CircularStoryRow({
    required this.groups,
    required this.onCreate,
    required this.onOpen,
    required this.userInitials,
    required this.myUserId,
  });

  final List<List<StoryItem>> groups;
  final VoidCallback onCreate;
  final void Function(List<StoryItem> group, int index) onOpen;
  final String userInitials;
  final String myUserId;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: groups.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          padding: const EdgeInsets.only(right: 16),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _AddStoryCircle(initials: userInitials, onTap: onCreate);
            }
            final group = groups[index - 1];
            final isOwn = group.first.userId == myUserId;
            return _StoryCircle(
                group: group,
                isOwn: isOwn,
                onTap: () => onOpen(group, 0));
          },
        ),
      );
}

class _AddStoryCircle extends StatelessWidget {
  const _AddStoryCircle({required this.initials, required this.onTap});

  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: appBorder, width: 2),
                      color: appSurface,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: appPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                          color: appPrimary, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'My Day',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

class _StoryCircle extends StatelessWidget {
  const _StoryCircle(
      {required this.group, required this.isOwn, required this.onTap});

  final List<StoryItem> group;
  final bool isOwn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final story = group.first;
    final gif = story.metadata['gif']?.toString();

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [appPrimary, appSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2.5),
              child: ClipOval(
                child: Container(
                  color: Colors.white,
                  child: ClipOval(
                    child: story.image != null
                        ? Image.memory(base64Decode(story.image!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _StoryInitial(story.fullName))
                        : gif != null
                            ? Image.network(gif,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _StoryInitial(story.fullName))
                            : _StoryInitial(story.fullName),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              isOwn ? 'Your Story' : story.fullName.split(' ').first,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryInitial extends StatelessWidget {
  const _StoryInitial(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Container(
        color: appPrimary,
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
          ),
        ),
      );
}

class _StoryViewer extends StatefulWidget {
  const _StoryViewer({
    required this.api,
    required this.stories,
    this.initialIndex = 0,
  });

  final MarketplaceApi api;
  final List<StoryItem> stories;
  final int initialIndex;

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  late int _index;
  var _viewers = <Map<String, dynamic>>[];
  var _loadingViewers = false;
  String? _floatingReaction;
  final _player = AudioPlayer();

  StoryItem get _story => widget.stories[_index];
  bool get _isOwner => widget.api.storedUser?.id == _story.userId;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _markViewed();
    if (_isOwner) _loadViewers();
    _playStoryMusic();
  }

  void _playStoryMusic() {
    final url = _story.metadata['musicUrl']?.toString();
    if (url != null && url.isNotEmpty) {
      _player.play(UrlSource(url)).catchError((_) {});
    } else {
      _player.stop().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _markViewed() {
    if (widget.api.token.isNotEmpty && !_isOwner) {
      widget.api.viewStory(_story.id).catchError((_) {});
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.stories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _index = next;
      _viewers = [];
      _floatingReaction = null;
    });
    _markViewed();
    if (_isOwner) _loadViewers();
    _playStoryMusic();
  }

  Future<void> _loadViewers() async {
    setState(() => _loadingViewers = true);
    try {
      final viewers = await widget.api.getStoryViewers(_story.id);
      if (mounted) {
        setState(() {
          _viewers = viewers;
          _loadingViewers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingViewers = false);
    }
  }

  Future<void> _react(String reaction) async {
    if (widget.api.token.isEmpty || _isOwner) return;
    setState(() => _floatingReaction = reaction);
    await widget.api.reactToStory(_story.id, reaction);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (mounted) setState(() => _floatingReaction = null);
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final gif = story.metadata['gif']?.toString();
    final music = story.metadata['music']?.toString();
    final location = story.metadata['location']?.toString();
    final background = story.metadata['backgroundColor'] is int
        ? Color(story.metadata['backgroundColor'] as int)
        : appPrimary;
    final total = widget.stories.length;

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(children: [
          // Background
          Positioned.fill(
            child: Container(
              color: background,
              child: story.image != null
                  ? Image.memory(base64Decode(story.image!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  : gif != null
                      ? Image.network(gif,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink())
                      : null,
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          // Tap zones: left = previous, right = next
          Positioned.fill(
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _go(-1),
                  behavior: HitTestBehavior.translucent,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _go(1),
                  behavior: HitTestBehavior.translucent,
                ),
              ),
            ]),
          ),
          // Progress bars
          Positioned(
            top: 8,
            left: 12,
            right: 52,
            child: Row(
              children: List.generate(total, (i) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= _index
                          ? Colors.white
                          : Colors.white.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Header
          Positioned(
            top: 20,
            left: 16,
            right: 56,
            child: Row(children: [
              CircleAvatar(
                backgroundColor: appPrimary,
                child: Text(story.fullName.isEmpty ? '?' : story.fullName[0],
                    style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(story.fullName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    Text(timeAgo(story.createdAt),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              if (total > 1)
                Text('${_index + 1}/$total',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white)),
          ),
          // Story content
          Positioned(
            left: 24,
            right: 24,
            bottom: 92,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (story.body.isNotEmpty)
                Text(story.body,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
              if (location != null)
                _StoryMetaPill(icon: Icons.place_outlined, label: location),
              if (music != null)
                _StoryMetaPill(icon: Icons.music_note_outlined, label: music),
            ]),
          ),
          // Floating reaction animation
          if (_floatingReaction != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 86,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                builder: (_, value, child) => Opacity(
                  opacity: 1 - value,
                  child: Transform.translate(
                    offset: Offset(0, -42 * value),
                    child:
                        Transform.scale(scale: 1 + value * 0.7, child: child),
                  ),
                ),
                child: Text(_floatingReaction!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 54)),
              ),
            ),
          // Bottom strip
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _isOwner ? _buildViewerStrip() : _buildReactionStrip(),
          ),
        ]),
      ),
    );
  }

  Widget _buildReactionStrip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(230),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final reaction in const ['❤️', '😂', '😢', '😡', '👍', '😮'])
              InkWell(
                onTap: () => _react(reaction),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(reaction, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      );

  Widget _buildViewerStrip() => InkWell(
        onTap: _showViewers,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(230),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(children: [
            const Icon(Icons.visibility_outlined, color: appPrimary),
            const SizedBox(width: 8),
            Text(
                _loadingViewers
                    ? 'Loading viewers...'
                    : '${_viewers.length} viewers',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_up, color: appMuted),
          ]),
        ),
      );

  void _showViewers() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Story viewers',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_viewers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child:
                    Text('No viewers yet.', style: TextStyle(color: appMuted)),
              )
            else
              ..._viewers.map((viewer) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: appPrimary,
                      child: Text((viewer['fullName']?.toString() ?? '?')[0],
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(viewer['fullName']?.toString() ?? 'User'),
                    trailing: Text(viewer['reaction']?.toString() ?? ''),
                  )),
          ]),
        ),
      ),
    );
  }
}

class _StoryMetaPill extends StatelessWidget {
  const _StoryMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
          ),
        ]),
      );
}

class _LiveSearchSheet extends StatefulWidget {
  const _LiveSearchSheet({
    required this.title,
    required this.hint,
    required this.search,
    required this.titleFor,
    required this.subtitleFor,
    this.imageFor,
    this.icon = Icons.search,
  });

  final String title;
  final String hint;
  final Future<List<Map<String, dynamic>>> Function(String query) search;
  final String Function(Map<String, dynamic> item) titleFor;
  final String Function(Map<String, dynamic> item) subtitleFor;
  final String? Function(Map<String, dynamic> item)? imageFor;
  final IconData icon;

  @override
  State<_LiveSearchSheet> createState() => _LiveSearchSheetState();
}

class _LiveSearchSheetState extends State<_LiveSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _results = <Map<String, dynamic>>[];
  var _loading = false;
  var _message = 'Start typing to see suggestions.';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = [];
        _message = 'Type at least 2 characters.';
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _loading = true;
        _message = '';
      });
      try {
        final results = await widget.search(query);
        if (!mounted) return;
        setState(() {
          _results = results;
          _message = results.isEmpty ? 'No results found.' : '';
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results = [];
          _message = 'Could not load suggestions.';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 14,
              right: 14,
              bottom: 14 + MediaQuery.viewInsetsOf(context).bottom),
          child: Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: appPrimary.withAlpha(35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [appPrimary, appSecondary]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator(),
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child:
                      Text(_message, style: const TextStyle(color: appMuted)),
                ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final image = widget.imageFor?.call(item);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: image?.isNotEmpty == true
                            ? Image.network(image!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _SearchIcon(widget.icon))
                            : _SearchIcon(widget.icon),
                      ),
                      title: Text(widget.titleFor(item),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(widget.subtitleFor(item),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
}

class _SearchIcon extends StatelessWidget {
  const _SearchIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: appSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: appPrimary),
      );
}

class _StoryComposeSheet extends StatefulWidget {
  const _StoryComposeSheet({required this.api, required this.onPosted});

  final MarketplaceApi api;
  final void Function({bool queued}) onPosted;

  @override
  State<_StoryComposeSheet> createState() => _StoryComposeSheetState();
}

class _StoryComposeSheetState extends State<_StoryComposeSheet> {
  final _bodyCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String? _gif;
  String? _location;
  String? _music;
  String? _musicUrl;
  var _privacy = 'Public';
  var _backgroundColor = appPrimary;
  var _posting = false;
  String? _error;

  static const _paletteColors = [
    Color(0xFF7B2FF7),
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF1F2937),
  ];

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  Future<void> _addGif() async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveSearchSheet(
        title: 'Add GIF',
        hint: 'Search GIFs',
        search: widget.api.searchGifs,
        titleFor: (item) => item['title']?.toString() ?? 'GIF',
        subtitleFor: (_) => 'Tap to add to My Day',
        imageFor: (item) =>
            item['previewUrl']?.toString() ?? item['url']?.toString(),
      ),
    );
    if (item != null) setState(() => _gif = item['url']?.toString());
  }

  Future<void> _addLocation() async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveSearchSheet(
        title: 'Location',
        hint: 'Search a place',
        search: widget.api.searchLocations,
        titleFor: (item) => item['name']?.toString() ?? 'Location',
        subtitleFor: (item) => item['displayName']?.toString() ?? '',
        icon: Icons.place_outlined,
      ),
    );
    if (item != null) {
      setState(() => _location =
          item['displayName']?.toString() ?? item['name']?.toString());
    }
  }

  Future<void> _addMusic() async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveSearchSheet(
        title: 'Music',
        hint: 'Search songs or artists',
        search: widget.api.searchMusic,
        titleFor: (item) => item['title']?.toString() ?? 'Track',
        subtitleFor: (item) => item['artist']?.toString() ?? '',
        imageFor: (item) => item['imageUrl']?.toString(),
        icon: Icons.music_note_outlined,
      ),
    );
    if (item != null) {
      setState(() {
        _music = '${item['title'] ?? 'Track'} - ${item['artist'] ?? 'Artist'}';
        _musicUrl = item['previewUrl']?.toString();
      });
    }
  }

  Future<void> _submit() async {
    final text = _bodyCtrl.text.trim();
    if (text.isEmpty && _imageBytes == null && _gif == null) {
      setState(() => _error = 'Add text, photo, or GIF to your story.');
      return;
    }
    setState(() => _posting = true);
    final image = _imageBytes == null ? null : base64Encode(_imageBytes!);
    final metadata = <String, dynamic>{
      if (_gif != null) 'gif': _gif,
      if (_location != null) 'location': _location,
      if (_music != null) 'music': _music,
      if (_musicUrl != null) 'musicUrl': _musicUrl,
      'backgroundColor': _backgroundColor.value,
    };
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('create_story', {
        'body': text,
        if (image != null) 'image': image,
        'metadata': metadata,
        'privacy': _privacy,
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted(queued: true);
      return;
    }
    try {
      await widget.api.createStory(
        body: text,
        image: image,
        metadata: metadata,
        privacy: _privacy,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('create_story', {
          'body': text,
          if (image != null) 'image': image,
          'metadata': metadata,
          'privacy': _privacy,
        });
        if (!mounted) return;
        Navigator.pop(context);
        widget.onPosted(queued: true);
      } else {
        setState(() { _posting = false; _error = friendlyError(e); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _imageBytes != null || _gif != null;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ── Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create My Day',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        const Text(
                          'Visible to followers · Disappears in 24 hours',
                          style: TextStyle(color: appMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_posting)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Story preview canvas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 270,
                  width: double.infinity,
                  child: Stack(fit: StackFit.expand, children: [
                    // Background layer
                    if (_imageBytes != null)
                      Image.memory(_imageBytes!, fit: BoxFit.cover)
                    else if (_gif != null)
                      Image.network(_gif!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _GradientBg(_backgroundColor))
                    else
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _backgroundColor,
                              Color.lerp(_backgroundColor, Colors.black, 0.25)!,
                            ],
                          ),
                        ),
                      ),
                    // Gradient overlay for readability when media is shown
                    if (hasMedia)
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black38,
                              Colors.transparent,
                              Colors.black54,
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    // "My Day" badge top-left
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_stories_outlined,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 5),
                              Text('My Day',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ]),
                      ),
                    ),
                    // Remove image/gif button top-right
                    if (hasMedia)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _imageBytes = null;
                            _gif = null;
                          }),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    // Text input
                    if (!hasMedia)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                          child: TextField(
                            controller: _bodyCtrl,
                            maxLines: null,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              shadows: [
                                Shadow(color: Colors.black26, blurRadius: 8)
                              ],
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              fillColor: Colors.transparent,
                              filled: true,
                              hintText: "What's happening today?",
                              hintStyle: TextStyle(
                                  color: Colors.white60, fontSize: 18),
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        bottom: 12,
                        left: 14,
                        right: 14,
                        child: TextField(
                          controller: _bodyCtrl,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8)
                            ],
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            fillColor: Colors.transparent,
                            filled: true,
                            hintText: 'Add a caption...',
                            hintStyle: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            // ── Color palette (text-only mode)
            if (!hasMedia) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _paletteColors.map((color) {
                    final selected = _backgroundColor.value == color.value;
                    return GestureDetector(
                      onTap: () => setState(() => _backgroundColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: selected ? 34 : 28,
                        height: selected ? 34 : 28,
                        margin: EdgeInsets.symmetric(
                            horizontal: 5, vertical: selected ? 2 : 5),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                      color: color.withAlpha(120),
                                      blurRadius: 10,
                                      spreadRadius: 2)
                                ]
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            // ── Action chips
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _StoryChip(
                    icon: Icons.photo_outlined,
                    label: 'Photo',
                    color: Colors.blue,
                    onTap: _pickImage,
                  ),
                  const SizedBox(width: 8),
                  _StoryChip(
                    icon: Icons.gif_box_outlined,
                    label: 'GIF',
                    color: Colors.orange,
                    onTap: _addGif,
                  ),
                  const SizedBox(width: 8),
                  _StoryChip(
                    icon: Icons.place_outlined,
                    label: _location ?? 'Location',
                    color: Colors.red,
                    active: _location != null,
                    onTap: _addLocation,
                  ),
                  const SizedBox(width: 8),
                  _StoryChip(
                    icon: Icons.music_note_outlined,
                    label:
                        _music != null ? _music!.split(' - ').first : 'Music',
                    color: const Color(0xFF9C27B0),
                    active: _music != null,
                    onTap: _addMusic,
                  ),
                  const SizedBox(width: 8),
                  _StoryChip(
                    icon: _privacy == 'Public'
                        ? Icons.public
                        : Icons.lock_outline,
                    label: _privacy,
                    color: Colors.teal,
                    onTap: () => setState(() =>
                        _privacy = _privacy == 'Public' ? 'Only me' : 'Public'),
                  ),
                ],
              ),
            ),
            // ── Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ]),
              ),
            // ── Share button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [appPrimary, appSecondary]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: appPrimary.withAlpha(70),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _posting ? null : _submit,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_posting)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.auto_stories_outlined,
                                color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _posting ? 'Sharing...' : 'Share to My Day',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Post Compose Sheet ────────────────────────────────────────────────────────

class _PostComposeSheet extends StatefulWidget {
  const _PostComposeSheet({required this.api, required this.onPosted});
  final MarketplaceApi api;
  final void Function({bool queued}) onPosted;

  @override
  State<_PostComposeSheet> createState() => _PostComposeSheetState();
}

class _PostComposeSheetState extends State<_PostComposeSheet> {
  final _bodyCtrl = TextEditingController();
  Uint8List? _imageBytes;
  Uint8List? _videoBytes;
  var _privacy = 'Public';
  String? _feeling;
  String? _location;
  String? _gif;
  String? _music;
  String? _musicUrl;
  String? _sticker;
  Color? _backgroundColor;
  final _tags = <String>[];
  var _posting = false;
  String? _error;

  static const _feelings = [
    ('Happy', Icons.sentiment_satisfied_alt_outlined),
    ('Thankful', Icons.favorite_border),
    ('Available', Icons.handyman_outlined),
    ('Excited', Icons.celebration_outlined),
    ('Busy', Icons.schedule_outlined),
    ('Inspired', Icons.lightbulb_outline),
  ];
  static const _backgrounds = [
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFFDB2777),
  ];

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() => _videoBytes = bytes);
  }

  Future<void> _addTag() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TagPickerSheet(api: widget.api),
    );
    if (value?.isNotEmpty == true && mounted) setState(() => _tags.add(value!));
  }

  Future<void> _setFeeling() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('How are you feeling?',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final feeling in _feelings)
                  ChoiceChip(
                    avatar: Icon(feeling.$2, size: 18),
                    label: Text(feeling.$1),
                    selected: _feeling == feeling.$1,
                    onSelected: (_) => Navigator.pop(ctx, feeling.$1),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
    if (value?.isNotEmpty == true) setState(() => _feeling = value);
  }

  Future<void> _setLocation() async {
    final value = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Check in',
        hint: 'Search a place or city...',
        search: widget.api.searchLocations,
        loadDefaults: () => widget.api.searchLocations(''),
        label: (item) => item['name']?.toString() ?? 'Location',
        subtitle: (item) => item['displayName']?.toString(),
        leading: (_) => const Icon(Icons.place_outlined, color: appPrimary),
      ),
    );
    if (value != null && mounted) {
      setState(() => _location =
          value['displayName']?.toString() ?? value['name']?.toString());
    }
  }

  Future<void> _setGif() async {
    final value = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Add GIF',
        hint: 'Search GIFs...',
        search: widget.api.searchGifs,
        loadDefaults: () => widget.api.searchGifs('trending'),
        label: (item) => item['title']?.toString() ?? 'GIF',
        leading: (item) {
          final preview =
              item['previewUrl']?.toString() ?? item['url']?.toString();
          return preview == null
              ? const Icon(Icons.gif_box_outlined, color: appPrimary)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(preview,
                      width: 52, height: 52, fit: BoxFit.cover),
                );
        },
      ),
    );
    if (value != null && mounted) setState(() => _gif = value['url']?.toString());
  }

  Future<void> _setBackground() async {
    final color = await showModalBottomSheet<Color?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Choose background',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final bg in _backgrounds)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(ctx, bg),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [bg, Color.lerp(bg, Colors.black, 0.22)!]),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: _backgroundColor == bg
                              ? Colors.white
                              : Colors.transparent,
                          width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: bg.withAlpha(70),
                            blurRadius: 16,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.format_color_reset_outlined),
                label: const Text('Clear'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
          ]),
        ),
      ),
    );
    setState(() => _backgroundColor = color);
  }

  Future<void> _setMusic() async {
    final value = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Add music',
        hint: 'Search songs or artists...',
        search: widget.api.searchMusic,
        loadDefaults: () => widget.api.searchMusic(''),
        label: (item) => item['title']?.toString() ?? 'Track',
        subtitle: (item) => item['artist']?.toString(),
        leading: (item) {
          final image = item['imageUrl']?.toString();
          return image == null || image.isEmpty
              ? const Icon(Icons.music_note_outlined, color: appPrimary)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(image,
                      width: 52, height: 52, fit: BoxFit.cover),
                );
        },
      ),
    );
    if (value != null && mounted) {
      setState(() {
        _music = '${value['title']} - ${value['artist']}';
        _musicUrl = value['previewUrl']?.toString();
      });
    }
  }

  Future<void> _setSticker() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StickerPickerSheet(api: widget.api),
    );
    if (value != null && mounted) setState(() => _sticker = value);
  }

  Future<void> _setPrivacy() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final option in const [
            'Public',
            'Friends',
            'Friends except...',
            'Specific friends',
            'Only me'
          ])
            ListTile(
              leading: Icon(option == _privacy
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(option),
              onTap: () => Navigator.pop(ctx, option),
            ),
        ]),
      ),
    );
    if (value != null) setState(() => _privacy = value);
  }

  Map<String, dynamic> _metadata() => {
        if (_tags.isNotEmpty) 'tags': _tags,
        if (_feeling != null) 'feeling': _feeling,
        if (_location != null) 'location': _location,
        if (_gif != null) 'gif': _gif,
        if (_music != null) 'music': _music,
        if (_musicUrl != null) 'musicUrl': _musicUrl,
        if (_sticker != null) 'sticker': _sticker,
        if (_backgroundColor != null) 'backgroundColor': _backgroundColor!.value,
      };

  Future<void> _submit() async {
    final text = _bodyCtrl.text.trim();
    if (text.isEmpty && _imageBytes == null && _videoBytes == null) {
      setState(() => _error = 'Please write something or attach media.');
      return;
    }
    final metadata = _metadata();
    final image = _imageBytes != null ? base64Encode(_imageBytes!) : null;
    final video = _videoBytes != null ? base64Encode(_videoBytes!) : null;
    setState(() { _posting = true; _error = null; });

    Future<void> queueAndClose() async {
      await LocalDb.instance.queueAction('create_social_post', {
        'body': text,
        if (image != null) 'image': image,
        'privacy': _privacy,
        'metadata': metadata,
      });
      // Optimistic feed item so the post appears immediately from cache
      final user = widget.api.storedUser;
      final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      await LocalDb.instance.cacheFeedItems([{
        'id': tempId,
        'type': 'social_post',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'likeCount': 0, 'commentCount': 0, 'isLiked': false,
        'socialPost': {
          'id': tempId,
          'userId': user?.id ?? '',
          'fullName': user?.fullName ?? 'You',
          'body': text, 'privacy': _privacy,
          'createdAt': DateTime.now().toIso8601String(),
          if (image != null) 'image': image,
          'metadata': metadata,
          'likeCount': 0, 'commentCount': 0,
        },
      }]);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted(queued: true);
    }

    if (!SyncService.instance.isOnline) {
      await queueAndClose();
      return;
    }

    try {
      await widget.api.createSocialPost(
        text, image: image, video: video,
        metadata: metadata, privacy: _privacy,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPosted();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await queueAndClose();
      } else {
        setState(() { _posting = false; _error = friendlyError(e); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.api.storedUser;
    final charCount = _bodyCtrl.text.length;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(28),
                        blurRadius: 28,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                      child: Row(children: [
                        Avatar(label: user?.initials ?? '?', size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user?.fullName ?? 'You',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: appPrimary.withAlpha(25),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: appPrimary.withAlpha(70),
                                          width: 1),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.public,
                                              size: 11, color: appPrimary),
                                          const SizedBox(width: 3),
                                          Text(_privacy,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: appPrimary,
                                                  fontWeight: FontWeight.w700)),
                                        ]),
                                  ),
                                ]),
                              ]),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ]),
                    ),
                    if (_tags.isNotEmpty ||
                        _feeling != null ||
                        _location != null ||
                        _gif != null ||
                        _music != null ||
                        _sticker != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          ..._tags.map((tag) => Chip(
                                avatar: const Icon(Icons.person, size: 14),
                                label: Text(tag),
                                onDeleted: () => setState(() => _tags.remove(tag)),
                              )),
                          if (_feeling != null)
                            Chip(
                              label: Text(_feeling!),
                              onDeleted: () => setState(() => _feeling = null),
                            ),
                          if (_location != null)
                            Chip(
                              avatar: const Icon(Icons.place_outlined, size: 14),
                              label: Text(_location!),
                              onDeleted: () => setState(() => _location = null),
                            ),
                          if (_gif != null)
                            Chip(
                              avatar: const Icon(Icons.gif_box_outlined, size: 14),
                              label: const Text('GIF added'),
                              onDeleted: () => setState(() => _gif = null),
                            ),
                          if (_music != null)
                            Chip(
                              avatar: const Icon(Icons.music_note_outlined, size: 14),
                              label: Text(_music!, overflow: TextOverflow.ellipsis),
                              onDeleted: () => setState(() => _music = null),
                            ),
                          if (_sticker != null)
                            Chip(
                              avatar: _sticker!.startsWith('http')
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(_sticker!,
                                          width: 20, height: 20,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.sticky_note_2_outlined, size: 14)))
                                  : const Icon(Icons.sticky_note_2_outlined, size: 14),
                              label: const Text('Sticker'),
                              onDeleted: () => setState(() => _sticker = null),
                            ),
                        ]),
                      ),
                    // Text area
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: _backgroundColor == null
                              ? null
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _backgroundColor!,
                                    Color.lerp(
                                        _backgroundColor!, Colors.black, 0.28)!,
                                  ],
                                ),
                          color: _backgroundColor == null ? Colors.white : null,
                          border: _backgroundColor == null
                              ? Border.all(color: appBorder)
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _backgroundColor != null
                              ? [
                                  BoxShadow(
                                    color: _backgroundColor!.withAlpha(80),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _bodyCtrl,
                          onChanged: (_) => setState(() {}),
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: "What's on your mind?",
                            hintStyle: TextStyle(
                                color: _backgroundColor == null
                                    ? appMuted
                                    : Colors.white54),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: true,
                            fillColor: Colors.transparent,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                              fontSize: 15,
                              height: 1.45,
                              color: _backgroundColor == null
                                  ? null
                                  : Colors.white),
                        ),
                      ),
                    ),
                    // Image preview
                    if (_imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(_imageBytes!,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => setState(() => _imageBytes = null),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(5),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    if (_videoBytes != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: appSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: appBorder),
                          ),
                          child: Row(children: [
                            const Icon(Icons.play_circle_outline,
                                color: appPrimary),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Video attached (${(_videoBytes!.length / 1024 / 1024).toStringAsFixed(1)} MB)')),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _videoBytes = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ]),
                        ),
                      ),
                    // Inline error
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              size: 15, color: Colors.red),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                    color: Colors.red.shade700, fontSize: 13)),
                          ),
                        ]),
                      ),
                    // Bottom toolbar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        _ComposeChip(
                            icon: Icons.lock_open,
                            label: _privacy,
                            active: _privacy != 'Public',
                            onTap: _setPrivacy),
                        _ComposeChip(
                            icon: Icons.person_add_alt,
                            label: 'Tag',
                            active: _tags.isNotEmpty,
                            onTap: _addTag),
                        _ComposeChip(
                            icon: Icons.emoji_emotions_outlined,
                            label: 'Feeling',
                            active: _feeling != null,
                            onTap: _setFeeling),
                        _ComposeChip(
                            icon: Icons.place_outlined,
                            label: 'Check in',
                            active: _location != null,
                            onTap: _setLocation),
                        _ComposeChip(
                            icon: Icons.format_color_fill,
                            label: 'Background',
                            active: _backgroundColor != null,
                            onTap: _setBackground),
                        _ComposeChip(
                            icon: Icons.gif_box_outlined,
                            label: 'GIF',
                            active: _gif != null,
                            onTap: _setGif),
                        _ComposeChip(
                            icon: Icons.music_note_outlined,
                            label: 'Music',
                            active: _music != null,
                            onTap: _setMusic),
                        _ComposeChip(
                            icon: Icons.sticky_note_2_outlined,
                            label: 'Stickers',
                            active: _sticker != null,
                            onTap: _setSticker),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 12, 16),
                      child: Row(children: [
                        IconButton(
                          onPressed: _pickImage,
                          icon: Icon(
                              _imageBytes != null
                                  ? Icons.add_photo_alternate
                                  : Icons.add_photo_alternate_outlined,
                              color:
                                  _imageBytes != null ? appPrimary : appMuted),
                          tooltip: 'Attach photo',
                        ),
                        IconButton(
                          onPressed: _pickVideo,
                          icon: Icon(Icons.video_library_outlined,
                              color:
                                  _videoBytes != null ? appPrimary : appMuted),
                          tooltip: 'Attach video',
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: (_posting ||
                                  (charCount == 0 &&
                                      _imageBytes == null &&
                                      _videoBytes == null))
                              ? null
                              : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                          ),
                          child: _posting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Post',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeChip extends StatelessWidget {
  const _ComposeChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? appPrimary.withAlpha(24) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: active ? appPrimary.withAlpha(120) : appBorder),
            boxShadow: [
              BoxShadow(
                color: (active ? appPrimary : Colors.black)
                    .withAlpha(active ? 32 : 10),
                blurRadius: active ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: active ? appPrimary : appMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? appPrimary : const Color(0xFF261C2B),
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ]),
        ),
      );
}

class _GradientBg extends StatelessWidget {
  const _GradientBg(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.25)!],
          ),
        ),
      );
}

class _StoryChip extends StatelessWidget {
  const _StoryChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withAlpha(30) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: active ? color : Colors.grey.shade200,
              width: active ? 1.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: color.withAlpha(40),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [
                    BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: active ? color : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? color : Colors.grey.shade700,
              ),
            ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Reusable live-search picker sheet (loads defaults on open, then filters)
// ---------------------------------------------------------------------------
class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.hint,
    required this.search,
    required this.label,
    this.subtitle,
    this.leading,
    this.loadDefaults,
  });

  final String title;
  final String hint;
  final Future<List<Map<String, dynamic>>> Function(String query) search;
  final String Function(Map<String, dynamic> item) label;
  final String? Function(Map<String, dynamic> item)? subtitle;
  final Widget? Function(Map<String, dynamic> item)? leading;
  final Future<List<Map<String, dynamic>>> Function()? loadDefaults;

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final _ctrl = TextEditingController();
  var _results = <Map<String, dynamic>>[];
  var _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    if (widget.loadDefaults == null) return;
    setState(() => _loading = true);
    try {
      final r = await widget.loadDefaults!();
      if (mounted) setState(() { _results = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) { _loadDefaults(); return; }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      try {
        final found = await widget.search(value.trim());
        if (mounted) setState(() { _results = found; _loading = false; });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: false,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () { _ctrl.clear(); _loadDefaults(); setState(() {}); },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _onChanged,
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())
          else if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No results', style: TextStyle(color: appMuted)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return ListTile(
                    leading: widget.leading?.call(item),
                    title: Text(widget.label(item),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: widget.subtitle == null
                        ? null
                        : Text(widget.subtitle!(item) ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag-people picker: shows users, searches as you type
// ---------------------------------------------------------------------------
class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.api});
  final MarketplaceApi api;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final _ctrl = TextEditingController();
  var _results = <UserSearchResult>[];
  var _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('a'); // load first page of suggestions
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.searchUsers(q.isEmpty ? 'a' : q);
      if (mounted) setState(() { _results = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _search(value.trim().isEmpty ? 'a' : value.trim()));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Text('Tag people',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search for a person...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () { _ctrl.clear(); _search('a'); setState(() {}); },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _onChanged,
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final u = _results[i];
                  return ListTile(
                    leading: Avatar(label: u.initials),
                    title: Text(u.fullName),
                    onTap: () => Navigator.pop(context, u.fullName),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticker picker: loads trending Giphy stickers, searches as you type
// ---------------------------------------------------------------------------
class _StickerPickerSheet extends StatefulWidget {
  const _StickerPickerSheet({required this.api});
  final MarketplaceApi api;

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet> {
  final _ctrl = TextEditingController();
  var _results = <Map<String, dynamic>>[];
  var _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final r = await widget.api.searchStickers(q);
      if (mounted) setState(() { _results = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _fetch(value.trim()));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stickers',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search stickers...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            _fetch('');
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: _onChanged,
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(
                        child: Text('No stickers found',
                            style: TextStyle(color: appMuted)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final s = _results[i];
                          final url = (s['previewUrl'] ?? s['url'])?.toString() ?? '';
                          final fullUrl = s['url']?.toString() ?? '';
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, fullUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: url.isNotEmpty
                                  ? Image.network(url, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image))
                                  : const Icon(Icons.broken_image),
                            ),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
