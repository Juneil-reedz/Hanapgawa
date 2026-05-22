import 'package:flutter/material.dart';

import 'core/api/marketplace_api.dart';
import 'core/local/local_db.dart';
import 'core/local/sync_service.dart';
import 'core/models/models.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/discover/suggested_users_sheet.dart';
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

  var _ready = false;
  var _splashComplete = false;
  var _showOnboarding = false;
  var _showFollowSuggestions = false;
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
    _exitingWidget = OnboardingScreen(onDone: () async {});
    _slideCtrl.forward(from: 0);
    setState(() => _showOnboarding = false);
  }

  Future<void> _setSession(AuthResponse auth) async {
    await api.persistSession(auth);
    _slideCtrl.duration = const Duration(milliseconds: 420);
    final showSuggestions = !api.hasSeenFollowSuggestions;
    setState(() {
      _exitingWidget = AuthScreen(api: api, onAuthenticated: (_) async {});
      _user = auth.user;
      _showFollowSuggestions = showSuggestions;
    });
    _slideCtrl.forward(from: 0);
  }

  Future<void> _finishFollowSuggestions() async {
    api.markFollowSuggestionsSeen();
    _slideCtrl.duration = const Duration(milliseconds: 420);
    setState(() {
      _exitingWidget =
          SuggestedUsersOnboarding(api: api, onDone: () {});
      _showFollowSuggestions = false;
    });
    _slideCtrl.forward(from: 0);
  }

  Future<void> _logout() async {
    _slideCtrl.duration = const Duration(milliseconds: 420);
    await api.clearSession();
    setState(() {
      _exitingWidget = ShellScreen(api: api, onLogout: () async {});
      _user = null;
      _showOnboarding = false;
    });
    _slideCtrl.forward(from: 0);
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
    if (_showFollowSuggestions && _user != null) {
      return SuggestedUsersOnboarding(
          key: const ValueKey('follow_suggestions'),
          api: api,
          onDone: _finishFollowSuggestions);
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
