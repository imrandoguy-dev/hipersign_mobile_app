import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/auth/session.dart';
import 'core/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final session = SessionController();
  // Restore in the background; the app shows a splash meanwhile.
  session.restore();
  runApp(ChangeNotifierProvider<SessionController>.value(value: session, child: const HipersignApp()));
}
