import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/session.dart';
import '../features/activities/activity_detail_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/trials/trial_detail_screen.dart';
import 'nav.dart';
import 'theme.dart';

class HipersignApp extends StatelessWidget {
  const HipersignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hipersign',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/activity/')) {
          final id = name.substring('/activity/'.length);
          return MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: id), settings: settings);
        }
        if (name.startsWith('/trial/')) {
          final id = name.substring('/trial/'.length);
          return MaterialPageRoute(builder: (_) => TrialDetailScreen(bookingId: id), settings: settings);
        }
        return null;
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return switch (session.status) {
      SessionStatus.restoring => const Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image(image: AssetImage('assets/branding/logo.png'), width: 96, height: 96),
              SizedBox(height: 16),
              Text('Hipersign', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: HsColors.accent)),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ]),
          ),
        ),
      SessionStatus.signedOut => const LoginScreen(),
      SessionStatus.signedIn => const HomeShell(),
    };
  }
}
