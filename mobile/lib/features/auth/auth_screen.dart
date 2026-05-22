import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/message_banner.dart';

final _googleSignIn = GoogleSignIn(
  serverClientId:
      '1051761935414-p8lv7ceqb0qki482upci225ebukgm21n.apps.googleusercontent.com',
);

enum AuthMode { login, register, verify }

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: Color(0xFFDADADA)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Google "G" logo colours
        _GoogleG(),
        const SizedBox(width: 10),
        const Text('Continue with Google',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ]),
    );
  }
}

class _GoogleG extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Simple coloured circle as placeholder for the Google G
    final paint = Paint()..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    // Blue arc
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -1.57, 3.14, true, paint);
    // Red arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 1.57, 1.57, true, paint);
    // Yellow arc
    paint.color = const Color(0xFFFBBC04);
    canvas.drawArc(rect, 3.14, 0.79, true, paint);
    // Green arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 3.93, 0.78, true, paint);
    // White inner circle
    paint.color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r * 0.6, paint);
    // Blue G bar
    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(cx, cy - r * 0.18, r, r * 0.36), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AuthScreen extends StatefulWidget {
  const AuthScreen(
      {super.key, required this.api, required this.onAuthenticated});
  final MarketplaceApi api;
  final Future<void> Function(AuthResponse auth) onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  var _mode = AuthMode.login;
  var _loading = false;
  var _showPassword = false;
  var _message = '';
  var _messageIsError = false;

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_mode == AuthMode.verify) {
      await _verifyEmail();
      return;
    }
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _setMessage('Please enter your email and password.', true);
      return;
    }
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      if (_mode == AuthMode.login) {
        await widget.onAuthenticated(
            await widget.api.login(_email.text.trim(), _password.text));
      } else {
        final res = await widget.api.register(
            _email.text.trim(), _password.text, _fullName.text.trim());
        setState(() {
          _mode = AuthMode.verify;
          _loading = false;
          _messageIsError = false;
          _message = res.devVerificationCode == null
              ? 'Account created. Check your email for the verification code.'
              : 'Account created. Development verification code: ${res.devVerificationCode}';
        });
      }
    } catch (error) {
      _setMessage(error.toString(), true);
    } finally {
      if (mounted && _mode != AuthMode.verify) setState(() => _loading = false);
    }
  }

  Future<void> _verifyEmail() async {
    if (_email.text.trim().isEmpty || _code.text.trim().isEmpty) {
      _setMessage('Enter your email and verification code.', true);
      return;
    }
    setState(() => _loading = true);
    try {
      final auth =
          await widget.api.verifyEmail(_email.text.trim(), _code.text.trim());
      await widget.onAuthenticated(auth);
    } catch (error) {
      _setMessage(error.toString(), true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_email.text.trim().isEmpty) {
      _setMessage('Email is required before requesting a new code.', true);
      return;
    }
    setState(() => _loading = true);
    try {
      final code = await widget.api.resendVerificationCode(_email.text.trim());
      _setMessage(
        code == null
            ? 'A new verification code was sent to your email.'
            : 'New verification code: $code',
        false,
      );
    } catch (error) {
      _setMessage(error.toString(), true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _loading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        _setMessage('Google Sign-In did not return a credential.', true);
        return;
      }
      final json = await widget.api.signInWithGoogleRaw(idToken);
      if (json['emailVerificationRequired'] == true) {
        // New or unverified user: show verification screen
        final email = json['email']?.toString() ?? '';
        final devCode = json['devVerificationCode']?.toString();
        setState(() {
          _mode = AuthMode.verify;
          _email.text = email;
          _loading = false;
          _messageIsError = false;
          _message = devCode == null
              ? 'Account created. A verification code was sent to $email.'
              : 'Account created. Dev code: $devCode';
        });
      } else {
        await widget.onAuthenticated(AuthResponse.fromJson(json));
      }
    } catch (error) {
      _setMessage(error.toString(), true);
    } finally {
      if (mounted && _mode != AuthMode.verify) {
        setState(() => _loading = false);
      }
    }
  }

  void _setMessage(String value, bool isError) {
    setState(() {
      _loading = false;
      _message = friendlyError(value);
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      AuthMode.login => 'Welcome back',
      AuthMode.register => 'Create account',
      AuthMode.verify => 'Verify email',
    };
    final subtitle = switch (_mode) {
      AuthMode.login => 'Sign in to your HanapGawa account.',
      AuthMode.register => 'Join the Tawi-Tawi service marketplace.',
      AuthMode.verify => 'Enter the 6-digit code sent to your email.',
    };

    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF7EC), appSurface],
              ),
            ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: appPrimary.withAlpha(24),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/hanapgawa-shaped-white-background-logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.handshake_outlined,
                            color: appPrimary,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: appMuted)),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: appPrimary.withAlpha(18),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            SegmentedButton<AuthMode>(
                              segments: const [
                                ButtonSegment(
                                    value: AuthMode.login,
                                    label: Text('Login')),
                                ButtonSegment(
                                    value: AuthMode.register,
                                    label: Text('Register')),
                              ],
                              selected: {
                                _mode == AuthMode.verify
                                    ? AuthMode.register
                                    : _mode
                              },
                              onSelectionChanged: (value) => setState(() {
                                _mode = value.first;
                                _message = '';
                              }),
                            ),
                            const SizedBox(height: 18),
                            if (_mode == AuthMode.register) ...[
                              TextField(
                                controller: _fullName,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    hintText: 'Juan dela Cruz'),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  hintText: 'you@example.com'),
                            ),
                            const SizedBox(height: 12),
                            if (_mode != AuthMode.verify)
                              TextField(
                                controller: _password,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                        () => _showPassword = !_showPassword),
                                    icon: Icon(_showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                  ),
                                ),
                              ),
                            if (_mode == AuthMode.verify)
                              TextField(
                                controller: _code,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                    labelText: 'Verification code',
                                    counterText: '',
                                    hintText: '123456'),
                              ),
                            if (_message.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              MessageBanner(
                                  message: _message, isError: _messageIsError),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Text(_mode == AuthMode.login
                                        ? 'Sign In'
                                        : _mode == AuthMode.register
                                            ? 'Create Account'
                                            : 'Verify Email'),
                              ),
                            ),
                            if (_mode == AuthMode.verify)
                              TextButton(
                                  onPressed: _loading ? null : _resendCode,
                                  child: const Text('Resend code')),
                            if (_mode != AuthMode.verify) ...[
                              const SizedBox(height: 16),
                              const Row(children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('or',
                                      style: TextStyle(
                                          color: appMuted, fontSize: 13)),
                                ),
                                Expanded(child: Divider()),
                              ]),
                              const SizedBox(height: 16),
                              _GoogleSignInButton(onTap: _handleGoogleSignIn),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
          ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}
