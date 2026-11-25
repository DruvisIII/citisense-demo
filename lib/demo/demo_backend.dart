import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citisense/demo/demo_config.dart';
import 'package:citisense/demo/demo_store.dart';

// ============================================================
// DEMO BACKEND
// ------------------------------------------------------------
// In demo mode main.dart runs the app inside http.runWithClient,
// so every existing http.get / http.post / MultipartRequest call
// lands here instead of the network. Each PHP endpoint the app
// uses gets the same JSON shape the real API returns, so the
// screens do not need to change. Nothing leaves the browser.
// ============================================================

http.Client createDemoClient() => MockClient(_handle);

String _iso(DateTime t) => t.toUtc().toIso8601String();

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode({'serverTime': _iso(DateTime.now()), ...body}),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _ok([Map<String, dynamic> extra = const {}]) =>
    _json({'success': true, 'message': 'OK', ...extra});

/// Reads form fields from a urlencoded, JSON or multipart body.
Map<String, String> _fields(http.Request request) {
  final type = request.headers['content-type'] ?? '';
  final fields = <String, String>{...request.url.queryParameters};
  try {
    if (type.contains('multipart/form-data')) {
      final boundary = RegExp(r'boundary=(.+)$').firstMatch(type)?.group(1);
      if (boundary != null) {
        final text = latin1.decode(request.bodyBytes);
        for (final part in text.split('--$boundary')) {
          final split = part.indexOf('\r\n\r\n');
          if (split < 0) continue;
          final head = part.substring(0, split);
          if (head.contains('filename=')) continue;
          final name = RegExp(r'name="([^"]+)"').firstMatch(head)?.group(1);
          if (name == null) continue;
          var value = part.substring(split + 4);
          if (value.endsWith('\r\n')) {
            value = value.substring(0, value.length - 2);
          }
          fields[name] = utf8.decode(latin1.encode(value));
        }
      }
    } else if (type.contains('application/json')) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        decoded.forEach((k, v) => fields['$k'] = '${v ?? ''}');
      }
    } else if (request.body.isNotEmpty) {
      fields.addAll(request.bodyFields);
    }
  } catch (_) {
    // Missing fields are treated as empty.
  }
  return fields;
}

Map<String, dynamic> _userJson(DemoAccount a) => {
  // No barangay until the tester picks one after the first login.
  'barangayID': DemoStore.instance.onboarded ? kDemoBarangayID : '',
  'userID': a.userID,
  'firstName': a.firstName,
  'lastName': a.lastName,
  'email': a.email,
  'contactNo': '09170000000',
  'profilePic': null,
};

Future<http.Response> _handle(http.Request request) async {
  final store = DemoStore.instance;
  final endpoint = request.url.pathSegments.isEmpty
      ? ''
      : request.url.pathSegments.last;
  final f = _fields(request);
  final userID = f['userID'] ?? '';

  // Feels like a network round-trip, but stays quick.
  await Future<void>.delayed(const Duration(milliseconds: 150));

  switch (endpoint) {
    case 'login.php':
      final account = findDemoAccount(f['email'] ?? '', f['password'] ?? '');
      if (account == null) {
        return _json({
          'success': false,
          'message':
              'Incorrect username or password. Try tester1 / demo1 '
              '(see the demo accounts below).',
        });
      }
      return _json({
        'success': true,
        'message': 'Login successful.',
        'authToken': 'demo-token-${account.username}',
        'user': _userJson(account),
      });

    case 'session.php':
      if (f['action'] == 'restore') {
        final token =
            request.headers['X-Auth-Token'] ??
            request.headers['x-auth-token'] ??
            '';
        final username = token.replaceFirst('demo-token-', '');
        final account = demoAccountById('DEMO-$username');
        if (account == null) {
          return _json({
            'success': false,
            'code': 'SESSION_EXPIRED',
            'message': 'Please log in again.',
          }, 401);
        }
        return _ok({'user': _userJson(account)});
      }
      return _ok();

    case 'get_profile.php':
      final account = demoAccountById(userID) ?? kDemoAccounts.first;
      return _ok({
        'data': {..._userJson(account), 'barangayName': kDemoBarangayName},
      });

    case 'get_barangays.php':
      return _ok({
        'data': [
          {'barangayID': kDemoBarangayID, 'barangayName': kDemoBarangayName},
        ],
      });

    case 'get_announcements.php':
      return _ok({'data': store.announcements});

    case 'announcement_comments.php':
      return _ok({'data': <dynamic>[], 'comments': <dynamic>[]});

    case 'get_my_reports.php':
      return _ok({'data': store.reportsFor(userID)});

    case 'get_notifications.php':
      return _ok({'data': store.notifications});

    case 'mark_notification_read.php':
      await store.markNotificationRead(f['type'] ?? '', f['id'] ?? '');
      return _ok();

    case 'mark_all_notifications_read.php':
      await store.markAllRead();
      return _ok();

    case 'classify_image.php':
      // Fake AI: fixed answer for the chosen sample, after a short pause.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final sample = store.lastSample ?? kDemoSamples.first;
      return _json({
        'success': true,
        'category': sample.category,
        'reason': sample.reason,
      });

    case 'register.php':
      // Demo onboarding: the barangay chosen after the first login.
      await store.setOnboarded();
      return _json({'success': true, 'message': 'Barangay saved.'});

    case 'submit_report.php':
      final id = await store.submitReport(
        categoryID: f['categoryID'] ?? 'CATE004',
        description: f['description'] ?? '',
        address: f['address'] ?? '',
        latitude: double.tryParse(f['latitude'] ?? ''),
        longitude: double.tryParse(f['longitude'] ?? ''),
      );
      return _json({
        'success': true,
        'message': 'Report submitted.',
        'data': {'reportID': id},
      });

    case 'get_report_thread.php':
      final reportID = f['reportID'] ?? '';
      final report = store.reportById(reportID);
      return _ok({
        'data': {
          'statusID': report?['statusID'] ?? 'STAT001',
          'items': store.statusLogFor(reportID),
          'feedback': store.feedbackFor(reportID),
        },
      });

    case 'submit_report_feedback.php':
      await store.submitFeedback(
        reportID: f['reportID'] ?? '',
        isFixed: f['isFixed'] == '1',
        rating: int.tryParse(f['rating'] ?? '') ?? 5,
        comment: f['comment'] ?? '',
      );
      return _json({'success': true, 'message': 'Thanks for your feedback!'});

    case 'resident_messages.php':
      final action = f['action'] ?? 'list';
      if (action == 'send') {
        await store.sendMessage(f['message'] ?? '', f['reportID'] ?? '');
      } else if (action == 'delete') {
        await store.deleteMessage(f['key'] ?? '');
      }
      return _ok({
        'barangayName': kDemoBarangayName,
        'data': store.messages,
        if (f['includeReports'] == '1' || action != 'list')
          'reports': store.messageReportOptions(),
      });
  }

  // Everything else (profile edits, passwords, OTP, app feedback...)
  // is simulated as a success so testers never hit an error.
  return _ok({'message': 'Done (simulated in the demo).', 'data': <dynamic>[]});
}
