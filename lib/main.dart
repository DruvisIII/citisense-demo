import 'package:citisense/api_client.dart';
import 'package:citisense/app_settings.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/demo/demo_backend.dart';
import 'package:citisense/demo/demo_config.dart';
import 'package:citisense/demo/demo_store.dart';
import 'package:citisense/demo/tutorial.dart';
import 'package:citisense/session_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'push_notification_service.dart';

// Handles FCM data messages received in the background.
// Android shows notification messages automatically when
// the app is in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('Background FCM message: ${message.messageId}');
}

Future<void> main() async {
  // Web demo (--dart-define=DEMO=true): no backend, Firebase or push.
  // Every http call inside this zone goes to the local mock backend.
  if (kDemoMode) {
    return http.runWithClient(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await DemoStore.instance.load();
      await TutorialController.instance.load();
      ApiClient.onSessionExpired = SessionManager.sessionExpired;
      runApp(const MyApp());
    }, createDemoClient);
  }

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await PushNotificationService.initialize();

  // A session the server no longer accepts logs the user out.
  ApiClient.onSessionExpired = SessionManager.sessionExpired;

  runApp(const MyApp());
}

/// Browser text size x in-app Font Size, capped so layouts do not break.
TextScaler _clampedScaler(TextScaler system, double scale) {
  final factor = (system.scale(14) / 14 * scale).clamp(0.85, 1.6);
  return TextScaler.linear(factor);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appFontScale,
      builder: (context, scale, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: kDemoMode ? 'Barangay Reports Demo' : 'CitiSense',
          theme: AppTheme.light,
          navigatorKey: appNavigatorKey,
          home: const StartupPage(),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);

            // The chosen Font Size applies to the whole app at once.
            // (Demo: the browser's own text size is kept and multiplied.)
            final app = MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: kDemoMode
                    ? _clampedScaler(mediaQuery.textScaler, scale)
                    : TextScaler.linear(scale),
              ),
              child: child!,
            );
            if (!kDemoMode) return app;
            return DemoPhoneFrame(child: DemoLayer(child: app));
          },
        );
      },
    );
  }
}

// ============================================================
// STARTUP
// ------------------------------------------------------------
// Opens Home straight away when the phone has a saved session,
// otherwise the Landing page. Logging in is only needed again
// after Log Out or when the server says the session expired.
// ============================================================

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final result = await SessionManager.restore();
    if (!mounted) return;

    final user = AuthSession.user;
    final Widget next = result == RestoreResult.loggedIn && user != null
        ? SessionManager.homeFor(user)
        : SessionManager.loggedOutHome;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => next,
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 120,
              width: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/citisense logo image.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
