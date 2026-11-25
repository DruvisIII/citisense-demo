import 'dart:async';
import 'package:citisense/api_config.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:citisense/app_theme.dart';
import 'package:citisense/mascot.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:citisense/auth_session.dart';
import 'package:citisense/demo/demo_config.dart';
import 'package:citisense/demo/tutorial.dart';
import 'package:citisense/barangaySelection.dart';
import 'package:citisense/createAccount.dart';
import 'package:citisense/friendly_errors.dart';
import 'package:citisense/landing.dart';
import 'package:citisense/session_manager.dart';
import 'package:citisense/forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ------------------------------------------------------------
  // API URL
  // ------------------------------------------------------------

  static const String _loginUrl =
      // 'http://10.186.51.252/citisense/api/login.php';
      '$apiBaseUrl/login.php';
  //'http://10.127.214.252/citisense/api/login.php';
  //'http://192.168.83.252/citisense/api/login.php';

  // If your PC's IP changes, update the URL above.

  // Diagnostic switch: set to false only temporarily to test whether
  // sending an FCM token causes login.php to stall.
  static const bool _includeFcmTokenInLogin = !kDemoMode;

  // ------------------------------------------------------------
  // CONTROLLERS
  // ------------------------------------------------------------

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // ------------------------------------------------------------
  // VARIABLES
  // ------------------------------------------------------------

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (kDemoMode) {
      // The demo tutorial starts on this screen.
      void track() => DemoNav.loginFilled =
          _emailController.text.trim().isNotEmpty &&
          _passwordController.text.isNotEmpty;
      _emailController.addListener(track);
      _passwordController.addListener(track);
      track();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => TutorialController.instance.onLoginShown(),
      );
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // LOGIN
  // ------------------------------------------------------------

  Future<void> _login() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    // ----------------------------------------------------------
    // CHECK EMPTY FIELDS
    // ----------------------------------------------------------

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }

    // ----------------------------------------------------------
    // CHECK EMAIL FORMAT
    // ----------------------------------------------------------

    if (!kDemoMode && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // --------------------------------------------------------
      // GET FIREBASE CLOUD MESSAGING TOKEN
      // --------------------------------------------------------

      String? fcmToken;

      if (_includeFcmTokenInLogin) {
        try {
          debugPrint('[LOGIN] Retrieving FCM token...');

          fcmToken = await FirebaseMessaging.instance.getToken().timeout(
            const Duration(seconds: 5),
          );

          debugPrint(
            '[LOGIN] FCM token available: '
            '${fcmToken != null && fcmToken.isNotEmpty}',
          );
        } on TimeoutException {
          debugPrint(
            '[LOGIN] FCM token retrieval timed out; continuing login.',
          );
        } catch (e) {
          debugPrint('[LOGIN] FCM token unavailable; continuing login: $e');
        }
      }

      // --------------------------------------------------------
      // SEND LOGIN REQUEST TO PHP API
      // --------------------------------------------------------

      final Map<String, String> loginData = {
        'email': email,
        'password': password,
      };

      if (_includeFcmTokenInLogin && fcmToken != null && fcmToken.isNotEmpty) {
        loginData['fcmToken'] = fcmToken;
      }

      // Never print the password or the actual FCM token.
      final requestTimer = Stopwatch()..start();

      debugPrint('[LOGIN] Sending POST to $_loginUrl');

      debugPrint(
        '[LOGIN] Including FCM token: '
        '${loginData.containsKey('fcmToken')}',
      );

      late final http.Response response;

      try {
        response = await http
            .post(
              Uri.parse(_loginUrl),
              headers: {'Accept': 'application/json'},
              body: loginData,
            )
            .timeout(const Duration(seconds: 20));

        debugPrint(
          '[LOGIN] HTTP status: ${response.statusCode} '
          'after ${requestTimer.elapsedMilliseconds}ms',
        );
      } on TimeoutException {
        debugPrint(
          '[LOGIN] PHP HTTP POST timed out after '
          '${requestTimer.elapsedMilliseconds}ms. '
          'FCM included: ${loginData.containsKey('fcmToken')}',
        );

        throw TimeoutException('Login request timed out.');
      } finally {
        requestTimer.stop();
      }

      // --------------------------------------------------------
      // CHECK HTTP STATUS
      // --------------------------------------------------------

      if (response.statusCode != 200) {
        debugPrint('[LOGIN] Unexpected HTTP ${response.statusCode}');
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FriendlyErrors.fromResponse(response)),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      // --------------------------------------------------------
      // DECODE JSON RESPONSE
      // --------------------------------------------------------

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response received from server.');
      }

      // --------------------------------------------------------
      // LOGIN FAILED
      // --------------------------------------------------------

      if (decoded['success'] != true) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.fromMessage(
                decoded['message']?.toString(),
                fallback: FriendlyErrors.wrongLogin,
              ),
            ),
            backgroundColor: AppColors.danger,
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // GET USER DATA
      // --------------------------------------------------------

      // Session token for messages, comments and notifications.
      final String authToken = decoded['authToken']?.toString().trim() ?? '';

      final dynamic userData = decoded['user'];

      if (userData == null || userData is! Map || authToken.isEmpty) {
        throw Exception('Invalid user data received from server.');
      }

      final SessionUser sessionUser = SessionUser.fromJson(
        Map<String, dynamic>.from(userData),
      ).copyWith(email: userData['email']?.toString() ?? email);

      // --------------------------------------------------------
      // CHECK WHETHER BARANGAY EXISTS
      // --------------------------------------------------------

      final bool hasBarangay = sessionUser.hasBarangay;

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // --------------------------------------------------------
      // LOGIN SUCCESSFUL
      // --------------------------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login successful!'),
          backgroundColor: AppColors.success,
        ),
      );

      // --------------------------------------------------------
      // IF USER HAS NO BARANGAY
      // --------------------------------------------------------

      // Demo onboarding: first login -> choose the barangay, then Home.
      if (!hasBarangay && kDemoMode) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BarangaySelection(
              firstName: sessionUser.firstName,
              lastName: sessionUser.lastName,
              email: sessionUser.email,
              contactNumber: sessionUser.contactNo,
              password: '',
              registrationToken: '',
              demoUser: sessionUser,
              demoAuthToken: authToken,
            ),
          ),
        );
        return;
      }

      if (!hasBarangay) {
        AuthSession.start(null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has no assigned barangay. Please contact the administrator.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );

        return;
      }

      // --------------------------------------------------------
      // USER ALREADY HAS BARANGAY
      // Keep the session on this phone (stays logged in until Log Out),
      // then open Home with nothing behind it, so the back button never
      // returns to this page.
      // --------------------------------------------------------

      await AuthSession.save(authToken, sessionUser);

      if (!mounted) return;
      SessionManager.openHome(context, sessionUser);
    } catch (e) {
      // --------------------------------------------------------
      // OTHER ERRORS
      // --------------------------------------------------------

      debugPrint('[LOGIN] Error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.fromException(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,

      // --------------------------------------------------------
      // APP BAR
      // --------------------------------------------------------
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            // After Log Out this is the only page: go to the welcome page
            // instead of closing the app with an empty screen.
            if (Navigator.of(context).canPop()) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LandingPage()),
              );
            }
          },
        ),
      ),

      // --------------------------------------------------------
      // BODY
      // --------------------------------------------------------
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ------------------------------------------------
              // MASCOT WITH CITY (logo artwork, no frame or text)
              // ------------------------------------------------
              Center(
                child: Image.asset(
                  'assets/citisense_mascot_scene.png',
                  height: 170,
                  fit: BoxFit.contain,
                  // Falls back to the drawn mascot if the image is missing.
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    width: 150,
                    height: 150,
                    child: CitiMascot(pose: MascotPose.thumbsUp),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ------------------------------------------------
              // TITLE
              // ------------------------------------------------
              const Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Welcome back to\n'),
                      TextSpan(
                        text: 'CitiSense',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: AppText.pageTitle,
                ),
              ),

              const SizedBox(height: 8),

              const Center(
                child: Text(
                  'Log in to continue reporting and tracking issues.',
                  textAlign: TextAlign.center,
                  style: AppText.subtitle,
                ),
              ),

              const SizedBox(height: 28),

              if (kDemoMode) ...[
                _DemoAccountsHint(
                  onPick: (account) => setState(() {
                    _emailController.text = account.username;
                    _passwordController.text = account.password;
                  }),
                ),
                const SizedBox(height: 20),
              ],

              // ------------------------------------------------
              // EMAIL
              // ------------------------------------------------
              const Text(
                kDemoMode ? 'Username or email' : 'Email',
                style: AppText.fieldLabel,
              ),

              const SizedBox(height: 8),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: kDemoMode ? 'e.g. tester1' : 'Enter your email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // PASSWORD
              // ------------------------------------------------
              const Text('Password', style: AppText.fieldLabel),

              const SizedBox(height: 8),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_isLoading) _login();
                },
                style: const TextStyle(fontFamily: appFontFamily, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),

              // ------------------------------------------------
              // FORGOT PASSWORD
              // ------------------------------------------------
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(fontSize: 13, fontFamily: appFontFamily),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ------------------------------------------------
              // LOGIN BUTTON
              // ------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: kDemoMode ? DemoKeys.loginButton : null,
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Log In'),
                ),
              ),

              const SizedBox(height: 28),

              // ------------------------------------------------
              // SIGN UP
              // ------------------------------------------------
              // Full width so the text is centered on the page (the column
              // aligns its children to the left).
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: appFontFamily,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                              // Replace Log In with Create Account so going
                              // back between them never stacks pages.
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateAccount(),
                                ),
                              );
                            },
                      child: const Text('Sign Up', style: AppText.link),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo only: the test accounts, tap one to fill the form.
class _DemoAccountsHint extends StatelessWidget {
  const _DemoAccountsHint({required this.onPick});

  final ValueChanged<DemoAccount> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: DemoKeys.demoAccounts,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demo accounts (tap one to fill in)',
            style: TextStyle(
              fontFamily: appHeadingFontFamily,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Username tester1 to tester5, password demo1 to demo5 '
            '(e.g. tester1 / demo1).',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final account in kDemoAccounts)
                ActionChip(
                  label: Text('${account.username} / ${account.password}'),
                  onPressed: () => onPick(account),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
