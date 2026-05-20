import 'package:flutter/material.dart';

import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  var _loading = false;

  Future<void> _handleDone() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onDone();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _features = [
    (
      Icons.search_outlined,
      'Explore Providers',
      'Find approved workers and agencies across Tawi-Tawi.'
    ),
    (
      Icons.calendar_today_outlined,
      'Book Instantly',
      'Send booking requests directly from your phone.'
    ),
    (
      Icons.star_outline,
      'Leave Reviews',
      'Rate completed jobs to help your community.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.3, 0.65, 1.0],
            colors: [
              Color(0xFF1E1523),
              Color(0xFF2E2035),
              appPrimary,
              appSecondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero block
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/hanapgawa-shaped-white-background-logo.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: appAccent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.search,
                                  size: 32, color: appPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Image.asset(
                          'assets/hanapgawa-wordmark.png',
                          height: 26,
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
                        const SizedBox(height: 14),
                        const Text(
                          "Tawi-Tawi's local service marketplace.\nFind trusted workers, book with confidence.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xC8FFFFFF),
                            fontSize: 16,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 44),

                    // Features
                    Column(
                      children: _features
                          .map((f) =>
                              _FeatureItem(icon: f.$1, title: f.$2, desc: f.$3))
                          .toList(),
                    ),

                    const SizedBox(height: 40),

                    // CTA buttons
                    FilledButton(
                      onPressed: _loading ? null : _handleDone,
                      style: FilledButton.styleFrom(
                        backgroundColor: appAccent,
                        foregroundColor: appPrimary,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: appPrimary))
                          : const Text('Get Started'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loading ? null : _handleDone,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xA6FFFFFF),
                        minimumSize: const Size.fromHeight(44),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('I already have an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem(
      {required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: appAccent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: appAccent, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 3),
              Text(desc,
                  style: const TextStyle(
                      color: Color(0xA6FFFFFF), fontSize: 13, height: 1.5)),
            ],
          ),
        ),
      ]),
    );
  }
}
