import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/api/marketplace_api.dart';
import 'core/local/local_db.dart';
import 'core/local/sync_service.dart';
import 'core/models/models.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/shell_screen.dart';

void main() {
  runApp(const HanapGawaApp());
}

class HanapGawaApp extends StatefulWidget {
  const HanapGawaApp({super.key});

  @override
  State<HanapGawaApp> createState() => _HanapGawaAppState();
}

class _HanapGawaAppState extends State<HanapGawaApp>
    with SingleTickerProviderStateMixin {
  late final MarketplaceApi api;
  late final AnimationController _slideCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Widget? _exitingWidget;
  var _useBookFlip = false;

  var _ready = false;
  var _splashComplete = false;
  var _showOnboarding = false;
  SessionUser? _user;

  @override
  void initState() {
    super.initState();
    api = MarketplaceApi();
    _slideCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _exitingWidget = null);
        _slideCtrl.reset();
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await api.init();
    // Open local database and start connectivity monitoring
    await LocalDb.instance.db;
    await SyncService.instance.initialize(api);
    final user = api.storedUser;
    setState(() {
      _user = user;
      _showOnboarding = user == null;
      _ready = true;
    });
  }

  Future<void> _finishOnboarding() async {
    api.markOnboardingSeen();
    _slideCtrl.duration = const Duration(milliseconds: 420);
    _useBookFlip = false;
    _exitingWidget = OnboardingScreen(onDone: () async {});
    _slideCtrl.forward(from: 0);
    setState(() => _showOnboarding = false);
  }

  Future<void> _setSession(AuthResponse auth) async {
    await api.persistSession(auth);
    _slideCtrl.duration = const Duration(milliseconds: 720);
    _useBookFlip = true;
    setState(() {
      _exitingWidget = AuthScreen(api: api, onAuthenticated: (_) async {});
      _user = auth.user;
    });
    _slideCtrl.forward(from: 0);
  }

  Future<void> _logout() async {
    await api.clearSession();
    setState(() {
      _user = null;
      _showOnboarding = true;
    });
  }

  Widget _buildCurrentScreen() {
    if (!_ready || !_splashComplete) {
      return _SplashScreen(
          key: const ValueKey('splash'),
          onComplete: () {
            if (mounted) setState(() => _splashComplete = true);
          });
    }
    if (_showOnboarding) {
      return OnboardingScreen(
          key: const ValueKey('onboarding'), onDone: _finishOnboarding);
    }
    if (_user == null) {
      return AuthScreen(
          key: const ValueKey('auth'), api: api, onAuthenticated: _setSession);
    }
    return ShellScreen(
        key: const ValueKey('shell'), api: api, onLogout: _logout);
  }

  @override
  Widget build(BuildContext context) {
    final slideIn = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeInOutCubic));
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0),
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeInOutCubic));

    return MaterialApp(
      title: 'HanapGawa',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedBuilder(
        animation: _slideCtrl,
        builder: (context, _) {
          final current = _buildCurrentScreen();
          if (_exitingWidget != null && _slideCtrl.value < 1.0) {
            if (_useBookFlip) {
              return _BookFlipTransition(
                animation: _slideCtrl,
                exiting: _exitingWidget!,
                entering: current,
              );
            }
            return Stack(children: [
              SlideTransition(position: slideOut, child: _exitingWidget),
              SlideTransition(position: slideIn, child: current),
            ]);
          }
          return current;
        },
      ),
    );
  }
}

class _BookFlipTransition extends StatelessWidget {
  const _BookFlipTransition({
    required this.animation,
    required this.exiting,
    required this.entering,
  });

  final Animation<double> animation;
  final Widget exiting;
  final Widget entering;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final value = curved.value;
        final exitingTurns = value <= 0.55 ? value / 0.55 : 1.0;
        final enteringTurns = value <= 0.45 ? 0.0 : (value - 0.45) / 0.55;
        final showEntering = value >= 0.5;

        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(children: [
            Positioned.fill(child: showEntering ? exiting : entering),
            Positioned.fill(
              child: showEntering
                  ? _BookPage(
                      angle: (1 - enteringTurns) * math.pi / 2,
                      shadow: (1 - enteringTurns).clamp(0.0, 1.0),
                      child: entering,
                    )
                  : _BookPage(
                      angle: -exitingTurns * math.pi / 2,
                      shadow: exitingTurns.clamp(0.0, 1.0),
                      child: exiting,
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class _BookPage extends StatelessWidget {
  const _BookPage({
    required this.angle,
    required this.shadow,
    required this.child,
  });

  final double angle;
  final double shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..rotateY(angle),
      child: Stack(children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withOpacity(0.08 * shadow),
                    Colors.black.withOpacity(0.28 * shadow),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.38, curve: Curves.easeOut),
    );
    final zoom = Tween<double>(begin: 0.8, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.14, 0.55, curve: Curves.easeOutBack),
    ));
    final glow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.12, end: 0.34), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.34, end: 0.18), weight: 55),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.95, curve: Curves.easeInOut),
    ));
    final taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.52, 0.9, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F3FF),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: fade.value,
                child: Transform.scale(
                  scale: zoom.value,
                  child: Container(
                    width: 154,
                    height: 154,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appPrimary.withOpacity(glow.value),
                          blurRadius: 42,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/hanapgawa-shaped-white-background-logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: taglineFade,
                child: const Text(
                  'HanapGawa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: appPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FadeTransition(
                opacity: taglineFade,
                child: const Text(
                  'Connecting Clients and Skilled Workers',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: appPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
