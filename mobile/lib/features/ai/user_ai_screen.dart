import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/theme.dart';

class UserAIScreen extends StatefulWidget {
  const UserAIScreen({super.key, required this.api});
  final MarketplaceApi api;

  @override
  State<UserAIScreen> createState() => _UserAIScreenState();
}

class _UserAIScreenState extends State<UserAIScreen> {
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<({bool isUser, String text})> _history = [];
  var _thinking = false;

  @override
  void dispose() {
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _send() async {
    final input = _chatCtrl.text.trim();
    if (input.isEmpty || _thinking) return;
    _chatCtrl.clear();
    setState(() {
      _history.add((isUser: true, text: input));
      _thinking = true;
    });
    _scrollToBottom();
    try {
      final historyPayload = _history
          .take(_history.length - 1)
          .map((m) => {'isUser': m.isUser, 'text': m.text})
          .toList();
      final reply = await widget.api.aiChat(input, history: historyPayload);
      if (mounted) setState(() => _history.add((isUser: false, text: reply)));
    } catch (_) {
      if (mounted) {
        setState(() => _history.add((
              isUser: false,
              text:
                  'Sorry, I\'m having trouble connecting right now. Please try again.'
            )));
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: appPrimary.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.psychology, color: appPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Zandra AI',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              Text('Your local service assistant',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(180),
                      fontWeight: FontWeight.w500)),
            ]),
          ]),
          toolbarHeight: 64,
        ),
        body: Column(children: [
          Expanded(
            child: _history.isEmpty && !_thinking
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length + (_thinking ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_thinking && i == _history.length) {
                        return const _TypingIndicator();
                      }
                      final msg = _history[i];
                      return _ChatBubble(text: msg.text, isUser: msg.isUser);
                    },
                  ),
          ),
          _buildInput(),
        ]),
      );

  Widget _buildWelcome() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 16),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: appPrimary.withAlpha(18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology, color: appPrimary, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Zandra AI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'Your smart assistant for finding workers\nand navigating the platform.',
            textAlign: TextAlign.center,
            style: TextStyle(color: appMuted, height: 1.5),
          ),
          const SizedBox(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Suggested questions',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          _SuggestGrid(onTap: (t) {
            _chatCtrl.text = t;
            _send();
          }),
        ]),
      );

  Widget _buildInput() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: appBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Ask me anything…',
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
              onPressed: _thinking ? null : _send,
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
      );
}

// ─── Sub-widgets ───────────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF3EEFF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(delay: 0),
            SizedBox(width: 4),
            _Dot(delay: 200),
            SizedBox(width: 4),
            _Dot(delay: 400),
          ]),
        ),
      );
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final int delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 1, curve: Curves.easeInOut),
    ));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
          width: 8,
          height: 8,
          decoration:
              const BoxDecoration(color: appPrimary, shape: BoxShape.circle),
        ),
      );
}

class _SuggestGrid extends StatelessWidget {
  const _SuggestGrid({required this.onTap});
  final void Function(String) onTap;

  static const _items = [
    (Icons.search, 'How do I find a worker?'),
    (Icons.calendar_today_outlined, 'How does booking work?'),
    (Icons.post_add_outlined, 'How do I post a job?'),
    (Icons.security_outlined, 'Is the platform safe?'),
    (Icons.star_outline, 'How do I leave a review?'),
    (Icons.attach_money, 'How is pricing handled?'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        children: _items
            .map((item) => GestureDetector(
                  onTap: () => onTap(item.$2),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: appBorder),
                    ),
                    child: Row(children: [
                      Icon(item.$1, size: 18, color: appPrimary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(item.$2,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: appMuted),
                    ]),
                  ),
                ))
            .toList(),
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
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          decoration: BoxDecoration(
            color: isUser ? appPrimary : const Color(0xFFF3EEFF),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
          ),
          child: Text(text,
              style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1F1F1F),
                  fontSize: 14,
                  height: 1.55)),
        ),
      );
}
