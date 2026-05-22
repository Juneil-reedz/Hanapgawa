import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _controller;
  var _loading = false;
  var _page = 0.0;
  var _currentPage = 0;

  static const _pages = [
    _IntroPage(
      icon: Icons.search_rounded,
      eyebrow: 'Chapter 1',
      title: 'Find trusted local help',
      body:
          'Browse approved workers and agencies in Tawi-Tawi for home services, errands, repairs, and more.',
      color: Color(0xFF7B2FF7),
      accent: Color(0xFFE9D8FF),
    ),
    _IntroPage(
      icon: Icons.calendar_month_rounded,
      eyebrow: 'Chapter 2',
      title: 'Book work without the back-and-forth',
      body:
          'Send requests, agree on schedules, and keep your booking details in one place.',
      color: Color(0xFF5F3DC4),
      accent: Color(0xFFDDE7FF),
    ),
    _IntroPage(
      icon: Icons.forum_rounded,
      eyebrow: 'Chapter 3',
      title: 'Share, chat, and stay updated',
      body:
          'Discover community posts, message providers, and follow stories from people around you.',
      color: Color(0xFF8A3FFC),
      accent: Color(0xFFFFE8CC),
    ),
    _IntroPage(
      icon: Icons.verified_rounded,
      eyebrow: 'Final Page',
      title: 'Build trust after every job',
      body:
          'Reviews, profiles, and booking history help the community choose reliable service providers.',
      color: Color(0xFF6D28D9),
      accent: Color(0xFFE7F8EF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.9)
      ..addListener(() {
        setState(() => _page = _controller.page ?? 0);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDone() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onDone();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _nextPage() {
    if (_currentPage == _pages.length - 1) {
      _handleDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.34, 0.72, 1],
            colors: [
              Color(0xFF170F20),
              Color(0xFF2B1740),
              appPrimary,
              appSecondary,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24, compact ? 18 : 28, 24, 10),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/hanapgawa-shaped-white-background-logo.png',
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: appAccent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.handshake_rounded,
                                color: appPrimary, size: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Image.asset(
                        'assets/hanapgawa-wordmark.png',
                        height: 25,
                        errorBuilder: (_, __, ___) => const Text(
                          'HanapGawa',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Open your local guide to trusted work and services.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xCFFFFFFF), height: 1.5),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            top: compact ? 18 : 34,
                            bottom: compact ? 18 : 30,
                            child: const _BookShadow(),
                          ),
                          PageView.builder(
                            controller: _controller,
                            itemCount: _pages.length,
                            onPageChanged: (index) =>
                                setState(() => _currentPage = index),
                            itemBuilder: (context, index) => _TurningBookPage(
                              page: _pages[index],
                              index: index,
                              currentPage: _page,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_pages.length, (index) {
                            final active = index == _currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: active ? 28 : 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.34),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _loading ? null : _nextPage,
                          style: FilledButton.styleFrom(
                            backgroundColor: appAccent,
                            foregroundColor: appPrimary,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: appPrimary,
                                  ),
                                )
                              : Text(isLastPage ? 'Get Started' : 'Turn Page'),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _handleDone,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xBFFFFFFF),
                            minimumSize: const Size.fromHeight(44),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('I already have an account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _IntroPage {
  const _IntroPage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.color,
    required this.accent,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final Color color;
  final Color accent;
}

class _BookShadow extends StatelessWidget {
  const _BookShadow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 46,
            spreadRadius: -12,
            offset: const Offset(0, 24),
          ),
        ],
      ),
    );
  }
}

class _TurningBookPage extends StatelessWidget {
  const _TurningBookPage({
    required this.page,
    required this.index,
    required this.currentPage,
  });

  final _IntroPage page;
  final int index;
  final double currentPage;

  @override
  Widget build(BuildContext context) {
    final distance = (index - currentPage).clamp(-1.0, 1.0);
    final isTurningAway = distance < 0;
    final turn = isTurningAway ? distance.abs() : (1 - distance).clamp(0, 1);
    final angle =
        isTurningAway ? -turn * math.pi / 2.7 : distance * math.pi / 3;
    final scale = 1 - distance.abs() * 0.05;
    final opacity = (1 - distance.abs() * 0.35).clamp(0.0, 1.0);

    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateY(angle)
      ..scale(scale, scale);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 22),
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.centerLeft,
          transform: transform,
          child: _BookPage(page: page, number: index + 1),
        ),
      ),
    );
  }
}

class _BookPage extends StatelessWidget {
  const _BookPage({required this.page, required this.number});
  final _IntroPage page;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -54,
              top: -54,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.accent,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(38, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: page.color,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: page.color.withOpacity(0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(page.icon, color: Colors.white, size: 32),
                      ),
                      const Spacer(),
                      Text(
                        number.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: page.color.withOpacity(0.18),
                          fontSize: 42,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    page.eyebrow.toUpperCase(),
                    style: TextStyle(
                      color: page.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    page.title,
                    style: const TextStyle(
                      color: Color(0xFF221729),
                      fontSize: 31,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    page.body,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 15.5,
                      height: 1.65,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: page.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe_rounded, color: page.color, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Swipe to turn the page',
                          style: TextStyle(
                            color: page.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7B2FF7).withOpacity(0.04)
      ..strokeWidth = 1;
    for (var y = 92.0; y < size.height - 36; y += 26) {
      canvas.drawLine(Offset(38, y), Offset(size.width - 28, y), paint);
    }

    final fold = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.42),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(size.width - 44, 0, 44, size.height));
    canvas.drawRect(Rect.fromLTWH(size.width - 44, 0, 44, size.height), fold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
