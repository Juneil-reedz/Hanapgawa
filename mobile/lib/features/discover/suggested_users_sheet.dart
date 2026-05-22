import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/avatar.dart';

/// Full-screen onboarding "Who to Follow" page shown once after first login.
class SuggestedUsersOnboarding extends StatefulWidget {
  const SuggestedUsersOnboarding(
      {super.key, required this.api, required this.onDone});
  final MarketplaceApi api;
  final VoidCallback onDone;

  @override
  State<SuggestedUsersOnboarding> createState() =>
      _SuggestedUsersOnboardingState();
}

class _SuggestedUsersOnboardingState extends State<SuggestedUsersOnboarding> {
  List<UserSearchResult> _users = [];
  final Set<String> _followed = {};
  final Set<String> _following = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suggested = widget.api.getSuggestedUsers(limit: 20);
    final following = widget.api.getMyFollowing();
    final users = await suggested;
    final followingList = await following;
    if (!mounted) return;
    setState(() {
      _users = users;
      _followed.addAll(followingList.map((u) => u.id));
      _loading = false;
    });
  }

  Future<void> _toggle(UserSearchResult u) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.people_alt_outlined, size: 48, color: appPrimary),
            const SizedBox(height: 16),
            const Text('Who to Follow',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: appPrimary)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Follow people to see their posts, jobs, and services in your feed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: appMuted, fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? const Center(
                          child: Text('No suggestions yet.',
                              style: TextStyle(color: appMuted)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) =>
                              _SuggestedUserTile(
                                user: _users[i],
                                isFollowed: _followed.contains(_users[i].id),
                                isLoading: _following.contains(_users[i].id),
                                onToggle: () => _toggle(_users[i]),
                              ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: FilledButton(
                onPressed: widget.onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: appPrimary,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _followed.isEmpty ? 'Skip for now' : 'Continue  →',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet version for the people-icon button in Discover AppBar.
class SuggestedUsersSheet extends StatefulWidget {
  const SuggestedUsersSheet({super.key, required this.api});
  final MarketplaceApi api;

  @override
  State<SuggestedUsersSheet> createState() => _SuggestedUsersSheetState();
}

class _SuggestedUsersSheetState extends State<SuggestedUsersSheet> {
  List<UserSearchResult> _users = [];
  final Set<String> _followed = {};
  final Set<String> _following = {};
  final Set<String> _dismissed = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suggested = widget.api.getSuggestedUsers(limit: 20);
    final following = widget.api.getMyFollowing();
    final users = await suggested;
    final followingList = await following;
    if (!mounted) return;
    setState(() {
      _users = users;
      _followed.addAll(followingList.map((u) => u.id));
      _loading = false;
    });
  }

  Future<void> _toggle(UserSearchResult u) async {
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Column(
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
              const Icon(Icons.people_alt_outlined, color: appPrimary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('People You May Know',
                    style: TextStyle(
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
                    ? const Center(
                        child: Text('No suggestions.',
                            style: TextStyle(color: appMuted)))
                    : ListView.separated(
                        controller: scroll,
                        itemCount: _users.where((u) => !_dismissed.contains(u.id)).length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final visible = _users.where((u) => !_dismissed.contains(u.id)).toList();
                          final u = visible[i];
                          return _SuggestedUserTile(
                            user: u,
                            isFollowed: _followed.contains(u.id),
                            isLoading: _following.contains(u.id),
                            onToggle: () => _toggle(u),
                            onRemove: () => setState(() => _dismissed.add(u.id)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedUserTile extends StatelessWidget {
  const _SuggestedUserTile({
    required this.user,
    required this.isFollowed,
    required this.isLoading,
    required this.onToggle,
    this.onRemove,
  });
  final UserSearchResult user;
  final bool isFollowed;
  final bool isLoading;
  final VoidCallback onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Avatar(
          imageData: user.profilePic,
          name: user.fullName,
          radius: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.fullName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              _subtitle,
              style: const TextStyle(color: appMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 10),
        isLoading
            ? const SizedBox(
                width: 68,
                height: 32,
                child: Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))))
            : AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: OutlinedButton(
                  onPressed: onToggle,
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                        isFollowed ? appPrimary : Colors.transparent,
                    foregroundColor:
                        isFollowed ? Colors.white : appPrimary,
                    side: const BorderSide(color: appPrimary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(isFollowed ? 'Following' : 'Follow',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
        if (onRemove != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.black54),
            ),
          ),
        ],
      ]),
    );
  }

  String get _subtitle {
    final parts = <String>[];
    if (user.role != 'client') parts.add(_capitalize(user.role));
    if (user.followers > 0) parts.add('${user.followers} followers');
    if (user.posts > 0) parts.add('${user.posts} posts');
    if (parts.isEmpty && user.bio != null && user.bio!.isNotEmpty) {
      return user.bio!;
    }
    return parts.isEmpty ? 'HanapGawa user' : parts.join(' · ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
