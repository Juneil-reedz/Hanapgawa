import 'dart:math' as math;
import 'package:flutter/material.dart';

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlight = isDark ? const Color(0xFF3D3D3D) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _ctrl.value;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                math.max(0.0, t - 0.3),
                t,
                math.min(1.0, t + 0.3),
              ],
              colors: [base, highlight, base],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

Widget _box({double? width, double height = 14, double radius = 8, Color? color}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? const Color(0xFFE0E0E0),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

// ── Feed / Discover ─────────────────────────────────────────────────────────

class SkeletonFeedList extends StatelessWidget {
  const SkeletonFeedList({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // story row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: List.generate(6, (_) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      _box(width: 58, height: 58, radius: 29),
                      const SizedBox(height: 5),
                      _box(width: 44, height: 9),
                    ],
                  ),
                )),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...List.generate(4, (_) => const _FeedCardSkeleton()),
          ],
        ),
      ),
    );
  }
}

class _FeedCardSkeleton extends StatelessWidget {
  const _FeedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar + name row
          Row(children: [
            _box(width: 40, height: 40, radius: 20),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(width: 120, height: 13),
              const SizedBox(height: 6),
              _box(width: 80, height: 10),
            ]),
          ]),
          const SizedBox(height: 10),
          // text lines
          _box(width: double.infinity, height: 13),
          const SizedBox(height: 6),
          _box(width: 220, height: 13),
          const SizedBox(height: 10),
          // image placeholder
          _box(width: double.infinity, height: 200, radius: 12),
          const SizedBox(height: 10),
          // action bar
          Row(children: [
            _box(width: 52, height: 28, radius: 14),
            const SizedBox(width: 8),
            _box(width: 52, height: 28, radius: 14),
            const SizedBox(width: 8),
            _box(width: 52, height: 28, radius: 14),
          ]),
        ],
      ),
    );
  }
}

// ── Jobs ────────────────────────────────────────────────────────────────────

class SkeletonJobList extends StatelessWidget {
  const SkeletonJobList({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        children: List.generate(5, (_) => const _JobCardSkeleton()),
      ),
    );
  }
}

class _JobCardSkeleton extends StatelessWidget {
  const _JobCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _box(width: 36, height: 36, radius: 18),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _box(width: 140, height: 13),
                const SizedBox(height: 5),
                _box(width: 90, height: 10),
              ]),
              const Spacer(),
              _box(width: 60, height: 22, radius: 11),
            ]),
            const SizedBox(height: 10),
            _box(width: double.infinity, height: 12),
            const SizedBox(height: 5),
            _box(width: 200, height: 12),
            const SizedBox(height: 10),
            Row(children: [
              _box(width: 70, height: 20, radius: 10),
              const SizedBox(width: 8),
              _box(width: 70, height: 20, radius: 10),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Dashboard ───────────────────────────────────────────────────────────────

class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // stats row
            Row(children: List.generate(3, (i) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _box(width: 40, height: 22),
                      const SizedBox(height: 6),
                      _box(width: 56, height: 10),
                    ],
                  ),
                ),
              ),
            ))),
            const SizedBox(height: 20),
            _box(width: 120, height: 16),
            const SizedBox(height: 12),
            ...List.generate(3, (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  _box(width: 54, height: 54, radius: 10),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _box(width: 130, height: 13),
                    const SizedBox(height: 7),
                    _box(width: 80, height: 11),
                    const SizedBox(height: 7),
                    _box(width: 60, height: 20, radius: 10),
                  ]),
                ]),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ── Bookings ────────────────────────────────────────────────────────────────

class SkeletonBookingList extends StatelessWidget {
  const SkeletonBookingList({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        children: List.generate(4, (_) => const _BookingCardSkeleton()),
      ),
    );
  }
}

class _BookingCardSkeleton extends StatelessWidget {
  const _BookingCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _box(width: 44, height: 44, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _box(width: 150, height: 14),
                  const SizedBox(height: 6),
                  _box(width: 100, height: 11),
                ]),
              ),
              _box(width: 70, height: 24, radius: 12),
            ]),
            const SizedBox(height: 12),
            _box(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            _box(width: 180, height: 12),
            const SizedBox(height: 12),
            Row(children: [
              _box(width: 90, height: 32, radius: 8),
              const SizedBox(width: 8),
              _box(width: 90, height: 32, radius: 8),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Profile sections ────────────────────────────────────────────────────────

class SkeletonProfilePhotos extends StatelessWidget {
  const SkeletonProfilePhotos({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: SizedBox(
        height: 80,
        child: Row(
          children: List.generate(5, (_) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _box(width: 72, height: 72, radius: 8),
          )),
        ),
      ),
    );
  }
}

class SkeletonProfilePosts extends StatelessWidget {
  const SkeletonProfilePosts({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        children: List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _box(width: 36, height: 36, radius: 18),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _box(width: 110, height: 12),
                const SizedBox(height: 5),
                _box(width: 70, height: 9),
              ]),
            ]),
            const SizedBox(height: 8),
            _box(width: double.infinity, height: 12),
            const SizedBox(height: 5),
            _box(width: 200, height: 12),
            const SizedBox(height: 8),
            _box(width: double.infinity, height: 160, radius: 10),
          ]),
        )),
      ),
    );
  }
}

class SkeletonProfileJobPosts extends StatelessWidget {
  const SkeletonProfileJobPosts({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        children: List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(width: 160, height: 13),
              const SizedBox(height: 7),
              _box(width: 100, height: 11),
              const SizedBox(height: 7),
              _box(width: 70, height: 20, radius: 10),
            ]),
          ),
        )),
      ),
    );
  }
}
