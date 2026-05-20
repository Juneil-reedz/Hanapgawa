import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/local/sync_service.dart';

/// Wraps [child] with a thin "You're offline" banner whenever connectivity
/// is lost. The banner auto-dismisses and shows a sync confirmation when
/// the device comes back online.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  bool _isOnline = true;
  late final AnimationController _anim;
  late final Animation<double> _slide;
  StreamSubscription<bool>? _sub;
  Timer? _syncMsgTimer;
  var _showSync = false;

  @override
  void initState() {
    super.initState();

    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = CurvedAnimation(parent: _anim, curve: Curves.easeOut);

    _isOnline = SyncService.instance.isOnline;
    if (!_isOnline) _anim.forward();

    _sub = SyncService.instance.onlineStream.listen((online) async {
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) {
        // Keep banner visible briefly to show "syncing" message
        setState(() => _showSync = true);
        _syncMsgTimer?.cancel();
        _syncMsgTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _showSync = false);
            _anim.reverse();
          }
        });
      } else {
        _anim.forward();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncMsgTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizeTransition(
            sizeFactor: _slide,
            child: _Banner(isOnline: _isOnline, showSync: _showSync),
          ),
          Expanded(child: widget.child),
        ],
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.isOnline, required this.showSync});
  final bool isOnline;
  final bool showSync;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isOnline ? const Color(0xFF22C55E) : Colors.orange.shade700;
    final icon = isOnline
        ? (showSync ? Icons.sync : Icons.wifi)
        : Icons.wifi_off;
    final message = isOnline
        ? (showSync ? 'Back online — syncing changes…' : 'Connected')
        : "You're offline — showing cached content";

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
