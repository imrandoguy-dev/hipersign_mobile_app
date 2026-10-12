import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _otp = TextEditingController();
  bool _busy = false;
  bool _showServer = false;
  bool _obscure = true;
  String? _error;
  String? _tmpId;
  String? _otpPrompt;

  @override
  void initState() {
    super.initState();
    final s = context.read<SessionController>();
    _server.text = s.server ?? SessionController.defaultServer;
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || (_pass.text.isEmpty && _tmpId == null)) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().signIn(
            _server.text,
            _user.text.trim(),
            _pass.text,
            otp: _tmpId == null ? null : _otp.text.trim(),
            tmpId: _tmpId,
          );
    } on TwoFactorRequired catch (t) {
      setState(() {
        _tmpId = t.tmpId;
        _otpPrompt = t.prompt;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'NOT_FOUND'
          ? 'This server does not have Hipersign Mobile installed. Check the server address.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Could not sign in. Check the server address and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = context.watch<SessionController>().notice;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 24),
                  const Text('Hipersign',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: HsColors.accent)),
                  const SizedBox(height: 6),
                  const Text('Sign in with your company ERP account',
                      style: TextStyle(color: HsColors.textSecondary)),
                  const SizedBox(height: 28),
                  if (notice != null && _error == null) ...[
                    _Banner(text: notice),
                    const SizedBox(height: 12),
                  ],
                  if (_tmpId == null) ...[
                    TextField(
                      controller: _user,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(_otpPrompt ?? 'Enter the verification code.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Verification code', prefixIcon: Icon(Icons.verified_user_outlined)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_showServer)
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Server address', prefixIcon: Icon(Icons.dns_outlined)),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showServer = true),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text(Uri.tryParse(ApiClient.normalizeServer(_server.text))?.host ?? 'Server'),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    _Banner(text: _error!, error: true),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_tmpId == null ? 'Sign in' : 'Verify'),
                  ),
                  if (_tmpId != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _tmpId = null;
                        _otp.clear();
                      }),
                      child: const Text('Back'),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFF4A2424) : const Color(0xFF3A2E1B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}
