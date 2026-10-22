import 'package:flutter/material.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Routes that can arrive from notifications: "/activity/<id>", "/trial/<id>", "/whatsapp/<number>".
bool isDeepLink(String? route) =>
    route != null &&
    (route.startsWith('/activity/') ||
        route.startsWith('/trial/') ||
        route.startsWith('/whatsapp/') ||
        route.startsWith('/dev/') ||
        route.startsWith('/task/') ||
        route.startsWith('/report/') ||
        route.startsWith('/feedback/') ||
        route.startsWith('/concern/') ||
        route == '/target');

void showSnack(String message, {bool error = false}) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? HsColors.danger : null,
    ));
}
