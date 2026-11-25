import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:citisense/demo/demo_config.dart';
import 'package:citisense/live_updates.dart';

// ============================================================
// DEMO STORE
// ------------------------------------------------------------
// All demo data lives here and is saved per browser with
// shared_preferences (survives a refresh). The mock backend
// (demo_backend.dart) reads and writes this store, so the app's
// screens keep calling the same PHP endpoints as before.
//
// Scripted lifecycle of the tester's report (no random timers):
//   none -> pending      report submitted
//   pending -> progress  tester opens the Notifications tab
//   progress -> resolved tester returns to My Reports after the
//                        barangay replied in the follow-up chat
//   resolved -> rated    tester submits the rating
// ============================================================

enum DemoStage { none, pending, progress, resolved, rated }

class DemoStore extends ChangeNotifier {
  DemoStore._();

  static final DemoStore instance = DemoStore._();

  static const String _stateKey = 'demo_state_v1';

  SharedPreferences? _prefs;
  Map<String, dynamic> _state = {};

  /// True while the scripted barangay reply is "typing".
  final ValueNotifier<bool> adminTyping = ValueNotifier<bool>(false);

  /// Short in-app banner text for a new notification (null = hidden).
  final ValueNotifier<String?> banner = ValueNotifier<String?>(null);

  /// Sample picked in the report form (used by the fake AI).
  DemoSample? lastSample;

  Timer? _bannerTimer;

  // ------------------------------------------------------------
  // LOAD / SAVE / RESET
  // ------------------------------------------------------------

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_stateKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _state = decoded;
      }
    } catch (e) {
      debugPrint('[DEMO] Could not read saved demo data: $e');
    }
    if (_state['version'] != 1) _state = _initialState();

    // A refresh during the 2-second "typing" pause: deliver the reply now.
    final pending = _state['pendingReply'];
    if (pending is Map) {
      _deliverReply(Map<String, dynamic>.from(pending));
    }
  }

  Future<void> _save() async {
    try {
      await _prefs?.setString(_stateKey, jsonEncode(_state));
    } catch (e) {
      debugPrint('[DEMO] Could not save demo data: $e');
    }
  }

  /// Restores the starting data (keeps the user logged in).
  Future<void> reset() async {
    _state = _initialState();
    lastSample = null;
    adminTyping.value = false;
    banner.value = null;
    await _save();
    notifyListeners();
    LiveUpdates.instance.notifyChanged();
  }

  static String _iso(DateTime time) => time.toUtc().toIso8601String();

  Map<String, dynamic> _initialState() {
    final now = DateTime.now();
    return {
      'version': 1,
      'nextReportNo': 32,
      'demoReportID': null,
      'stage': DemoStage.none.name,
      'adminReplied': false,
      'nextId': 100,
      'reports': [
        _report(
          id: 'REP030',
          categoryID: 'CATE003',
          statusID: 'STAT003',
          image: kDemoSamples[3].asset,
          description: 'Large pothole near the basketball court.',
          date: now.subtract(const Duration(days: 12)),
          latitude: 10.2928,
          longitude: 123.8826,
        ),
        _report(
          id: 'REP031',
          categoryID: 'CATE001',
          statusID: 'STAT002',
          image: kDemoSamples[2].asset,
          description: 'Uncollected garbage beside the chapel.',
          date: now.subtract(const Duration(days: 4)),
          latitude: 10.2943,
          longitude: 123.8851,
        ),
      ],
      'notifications': [
        {
          'id': 'N1',
          'type': 'report',
          'kind': 'status',
          'reportID': 'REP031',
          'title': 'Report Update',
          'status': 'In progress',
          'message': 'Your report REP031 is now In progress.',
          'timestamp': _iso(now.subtract(const Duration(days: 3))),
          'isRead': true,
        },
      ],
      'announcements': [
        {
          'announceID': 'ANN001',
          'userID': 'ADMIN',
          'barangayID': kDemoBarangayID,
          'barangayName': kDemoBarangayName,
          'title': 'Clean-up drive this Saturday',
          'content':
              'Join our barangay clean-up drive this Saturday at 7:00 AM. '
              'Meet at the barangay hall. (Sample announcement for the demo.)',
          'datePosted': _iso(now.subtract(const Duration(days: 1))),
          'postedBy': null,
          'commentCount': 0,
          'images': [],
        },
      ],
      'messages': [],
      'feedback': {
        'REP030': {
          'isFixed': true,
          'rating': 4,
          'comment': 'Fixed within a week.',
          'updatedAt': _iso(now.subtract(const Duration(days: 9))),
        },
      },
      'statusLog': {
        'REP030': [
          _log(
            'Your report was received.',
            now.subtract(const Duration(days: 12)),
          ),
          _log(
            'Your report is now In progress.',
            now.subtract(const Duration(days: 11)),
          ),
          _log(
            'Your report has been resolved.',
            now.subtract(const Duration(days: 10)),
          ),
        ],
        'REP031': [
          _log(
            'Your report was received.',
            now.subtract(const Duration(days: 4)),
          ),
          _log(
            'Your report is now In progress.',
            now.subtract(const Duration(days: 3)),
          ),
        ],
      },
    };
  }

  static Map<String, dynamic> _log(String message, DateTime at) => {
    'type': 'system',
    'message': message,
    'createdAt': _iso(at),
  };

  static const Map<String, String> _categoryNames = {
    'CATE001': 'Waste Accumulation',
    'CATE003': 'Road Potholes',
    'CATE004': 'Others',
  };

  static const Map<String, String> _statusNames = {
    'STAT001': 'Pending',
    'STAT002': 'In Progress',
    'STAT003': 'Resolved',
  };

  Map<String, dynamic> _report({
    required String id,
    required String categoryID,
    required String statusID,
    required String image,
    required String description,
    required DateTime date,
    String address = kDemoAddress,
    double latitude = kDemoLatitude,
    double longitude = kDemoLongitude,
  }) {
    return {
      'reportID': id,
      'userID': '',
      'barangayID': kDemoBarangayID,
      'categoryID': categoryID,
      'statusID': statusID,
      'title': '',
      'description': description,
      'noOfReports': 1,
      // Local time without a zone, like the real API's SQL DATETIME.
      'dateReported': date.toIso8601String().split('.').first,
      'timeline': null,
      'categoryName': _categoryNames[categoryID] ?? 'Others',
      'statusName': _statusNames[statusID] ?? '',
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'imagePath': image,
    };
  }

  // ------------------------------------------------------------
  // GETTERS
  // ------------------------------------------------------------

  List<Map<String, dynamic>> _list(String key) =>
      ((_state[key] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// Web address of a bundled asset (Flutter web serves assets/<key>).
  static String assetUrl(String asset) =>
      Uri.base.resolve('assets/$asset').toString();

  List<Map<String, dynamic>> reportsFor(String userID) {
    final list = _list('reports')
        .map(
          (r) => {
            ...r,
            'userID': userID,
            'imagePath': assetUrl('${r['imagePath']}'),
          },
        )
        .toList();
    list.sort(
      (a, b) => '${b['dateReported']}'.compareTo('${a['dateReported']}'),
    );
    return list;
  }

  Map<String, dynamic>? reportById(String reportID) {
    for (final r in _list('reports')) {
      if (r['reportID'] == reportID) return r;
    }
    return null;
  }

  List<Map<String, dynamic>> get notifications {
    final list = [
      ..._list('notifications'),
      for (final a in _list('announcements'))
        {
          'id': a['announceID'],
          'type': 'announcement',
          'kind': 'announcement',
          'reportID': null,
          'title': a['title'],
          'message': a['content'],
          'barangayName': kDemoBarangayName,
          'timestamp': a['datePosted'],
          'isRead':
              (_state['readAnnouncements'] as List?)?.contains(
                a['announceID'],
              ) ??
              false,
        },
    ];
    list.sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));
    return list;
  }

  List<Map<String, dynamic>> get announcements => _list('announcements');

  int get unreadCount => notifications.where((n) => n['isRead'] != true).length;

  String? get demoReportID => _state['demoReportID'] as String?;

  DemoStage get stage => DemoStage.values.firstWhere(
    (s) => s.name == _state['stage'],
    orElse: () => DemoStage.none,
  );

  bool get adminReplied => _state['adminReplied'] == true;

  /// Barangay chosen after the first login (onboarding).
  bool get onboarded => _state['onboarded'] == true;

  Future<void> setOnboarded() async {
    _state['onboarded'] = true;
    await _commit();
  }

  bool get hasAskedFollowUp => _list(
    'messages',
  ).any((m) => m['fromBarangay'] != true && m['reportID'] == demoReportID);

  List<Map<String, dynamic>> get messages => _list('messages');

  Map<String, dynamic>? feedbackFor(String reportID) {
    final all = _state['feedback'];
    if (all is Map && all[reportID] is Map) {
      return Map<String, dynamic>.from(all[reportID] as Map);
    }
    return null;
  }

  List<Map<String, dynamic>> statusLogFor(String reportID) {
    final all = _state['statusLog'];
    if (all is Map && all[reportID] is List) {
      return (all[reportID] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ------------------------------------------------------------
  // CHANGES
  // ------------------------------------------------------------

  String _nextId() {
    final id = (_state['nextId'] as int? ?? 100) + 1;
    _state['nextId'] = id;
    return 'N$id';
  }

  void _addStatusLog(String reportID, String message) {
    final all = Map<String, dynamic>.from(_state['statusLog'] as Map? ?? {});
    final list = List<dynamic>.from(all[reportID] as List? ?? const []);
    list.add(_log(message, DateTime.now()));
    all[reportID] = list;
    _state['statusLog'] = all;
  }

  void _setStatus(String reportID, String statusID) {
    _state['reports'] = _list('reports').map((r) {
      if (r['reportID'] != reportID) return r;
      return {...r, 'statusID': statusID, 'statusName': _statusNames[statusID]};
    }).toList();
  }

  void _addNotification(String reportID, String status, String message) {
    final list = _list('notifications');
    list.add({
      'id': _nextId(),
      'type': 'report',
      'kind': 'status',
      'reportID': reportID,
      'title': 'Report Update',
      'status': status,
      'message': message,
      'timestamp': _iso(DateTime.now()),
      'isRead': false,
    });
    _state['notifications'] = list;
    showBanner(message);
  }

  void showBanner(String message) {
    _bannerTimer?.cancel();
    banner.value = message;
    _bannerTimer = Timer(const Duration(seconds: 4), () => banner.value = null);
  }

  Future<void> _commit() async {
    await _save();
    notifyListeners();
    LiveUpdates.instance.notifyChanged();
  }

  /// submit_report.php
  Future<String> submitReport({
    required String categoryID,
    required String description,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    final no = _state['nextReportNo'] as int? ?? 32;
    final id = 'REP${no.toString().padLeft(3, '0')}';
    _state['nextReportNo'] = no + 1;

    final list = _list('reports');
    list.add(
      _report(
        id: id,
        categoryID: categoryID,
        statusID: 'STAT001',
        image: (lastSample ?? kDemoSamples.first).asset,
        description: description,
        date: DateTime.now(),
        address: address.isEmpty ? kDemoAddress : address,
        latitude: latitude ?? kDemoLatitude,
        longitude: longitude ?? kDemoLongitude,
      ),
    );
    _state['reports'] = list;
    _addStatusLog(id, 'Your report was received.');

    // The first report submitted is the one the tutorial follows.
    if (demoReportID == null || stage == DemoStage.none) {
      _state['demoReportID'] = id;
      _state['stage'] = DemoStage.pending.name;
      _state['adminReplied'] = false;
    }
    await _commit();
    return id;
  }

  /// Pending -> In progress (tester opened the Notifications tab).
  Future<void> markInProgress() async {
    final id = demoReportID;
    if (id == null || stage != DemoStage.pending) return;
    _state['stage'] = DemoStage.progress.name;
    _setStatus(id, 'STAT002');
    _addStatusLog(id, 'Your report is now In progress.');
    _addNotification(id, 'In progress', 'Your report $id is now In progress');
    await _commit();
  }

  /// In progress -> Resolved (back on My Reports after the chat reply).
  Future<void> markResolved() async {
    final id = demoReportID;
    if (id == null || stage != DemoStage.progress || !adminReplied) return;
    _state['stage'] = DemoStage.resolved.name;
    _setStatus(id, 'STAT003');
    _addStatusLog(id, 'Your report has been resolved.');
    _addNotification(id, 'Resolved', 'Your report $id has been resolved');
    await _commit();
  }

  Future<void> markNotificationRead(String type, String id) async {
    if (type == 'announcement') {
      final read = List<dynamic>.from(
        _state['readAnnouncements'] as List? ?? const [],
      );
      if (!read.contains(id)) read.add(id);
      _state['readAnnouncements'] = read;
    } else {
      _state['notifications'] = _list(
        'notifications',
      ).map((n) => n['id'] == id ? {...n, 'isRead': true} : n).toList();
    }
    await _commit();
  }

  Future<void> markAllRead() async {
    _state['notifications'] = _list(
      'notifications',
    ).map((n) => {...n, 'isRead': true}).toList();
    _state['readAnnouncements'] = [
      for (final a in _list('announcements')) a['announceID'],
    ];
    await _commit();
  }

  Future<void> submitFeedback({
    required String reportID,
    required bool isFixed,
    required int rating,
    required String comment,
  }) async {
    final all = Map<String, dynamic>.from(_state['feedback'] as Map? ?? {});
    all[reportID] = {
      'isFixed': isFixed,
      'rating': rating,
      'comment': comment,
      'updatedAt': _iso(DateTime.now()),
    };
    _state['feedback'] = all;
    if (reportID == demoReportID && stage == DemoStage.resolved) {
      _state['stage'] = DemoStage.rated.name;
    }
    await _commit();
  }

  /// resident_messages.php action=send. The barangay "replies" after
  /// 2 seconds with a scripted message.
  Future<void> sendMessage(String text, String reportID) async {
    final list = _list('messages');
    final key = 'm:${_nextId()}';
    list.add({
      'key': key,
      'id': key,
      'reportID': reportID,
      'reportLabel': _reportLabel(reportID),
      'fromBarangay': false,
      'isMine': true,
      'canDelete': true,
      'name': 'You',
      'message': text,
      'createdAt': _iso(DateTime.now()),
      'replyTo': null,
    });
    _state['messages'] = list;

    final isFollowUp =
        reportID.isNotEmpty &&
        reportID == demoReportID &&
        !adminReplied &&
        stage == DemoStage.progress;
    final reply = {
      'reportID': reportID,
      'text': isFollowUp ? kDemoAdminFollowUpReply : kDemoAdminGenericReply,
      'followUp': isFollowUp,
    };
    _state['pendingReply'] = reply;
    await _commit();

    adminTyping.value = true;
    Timer(const Duration(seconds: 2), () => _deliverReply(reply));
  }

  void _deliverReply(Map<String, dynamic> reply) {
    if (_state['pendingReply'] == null) return;
    final reportID = reply['reportID']?.toString() ?? '';
    final list = _list('messages');
    final key = 'b:${_nextId()}';
    list.add({
      'key': key,
      'id': key,
      'reportID': reportID,
      'reportLabel': _reportLabel(reportID),
      'fromBarangay': true,
      'isMine': false,
      'canDelete': false,
      'name': 'Barangay Official',
      'message': reply['text'],
      'createdAt': _iso(DateTime.now()),
      'replyTo': null,
    });
    _state['messages'] = list;
    _state.remove('pendingReply');
    if (reply['followUp'] == true) _state['adminReplied'] = true;
    adminTyping.value = false;
    _commit();
  }

  Future<void> deleteMessage(String key) async {
    _state['messages'] = _list(
      'messages',
    ).where((m) => m['key'] != key).toList();
    await _commit();
  }

  String _reportLabel(String reportID) {
    if (reportID.isEmpty) return '';
    final report = reportById(reportID);
    final category = report?['categoryName']?.toString() ?? '';
    return category.isEmpty ? reportID : '$reportID · $category';
  }

  List<Map<String, dynamic>> messageReportOptions() => [
    for (final r in reportsFor(''))
      {
        'reportID': r['reportID'],
        'categoryName': r['categoryName'],
        'statusID': r['statusID'],
        'statusName': r['statusName'],
        'imagePath': r['imagePath'],
        'dateReported': r['dateReported'],
      },
  ];
}
