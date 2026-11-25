// ============================================================
// DEMO MODE CONFIGURATION
// ------------------------------------------------------------
// Demo mode is ON only when the app is built with
//   --dart-define=DEMO=true
// Without it, kDemoMode is false and the app behaves exactly as
// before (real PHP backend, Firebase, camera, maps...).
// ============================================================

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

const bool kDemoMode = bool.fromEnvironment('DEMO');

/// Google Form opened at the end of the tutorial and from Settings.
/// Change only this line to point testers to another form.
const String kFeedbackFormUrl =
    'https://docs.google.com/forms/d/e/1FAIpQLSdFhb3sdzDysQU_EwS98TANqSWUi0Q7natS1ppnkQxUVKLygg/viewform';

/// Fake barangay used by every demo account.
const String kDemoBarangayID = 'BRGY-DULJO';
const String kDemoBarangayName = 'Duljo-Fatima';

/// Address saved with every demo report (the exact pin is saved too).
const String kDemoAddress = 'Duljo-Fatima, Cebu City, Cebu';

// ------------------------------------------------------------
// Map area for pinning (live OpenStreetMap map, no API key).
// The map opens on kDemoMapCenter and only accepts pins inside
// kDemoArea. These are APPROXIMATE Duljo-Fatima coordinates:
// check them once on the map and adjust here if needed
// (south-west corner first, then north-east corner).
// ------------------------------------------------------------
const double kDemoLatitude = 10.2935;
const double kDemoLongitude = 123.8840;
const LatLng kDemoMapCenter = LatLng(kDemoLatitude, kDemoLongitude);
final LatLngBounds kDemoArea = LatLngBounds(
  const LatLng(10.2895, 123.8790),
  const LatLng(10.2975, 123.8890),
);

class DemoAccount {
  const DemoAccount(
    this.username,
    this.password,
    this.firstName,
    this.lastName,
    this.email,
  );

  final String username;
  final String password;
  final String firstName;
  final String lastName;
  final String email;

  String get userID => 'DEMO-$username';
}

/// Hard-coded demo logins (fake names and e-mails only).
const List<DemoAccount> kDemoAccounts = [
  DemoAccount('tester1', 'demo1', 'Ana', 'Reyes', 'tester1@demo.test'),
  DemoAccount('tester2', 'demo2', 'Ben', 'Cruz', 'tester2@demo.test'),
  DemoAccount('tester3', 'demo3', 'Carla', 'Santos', 'tester3@demo.test'),
  DemoAccount('tester4', 'demo4', 'Dan', 'Mendoza', 'tester4@demo.test'),
  DemoAccount('tester5', 'demo5', 'Ella', 'Garcia', 'tester5@demo.test'),
];

/// Accepts "tester1" or "tester1@demo.test" (any letter case).
DemoAccount? findDemoAccount(String login, String password) {
  final value = login.trim().toLowerCase();
  for (final account in kDemoAccounts) {
    if ((value == account.username || value == account.email) &&
        password == account.password) {
      return account;
    }
  }
  return null;
}

DemoAccount? demoAccountById(String userID) {
  for (final account in kDemoAccounts) {
    if (account.userID == userID) return account;
  }
  return null;
}

/// Bundled sample photos the tester can choose instead of the camera.
/// Replace the files in assets/demo/ with real photos (same names).
class DemoSample {
  const DemoSample(this.asset, this.label, this.category, this.reason);

  final String asset;
  final String label;

  /// Fixed "AI" result for this photo (one of the app's categories).
  final String category;
  final String reason;
}

const List<DemoSample> kDemoSamples = [
  DemoSample(
    'assets/demo/sample_waste_1.jpg',
    'Garbage pile',
    'Waste Accumulation',
    'Garbage bags and litter detected (simulated).',
  ),
  DemoSample(
    'assets/demo/sample_pothole_1.jpg',
    'Pothole',
    'Road Potholes',
    'Road surface damage detected (simulated).',
  ),
  DemoSample(
    'assets/demo/sample_waste_2.jpg',
    'Litter by the road',
    'Waste Accumulation',
    'Scattered waste detected (simulated).',
  ),
  DemoSample(
    'assets/demo/sample_pothole_2.jpg',
    'Damaged road',
    'Road Potholes',
    'Cracks and a pothole detected (simulated).',
  ),
];

const String kDemoStaticMapAsset = 'assets/demo/static_map.png';

/// Scripted texts.
const String kDemoFollowUpMessage =
    'Hello, may I ask for an update on my report?';
const String kDemoAdminFollowUpReply = 'Currently working for it.';
const String kDemoAdminGenericReply = 'Thanks, we have noted your message.';
const String kDemoFeedbackComment =
    'The issue was fixed quickly. Thank you, barangay!';
