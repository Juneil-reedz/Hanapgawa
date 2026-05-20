import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/empty_state.dart';

// ─── AI section ───────────────────────────────────────────────────────────────

class AdminAISection extends StatefulWidget {
  const AdminAISection({
    super.key,
    required this.api,
    required this.users,
    required this.reports,
    required this.bookings,
    required this.jobs,
  });

  final MarketplaceApi api;
  final List<SessionUser> users;
  final List<ReportItem> reports;
  final List<Booking> bookings;
  final List<JobPost> jobs;

  @override
  State<AdminAISection> createState() => _AdminAISectionState();
}

class _AdminAISectionState extends State<AdminAISection> {
  int _view = 0; // 0=risk, 1=reports, 2=insights, 3=chat
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<({bool isUser, String text})> _chatHistory = [];
  var _thinking = false;

  @override
  void dispose() {
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Risk scoring ────────────────────────────────────────────────────────

  int _cancellationsFor(String userId) => widget.bookings
      .where((b) => b.workerUserId == userId && b.status == 'cancelled')
      .length;

  int _riskScore(SessionUser user) {
    final cancellations = _cancellationsFor(user.id);
    return (user.reportCount * 20) + (cancellations * 5);
  }

  String _riskLevel(int score) {
    if (score >= 70) return 'High';
    if (score >= 40) return 'Medium';
    return 'Low';
  }

  Color _riskColor(int score) {
    if (score >= 70) return const Color(0xFFEF4444);
    if (score >= 40) return const Color(0xFFF97316);
    return const Color(0xFF22C55E);
  }

  List<SessionUser> get _riskUsers {
    final nonAdmin =
        widget.users.where((u) => u.role != 'admin').toList();
    nonAdmin.sort((a, b) => _riskScore(b).compareTo(_riskScore(a)));
    return nonAdmin.where((u) => _riskScore(u) > 0).toList();
  }

  // ─── Report prioritization ───────────────────────────────────────────────

  static const _highKeywords = [
    'scam', 'fraud', 'fake', 'harassment', 'abuse', 'threat', 'assault',
    'extort', 'blackmail', 'stole', 'stolen', 'robbery', 'violence',
  ];
  static const _mediumKeywords = [
    'cancel', 'no-show', 'rude', 'unprofessional', 'overcharge', 'overcharged',
    'late', 'ghost', 'ghosted', 'disrespect', 'disrespectful', 'negligent',
    'neglect',
  ];

  String _reportPriority(ReportItem r) {
    final text = '${r.reason} ${r.details}'.toLowerCase();
    if (_highKeywords.any(text.contains)) return 'High';
    if (_mediumKeywords.any(text.contains)) return 'Medium';
    return 'Low';
  }

  Color _priorityColor(String p) => switch (p) {
        'High' => const Color(0xFFEF4444),
        'Medium' => const Color(0xFFF97316),
        _ => const Color(0xFF22C55E),
      };

  List<ReportItem> get _prioritizedReports {
    const order = {'High': 0, 'Medium': 1, 'Low': 2};
    final pending =
        widget.reports.where((r) => r.status == 'pending').toList();
    pending.sort((a, b) =>
        (order[_reportPriority(a)] ?? 2)
            .compareTo(order[_reportPriority(b)] ?? 2));
    return pending;
  }

  // ─── Insights ─────────────────────────────────────────────────────────────

  List<SessionUser> get _topReported {
    final list = widget.users
        .where((u) => u.role != 'admin' && u.reportCount > 0)
        .toList()
      ..sort((a, b) => b.reportCount.compareTo(a.reportCount));
    return list.take(5).toList();
  }

  List<MapEntry<String, int>> get _topCancelledProviders {
    final counts = <String, int>{};
    for (final b in widget.bookings) {
      if (b.status == 'cancelled') {
        counts[b.workerUserId] = (counts[b.workerUserId] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  List<MapEntry<String, int>> get _complaintCategories {
    final counts = <String, int>{};
    for (final r in widget.reports) {
      final booking = widget.bookings
          .where((b) => b.id == r.bookingId)
          .firstOrNull;
      final cat = booking?.serviceCategory ?? 'Unknown';
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  String _nameForId(String userId) {
    final u = widget.users
        .where((u) => u.id == userId)
        .firstOrNull;
    if (u?.fullName?.isNotEmpty == true) return u!.fullName!;
    if (u?.email.isNotEmpty == true) return u!.email;
    return userId.length <= 8 ? userId : userId.substring(0, 8);
  }

  // ─── AI chat ─────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendChat() async {
    final input = _chatCtrl.text.trim();
    if (input.isEmpty || _thinking) return;
    _chatCtrl.clear();
    setState(() {
      _chatHistory.add((isUser: true, text: input));
      _thinking = true;
    });
    _scrollToBottom();
    try {
      final historyPayload = _chatHistory
          .take(_chatHistory.length - 1)
          .map((m) => {'isUser': m.isUser, 'text': m.text})
          .toList();
      // Build a brief platform context summary for the admin AI
      final pendingReports =
          widget.reports.where((r) => r.status == 'pending').length;
      final highRisk = _riskUsers.where((u) => _riskScore(u) >= 70).length;
      final context = 'Platform stats: ${widget.users.length} users, '
          '${widget.bookings.length} bookings, '
          '$pendingReports pending reports, '
          '$highRisk high-risk users.';
      final reply = await widget.api
          .aiAdminChat(input, history: historyPayload, context: context);
      if (mounted) setState(() => _chatHistory.add((isUser: false, text: reply)));
    } catch (_) {
      if (mounted) {
        setState(() => _chatHistory.add((
          isUser: false,
          text: 'AI service unavailable. Please check your connection.'
        )));
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollToBottom();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  static const _views = ['Risk Board', 'Reports', 'Insights', 'AI Chat'];
  static const _viewIcons = [
    Icons.warning_amber_rounded,
    Icons.flag_outlined,
    Icons.bar_chart,
    Icons.chat_bubble_outline,
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildSubNav(),
          const SizedBox(height: 20),
          switch (_view) {
            0 => _buildRiskBoard(),
            1 => _buildPrioritizedReports(),
            2 => _buildInsights(),
            3 => _buildChat(),
            _ => const SizedBox.shrink(),
          },
        ],
      );

  Widget _buildHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appPrimary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.psychology, color: appPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Assistant',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              Text('Rule-based fraud detection & insights',
                  style: TextStyle(color: appMuted, fontSize: 12)),
            ]),
          ]),
        ],
      );

  Widget _buildSubNav() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_views.length, (i) {
            final selected = _view == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _view = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? appPrimary.withAlpha(15) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: selected ? appPrimary : appBorder,
                        width: selected ? 1.5 : 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_viewIcons[i],
                        size: 14,
                        color: selected ? appPrimary : appMuted),
                    const SizedBox(width: 6),
                    Text(_views[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? appPrimary : const Color(0xFF1F1F1F),
                        )),
                  ]),
                ),
              ),
            );
          }),
        ),
      );

  // ── Risk Board ─────────────────────────────────────────────────────────────

  Widget _buildRiskBoard() {
    final users = _riskUsers;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _AICardHeader(
        title: 'Fraud Risk Board',
        subtitle:
            'Score = (reports × 20) + (cancellations × 5)',
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFEF4444),
      ),
      const SizedBox(height: 4),
      Row(children: [
        _RiskSummaryChip(
            label: 'High',
            count: users.where((u) => _riskScore(u) >= 70).length,
            color: const Color(0xFFEF4444)),
        const SizedBox(width: 8),
        _RiskSummaryChip(
            label: 'Medium',
            count: users
                .where((u) =>
                    _riskScore(u) >= 40 && _riskScore(u) < 70)
                .length,
            color: const Color(0xFFF97316)),
        const SizedBox(width: 8),
        _RiskSummaryChip(
            label: 'Low',
            count:
                users.where((u) => _riskScore(u) < 40).length,
            color: const Color(0xFF22C55E)),
      ]),
      const SizedBox(height: 14),
      if (users.isEmpty)
        const EmptyState(
          icon: Icons.shield_outlined,
          title: 'No flagged users',
          subtitle: 'All users currently have zero risk score.',
        )
      else
        ...users.map((u) {
          final score = _riskScore(u);
          final level = _riskLevel(score);
          final color = _riskColor(score);
          final cancels = _cancellationsFor(u.id);
          return AppCard(
            accentColor: score >= 70 ? color : null,
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.fullName ?? u.email,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, children: [
                        _MiniTag(
                            '${u.reportCount} report${u.reportCount == 1 ? '' : 's'}',
                            Colors.red),
                        _MiniTag(
                            '$cancels cancel${cancels == 1 ? '' : 's'}',
                            Colors.orange),
                        _MiniTag(u.role, appPrimary),
                      ]),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withAlpha(60)),
                  ),
                  child: Text(level,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
                const SizedBox(height: 4),
                Text('$score pts',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        height: 1)),
              ]),
            ]),
          );
        }),
    ]);
  }

  // ── Prioritized Reports ────────────────────────────────────────────────────

  Widget _buildPrioritizedReports() {
    final reports = _prioritizedReports;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _AICardHeader(
        title: 'Prioritized Reports',
        subtitle: 'Pending reports ranked by severity keywords',
        icon: Icons.flag_outlined,
        color: Color(0xFFF97316),
      ),
      const SizedBox(height: 14),
      if (reports.isEmpty)
        const EmptyState(
          icon: Icons.verified_outlined,
          title: 'No pending reports',
          subtitle: 'All reports have been resolved or dismissed.',
        )
      else
        ...reports.map((r) {
          final priority = _reportPriority(r);
          final color = _priorityColor(priority);
          return AppCard(
            accentColor: priority == 'High' ? color : null,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(r.reason,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withAlpha(60)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, size: 7, color: color),
                        const SizedBox(width: 5),
                        Text(priority,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(r.details,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: appMuted, fontSize: 13, height: 1.4)),
                ]),
          );
        }),
    ]);
  }

  // ── Insights ───────────────────────────────────────────────────────────────

  Widget _buildInsights() {
    final topReported = _topReported;
    final topCancelled = _topCancelledProviders;
    final complaintCats = _complaintCategories;
    final maxReports =
        topReported.isEmpty ? 1 : topReported.first.reportCount;
    final maxCancels = topCancelled.isEmpty ? 1 : topCancelled.first.value;
    final maxComplaints = complaintCats.isEmpty ? 1 : complaintCats.first.value;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _AICardHeader(
        title: 'AI Insights Dashboard',
        subtitle: 'Aggregated risk & complaint patterns',
        icon: Icons.bar_chart,
        color: appPrimary,
      ),
      const SizedBox(height: 14),
      // Most reported users
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Most Reported Users',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (topReported.isEmpty)
            const Text('No reports yet.',
                style: TextStyle(color: appMuted, fontSize: 13))
          else
            ...topReported.map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  u.fullName ?? u.email,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                          Text('${u.reportCount} report${u.reportCount == 1 ? '' : 's'}',
                              style:
                                  const TextStyle(color: appMuted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: u.reportCount / maxReports,
                            minHeight: 6,
                            backgroundColor: appBorder,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ]),
                )),
        ]),
      ),
      // Most cancellations
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Providers with Most Cancellations',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (topCancelled.isEmpty)
            const Text('No cancellations yet.',
                style: TextStyle(color: appMuted, fontSize: 13))
          else
            ...topCancelled.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(_nameForId(e.key),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                          Text('${e.value} cancellation${e.value == 1 ? '' : 's'}',
                              style:
                                  const TextStyle(color: appMuted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: e.value / maxCancels,
                            minHeight: 6,
                            backgroundColor: appBorder,
                            color: const Color(0xFFF97316),
                          ),
                        ),
                      ]),
                )),
        ]),
      ),
      // Complaint categories
      if (complaintCats.isNotEmpty)
        AppCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Complaint-Heavy Categories',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            ...complaintCats.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                          Text('${e.value} complaint${e.value == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: appMuted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: e.value / maxComplaints,
                            minHeight: 6,
                            backgroundColor: appBorder,
                            color: appPrimary,
                          ),
                        ),
                      ]),
                )),
          ]),
        ),
    ]);
  }

  // ── AI Chat ────────────────────────────────────────────────────────────────

  Widget _buildChat() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AICardHeader(
            title: 'Admin AI Chat',
            subtitle: 'Ask about users, reports, and platform health',
            icon: Icons.chat_bubble_outline,
            color: Color(0xFF4F7FFF),
          ),
          const SizedBox(height: 14),
          Container(
            height: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: appBorder),
            ),
            child: Column(children: [
              Expanded(
                child: _chatHistory.isEmpty && !_thinking
                    ? _buildChatEmpty()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(14),
                        itemCount:
                            _chatHistory.length + (_thinking ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_thinking && i == _chatHistory.length) {
                            return const _AdminTypingIndicator();
                          }
                          final msg = _chatHistory[i];
                          return _ChatBubble(
                            text: msg.text,
                            isUser: msg.isUser,
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _chatCtrl,
                      onSubmitted: (_) => _sendChat(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about risk, reports, bookings…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _thinking ? null : _sendChat,
                    style: FilledButton.styleFrom(
                      backgroundColor: appPrimary,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: _thinking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18, color: Colors.white),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      );

  Widget _buildChatEmpty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.psychology, size: 48, color: appMuted),
          const SizedBox(height: 12),
          const Text('Admin AI',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('Ask me anything about the platform.',
              style: TextStyle(color: appMuted, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _SuggestionChip(
                  label: 'High-risk users?',
                  onTap: () {
                    _chatCtrl.text = 'Who are the high-risk users?';
                    _sendChat();
                  }),
              _SuggestionChip(
                  label: 'Most reported?',
                  onTap: () {
                    _chatCtrl.text = 'Show most reported accounts';
                    _sendChat();
                  }),
              _SuggestionChip(
                  label: 'Platform summary',
                  onTap: () {
                    _chatCtrl.text = 'Give me a platform summary';
                    _sendChat();
                  }),
            ],
          ),
        ]),
      );
}

// ─── Sub-widgets ───────────────────────────────────────────────────────────────

class _AICardHeader extends StatelessWidget {
  const _AICardHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          Text(subtitle,
              style: const TextStyle(color: appMuted, fontSize: 11)),
        ]),
      ]);
}

class _RiskSummaryChip extends StatelessWidget {
  const _RiskSummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900)),
          ),
        ]),
      );
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          decoration: BoxDecoration(
            color: isUser ? appPrimary : const Color(0xFFF3EEFF),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Text(text,
              style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1F1F1F),
                  fontSize: 13,
                  height: 1.5)),
        ),
      );
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: appPrimary.withAlpha(12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: appPrimary.withAlpha(50)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: appPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      );
}

class _AdminTypingIndicator extends StatelessWidget {
  const _AdminTypingIndicator();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 40,
              height: 14,
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: appPrimary),
              ),
            ),
            SizedBox(width: 8),
            Text('Gemini is thinking…',
                style: TextStyle(color: appMuted, fontSize: 12)),
          ]),
        ),
      );
}
