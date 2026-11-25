import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:citisense/app_theme.dart';
import 'package:citisense/auth_session.dart';
import 'package:citisense/barangay_messages_page.dart';
import 'package:citisense/demo/demo_config.dart';
import 'package:citisense/demo/demo_store.dart';
import 'package:citisense/demo/open_url.dart';
import 'package:citisense/notification_router.dart';
import 'package:citisense/session_manager.dart';

// ============================================================
// DEMO TUTORIAL (coach marks)
// ------------------------------------------------------------
// A small custom Overlay placed above the Navigator (main.dart,
// MaterialApp.builder). It dims the screen, cuts a hole around the
// real widget for the current step (found through the GlobalKeys
// in DemoKeys) and shows a tooltip with Back / Next / Skip.
//
// Taps inside the hole reach the real widget, so testers do the
// actions themselves; the step advances automatically when they do.
// "Next" always works as a fallback (it performs the action for
// them), so nobody gets stuck. The step is saved in
// shared_preferences, so a refresh resumes at the right place.
// ============================================================

const int kTutorialSteps = 15;

/// GlobalKeys on the real widgets the tutorial highlights.
class DemoKeys {
  DemoKeys._();

  static final homeHeader = GlobalKey(debugLabel: 'homeHeader');
  static final reportButton = GlobalKey(debugLabel: 'reportButton');
  static final navBar = GlobalKey(debugLabel: 'navBar');
  static final photoBox = GlobalKey(debugLabel: 'photoBox');
  static final sampleSheet = GlobalKey(debugLabel: 'sampleSheet');
  static final categoryField = GlobalKey(debugLabel: 'categoryField');
  static final locationButton = GlobalKey(debugLabel: 'locationButton');
  static final mapConfirm = GlobalKey(debugLabel: 'mapConfirm');
  static final submitButton = GlobalKey(debugLabel: 'submitButton');
  static final demoReportCard = GlobalKey(debugLabel: 'demoReportCard');
  static final demoNotifCard = GlobalKey(debugLabel: 'demoNotifCard');
  static final detailsStatus = GlobalKey(debugLabel: 'detailsStatus');
  static final askButton = GlobalKey(debugLabel: 'askButton');
  static final chatComposer = GlobalKey(debugLabel: 'chatComposer');
  static final rateSection = GlobalKey(debugLabel: 'rateSection');
  static final rateDone = GlobalKey(debugLabel: 'rateDone');
}

/// Links between the tutorial and the app's screens. Screens register
/// callbacks while they are open so "Next" can do the step for the tester.
class DemoNav {
  DemoNav._();

  /// Selected bottom tab on Home (0 Home, 1 My Reports, 2 Alerts, 3 Settings).
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  static void Function(int index)? switchTab;
  static VoidCallback? openReport;
  static VoidCallback? chooseSample;
  static VoidCallback? confirmLocation;
  static VoidCallback? submitReport;
  static VoidCallback? sendChat;
  static VoidCallback? submitRating;

  /// Set by the report form for the current form only.
  static bool sampleChosen = false;
  static bool locationConfirmed = false;

  /// Report form: AI finished and a category is selected.
  static bool categoryReady = false;
  static String? selectedCategory;

  /// [key] is mounted, on the top-most route and (for Home tabs) on
  /// the selected tab.
  static bool isShown(GlobalKey key, {int? onTab}) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (onTab != null && tab.value != onTab) return false;
    return true;
  }

  static bool get homeIsCurrent => isShown(DemoKeys.navBar);

  /// Status changes that follow from what the tester is looking at.
  /// Called often; each change happens only once (see DemoStore).
  static void checkTransitions() {
    if (!homeIsCurrent) return;
    final store = DemoStore.instance;
    if (tab.value == 2 && store.stage == DemoStage.pending) {
      store.markInProgress();
    }
    if (tab.value == 1 &&
        store.stage == DemoStage.progress &&
        store.adminReplied) {
      store.markResolved();
    }
  }

  static void popToHome() {
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  static void openDemoReport() {
    final id = DemoStore.instance.demoReportID;
    final user = AuthSession.user;
    if (id == null || user == null) return;
    NotificationRouter.attach(userID: user.userID, barangayID: user.barangayID);
    NotificationRouter.open(
      NotificationTarget(NotificationTargetType.report, id: id),
    );
  }

  static void openDemoChat() {
    final id = DemoStore.instance.demoReportID;
    final user = AuthSession.user;
    if (id == null || user == null) return;
    appNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BarangayMessagesPage(userID: user.userID, initialReportID: id),
      ),
    );
  }
}

// ============================================================
// CONTROLLER
// ============================================================

class TutorialController extends ChangeNotifier {
  TutorialController._();

  static final TutorialController instance = TutorialController._();

  static const _stepKey = 'demo_tutorial_step';
  static const _doneKey = 'demo_tutorial_done';
  static const _skippedKey = 'demo_tutorial_skipped';

  SharedPreferences? _prefs;

  int step = 1;
  bool active = false;
  bool done = false;
  bool skipped = false;

  /// Final "Thank you" screen with the countdown.
  bool showThanks = false;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      step = (_prefs!.getInt(_stepKey) ?? 1).clamp(1, kTutorialSteps);
      done = _prefs!.getBool(_doneKey) ?? false;
      skipped = _prefs!.getBool(_skippedKey) ?? false;
    } catch (e) {
      debugPrint('[DEMO] Tutorial progress unavailable: $e');
    }
  }

  void _save() {
    try {
      _prefs?.setInt(_stepKey, step);
      _prefs?.setBool(_doneKey, done);
      _prefs?.setBool(_skippedKey, skipped);
    } catch (_) {}
  }

  /// Home opened (after login or a refresh): start or resume once.
  void onHomeShown() {
    if (done || skipped || active) return;
    active = true;
    if (step >= kTutorialSteps) step = kTutorialSteps - 1;
    notifyListeners();
  }

  /// Lowest step allowed by the saved report state, so Back and a
  /// refresh never go "before" something that already happened.
  int get minStep {
    final store = DemoStore.instance;
    switch (store.stage) {
      case DemoStage.rated:
        return 14;
      case DemoStage.resolved:
        return 13;
      case DemoStage.progress:
        return store.adminReplied ? 12 : 9;
      case DemoStage.pending:
        return 7;
      case DemoStage.none:
        return 1;
    }
  }

  void goTo(int value) {
    step = value.clamp(1, kTutorialSteps);
    _save();
    notifyListeners();
  }

  bool get canGoBack => step > 1 && step - 1 >= minStep && step < 15;

  void back() {
    if (!canGoBack) return;
    final target = step - 1;
    // Put the screen back where that step expects it.
    if (target <= 3) {
      DemoNav.popToHome();
      DemoNav.switchTab?.call(0);
    } else if (target == 8 || target == 9 || target == 10) {
      DemoNav.popToHome();
      DemoNav.switchTab?.call(target == 8 ? 1 : 2);
    } else if (target == 11 && DemoNav.isShown(DemoKeys.chatComposer)) {
      appNavigatorKey.currentState?.maybePop();
    }
    goTo(target);
  }

  /// Steps that only explain something (no action required).
  static bool isInfoStep(int s) => s == 1 || s == 2;

  /// True once the tester has really done what the current step asks.
  /// "Next" stays disabled until then, so it cannot be used to skip.
  bool get stepDone => isStepDone(step);

  bool isStepDone(int s) {
    final store = DemoStore.instance;
    final formOpen = DemoKeys.photoBox.currentContext != null;
    final onHome = DemoNav.homeIsCurrent;
    final tab = DemoNav.tab.value;
    switch (s) {
      case 1:
      case 2:
        return true;
      case 3: // tapped "Report an Issue"
        return formOpen;
      case 4: // picked a sample photo
        return formOpen &&
            DemoNav.sampleChosen &&
            !DemoNav.isShown(DemoKeys.sampleSheet);
      case 5: // AI suggestion is ready and a category is selected
        return formOpen && DemoNav.categoryReady;
      case 6: // confirmed the pin on the map
        return formOpen &&
            DemoNav.locationConfirmed &&
            !DemoNav.isShown(DemoKeys.mapConfirm);
      case 7: // submitted the report
        return store.stage != DemoStage.none && !formOpen;
      case 8: // opened My Reports
        return onHome && tab == 1 && store.demoReportID != null;
      case 9: // opened Alerts (report became In progress)
        return onHome &&
            tab == 2 &&
            store.stage.index >= DemoStage.progress.index;
      case 10: // tapped the notification: Report Details is open
        return DemoNav.isShown(DemoKeys.detailsStatus);
      case 11: // tapped "Ask your barangay about this report"
        return DemoNav.isShown(DemoKeys.chatComposer);
      case 12: // sent the message and the barangay replied
        return store.adminReplied;
      case 13: // went back to My Reports: report is Resolved
        return store.stage.index >= DemoStage.resolved.index;
      case 14: // submitted the rating
        return store.stage == DemoStage.rated;
    }
    return false;
  }

  /// "Next": only moves on once the step's action is done.
  void next() {
    if (!stepDone) return;
    if (step >= 14) return finish();
    goTo(step + 1);
  }

  void skip() {
    active = false;
    skipped = true;
    _save();
    notifyListeners();
  }

  /// Help button > Continue.
  void resume() {
    skipped = false;
    active = true;
    _save();
    notifyListeners();
  }

  /// Settings > How to test, or Help button > Restart.
  void restart() {
    done = false;
    skipped = false;
    showThanks = false;
    active = true;
    step = minStep;
    DemoNav.popToHome();
    DemoNav.switchTab?.call(step >= 13 ? 1 : 0);
    _save();
    notifyListeners();
  }

  /// "Finish"/"Done" after rating: show the thank-you screen (step 15).
  void finish() {
    step = kTutorialSteps;
    showThanks = true;
    _save();
    notifyListeners();
  }

  /// Saved BEFORE leaving for the form, so Back from the form restores
  /// Home without restarting the tutorial or redirecting again.
  void markCompleted() {
    done = true;
    active = false;
    showThanks = false;
    _save();
    notifyListeners();
  }

  Future<void> resetAll() async {
    await DemoStore.instance.reset();
    done = false;
    skipped = false;
    showThanks = false;
    step = 1;
    active = true;
    DemoNav.popToHome();
    DemoNav.switchTab?.call(0);
    _save();
    notifyListeners();
  }

  /// Keeps the step consistent with what is on screen (never moves
  /// forward on its own: only "Next" does that).
  void tick() {
    if (!active || showThanks) return;
    final store = DemoStore.instance;

    // Never stay before something that already happened.
    if (step < minStep) return goTo(minStep);

    final formOpen = DemoKeys.photoBox.currentContext != null;
    switch (step) {
      case 4:
      case 5:
      case 6:
      case 7:
        // The report form was closed before submitting: start it again.
        if (!formOpen && store.stage == DemoStage.none) goTo(3);
      case 11:
        if (DemoKeys.detailsStatus.currentContext == null &&
            DemoKeys.chatComposer.currentContext == null &&
            DemoNav.homeIsCurrent) {
          goTo(10);
        }
      case 12:
        if (!store.adminReplied &&
            DemoKeys.chatComposer.currentContext == null) {
          goTo(DemoKeys.detailsStatus.currentContext != null ? 11 : 10);
        }
    }
  }
}

// ============================================================
// STEP CONTENT
// ============================================================

class _StepView {
  const _StepView({
    required this.title,
    required this.text,
    this.target,
    this.onTab,
    this.navSlice,
    this.scroll = false,
    this.nextLabel = 'Next',
    this.doneTitle,
    this.doneText,
  });

  final String title;
  final String text;
  final GlobalKey? target;
  final int? onTab;

  /// Highlight one item of the bottom navigation bar (0-3).
  final int? navSlice;
  final bool scroll;
  final String nextLabel;

  /// Shown (without dimming) once the step's action is done.
  final String? doneTitle;
  final String? doneText;

  bool get hasTarget => target != null || navSlice != null;
}

_StepView _viewFor(int step) {
  final store = DemoStore.instance;
  final id = store.demoReportID ?? 'your report';
  final tab = DemoNav.tab.value;
  final onHome = DemoNav.homeIsCurrent;

  switch (step) {
    case 1:
      return _StepView(
        title: 'Welcome to the CitiSense demo!',
        text:
            'This is a prototype for testing. Notifications, AI photo '
            'detection and barangay replies are simulated, and nothing is '
            'sent to a real barangay. Let’s walk through one report.',
        nextLabel: 'Start',
      );
    case 2:
      return _StepView(
        title: 'Your Home screen',
        text:
            'Here you see a greeting, your barangay, and the main actions. '
            'Announcements from your barangay appear below.',
        target: DemoKeys.homeHeader,
        onTab: 0,
      );
    case 3:
      return _StepView(
        title: 'Report an issue',
        text: 'Tap “Report an Issue” to start a new report.',
        target: DemoKeys.reportButton,
        onTab: 0,
        scroll: true,
        doneTitle: 'Report form opened',
        doneText:
            'This is where you describe the problem. Tap Next to add a photo.',
      );
    case 4:
      final sheet = DemoNav.isShown(DemoKeys.sampleSheet);
      return _StepView(
        title: sheet ? 'Choose a sample photo' : 'Add a photo',
        text: sheet
            ? 'Pick any sample photo. In the real app you would use your camera.'
            : 'Tap the photo box to choose one of the sample photos.',
        target: sheet ? DemoKeys.sampleSheet : DemoKeys.photoBox,
        doneTitle: 'Photo added',
        doneText:
            'The simulated AI is checking the photo. Tap Next to see its suggestion.',
      );
    case 5:
      return _StepView(
        title: 'Check the AI suggestion',
        text: 'Wait a moment while the simulated AI checks your photo…',
        target: DemoKeys.categoryField,
        scroll: true,
        nextLabel: 'Confirm',
        doneTitle: 'AI suggestion ready',
        doneText:
            'The AI suggests “${DemoNav.selectedCategory ?? '-'}”. You can '
            'change it in the list. Tap Confirm when it’s right.',
      );
    case 6:
      final map = DemoNav.isShown(DemoKeys.mapConfirm);
      return _StepView(
        title: map ? 'Confirm the location' : 'Set the location',
        text: map
            ? 'The pin is already in place. Just press Confirm.'
            : 'Tap “Set Location on Map” to see where the issue is pinned.',
        target: map ? DemoKeys.mapConfirm : DemoKeys.locationButton,
        scroll: !map,
        doneTitle: 'Location confirmed',
        doneText: 'The issue is pinned on the map. Tap Next.',
      );
    case 7:
      return _StepView(
        title: 'Submit the report',
        text: 'Everything is filled in. Tap “Submit Report”.',
        target: DemoKeys.submitButton,
        scroll: true,
        doneTitle: 'Report sent!',
        doneText: 'Your report $id was submitted. Tap Next to find it.',
      );
    case 8:
      return _StepView(
        title: 'Open My Reports',
        text:
            'Tap “My Reports” at the bottom to find the report you just sent.',
        navSlice: 1,
        doneTitle: 'Your new report',
        doneText:
            'Here is $id. Its status is Pending: the barangay has not '
            'acted on it yet.',
      );
    case 9:
      return _StepView(
        title: 'Check your alerts',
        text: 'Tap “Alerts” at the bottom to see what happened to your report.',
        navSlice: 2,
        doneTitle: 'Your report was updated',
        doneText:
            'The barangay started working on it: $id changed from Pending '
            'to In progress.',
      );
    case 10:
      final onAlerts = onHome && tab == 2;
      return _StepView(
        title: 'Open the notification',
        text: onAlerts
            ? 'Tap the “$id is now In progress” notification to open the report.'
            : 'Go to “Alerts” and tap the “$id is now In progress” notification.',
        target: onAlerts ? DemoKeys.demoNotifCard : null,
        onTab: 2,
        navSlice: onAlerts ? null : 2,
        scroll: true,
        doneTitle: 'Report Details',
        doneText: 'The status now shows In progress, here and in My Reports.',
      );
    case 11:
      return _StepView(
        title: 'Ask for an update',
        text: 'Tap “Ask your barangay about this report” below.',
        target: DemoKeys.askButton,
        scroll: true,
        doneTitle: 'Chat with your barangay',
        doneText: 'This chat is about $id. Tap Next to send a follow-up.',
      );
    case 12:
      return _StepView(
        title: store.hasAskedFollowUp
            ? 'Waiting for the barangay'
            : 'Send a follow-up',
        text: store.hasAskedFollowUp
            ? 'The barangay is typing a reply (simulated)…'
            : 'We wrote a message for you. Just press the Send button.',
        target: DemoKeys.chatComposer,
        doneTitle: 'The barangay replied',
        doneText: '“Currently working for it.” Tap Next.',
      );
    case 13:
      return _StepView(
        title: 'Go back to My Reports',
        text: onHome
            ? 'Tap “My Reports” at the bottom.'
            : 'Go back (top-left arrow or your browser’s Back button) to '
                  'the main screen, then tap “My Reports”.',
        navSlice: 1,
        doneTitle: 'Your report is resolved',
        doneText: '$id now shows Resolved, and you got a new alert.',
      );
    case 14:
      final rating = DemoNav.isShown(DemoKeys.rateSection);
      final onList = onHome && tab == 1;
      return _StepView(
        title: 'Rate the resolution',
        text: rating
            ? 'We suggested 5 stars and a sample comment. Change them if you '
                  'like, then press “Submit Feedback”.'
            : onList
            ? 'Tap $id to open it and rate how it was handled.'
            : 'Go to “My Reports” and open $id.',
        target: rating
            ? DemoKeys.rateSection
            : onList
            ? DemoKeys.demoReportCard
            : null,
        onTab: rating ? null : 1,
        navSlice: rating || onList ? null : 1,
        scroll: true,
        nextLabel: 'Finish',
        doneTitle: 'Thanks for your feedback!',
        doneText: 'Tap Finish to complete the tutorial.',
      );
  }
  return const _StepView(title: '', text: '');
}

// ============================================================
// LAYER (dim + hole + tooltip + banner + help + thank-you)
// ============================================================

class DemoLayer extends StatefulWidget {
  const DemoLayer({super.key, required this.child});

  final Widget child;

  @override
  State<DemoLayer> createState() => _DemoLayerState();
}

class _DemoLayerState extends State<DemoLayer>
    with SingleTickerProviderStateMixin {
  final GlobalKey _layerKey = GlobalKey();
  final TutorialController _tutorial = TutorialController.instance;

  late final Ticker _ticker;
  Timer? _slowTimer;

  Rect? _hole;
  bool _homeShown = false;

  // Overlay is shown only after the screen has settled (see _update).
  bool _ready = false;
  String _phase = '';
  DateTime _phaseStart = DateTime(2000);
  int _stableFrames = 0;
  Rect? _lastRect;
  String _scrolledFor = '';
  DateTime _lastScroll = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _update());
    _tutorial.addListener(_onTutorialChanged);
    DemoStore.instance.addListener(_onTutorialChanged);
    // Checks status changes and keeps the help button in sync.
    _slowTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      DemoNav.checkTransitions();
      final shown = DemoNav.homeIsCurrent;
      if (shown != _homeShown) setState(() => _homeShown = shown);
      if (_tutorial.active && !_ticker.isActive) _ticker.start();
    });
    _onTutorialChanged();
  }

  @override
  void dispose() {
    _tutorial.removeListener(_onTutorialChanged);
    DemoStore.instance.removeListener(_onTutorialChanged);
    _slowTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onTutorialChanged() {
    if (!mounted) return;
    if (_tutorial.active && !_ticker.isActive) _ticker.start();
    if (!_tutorial.active && _ticker.isActive) _ticker.stop();
    setState(() {});
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final layer = _layerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || layer is! RenderBox) return null;
    if (!box.attached || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: layer);
    return topLeft & box.size;
  }

  void _update() {
    _tutorial.tick();
    if (!_tutorial.active || _tutorial.showThanks) return;

    final step = _tutorial.step;
    final done = _tutorial.stepDone;
    final info = TutorialController.isInfoStep(step);
    final view = _viewFor(step);
    final now = DateTime.now();

    // Dim + spotlight only while the action is still to be done (or on
    // the explanation steps). Once done, the screen stays normal.
    final spotlight = info || !done;

    Rect? rect;
    final target = view.target;
    if (spotlight &&
        target != null &&
        DemoNav.isShown(target, onTab: view.onTab)) {
      rect = _rectOf(target);
      // Bring the target into view (again if the layout moves it away,
      // e.g. an image above it finished loading).
      final id = '$step:${target.hashCode}';
      final offScreen = rect != null && !_fitsOnScreen(rect);
      final due = now.difference(_lastScroll).inMilliseconds > 700;
      if (view.scroll &&
          rect != null &&
          (_scrolledFor != id || (offScreen && due))) {
        _scrolledFor = id;
        _lastScroll = now;
        Scrollable.ensureVisible(
          target.currentContext!,
          alignment: 0.35,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    } else if (spotlight && view.navSlice != null && DemoNav.homeIsCurrent) {
      final bar = _rectOf(DemoKeys.navBar);
      if (bar != null) {
        final w = bar.width / 4;
        rect = Rect.fromLTWH(
          bar.left + w * view.navSlice!,
          bar.top,
          w,
          bar.height,
        );
      }
    }
    if (rect != null) {
      rect = rect.inflate(6);
      // Only a target that is fully on screen can be highlighted.
      if (!_fitsOnScreen(rect)) rect = null;
    }

    // A new step, a finished action or a target that (re)appears starts
    // a new "phase": the overlay is hidden until the screen has settled.
    final phase =
        '$step|$spotlight|${target?.hashCode}|${view.navSlice}|${rect != null}';
    if (phase != _phase) {
      _phase = phase;
      _phaseStart = now;
      _stableFrames = 0;
      _lastRect = null;
      if (_ready || _hole != null) {
        setState(() {
          _ready = false;
          _hole = null;
        });
      }
    }

    if (!_ready) {
      final same =
          rect != null &&
          _lastRect != null &&
          (rect.topLeft - _lastRect!.topLeft).distance < 0.5 &&
          (rect.size - _lastRect!.size as Offset).distance < 0.5;
      _stableFrames = same ? _stableFrames + 1 : 0;
      _lastRect = rect;
      final waited = now.difference(_phaseStart).inMilliseconds;
      // Navigation/scroll finished: target has stopped moving.
      final settled = rect != null && _stableFrames >= 8 && waited >= 350;
      // Nothing to highlight (explanation, done, or target not on this
      // screen): show the card once the transition is over.
      final noTarget =
          rect == null && (!spotlight || !view.hasTarget || waited >= 900);
      if (settled || (noTarget && waited >= 350)) {
        setState(() {
          _ready = true;
          _hole = rect;
        });
      }
      return;
    }

    // Visible: follow the target if it moves (e.g. screen size change).
    if (rect != _hole) setState(() => _hole = rect);
  }

  bool _fitsOnScreen(Rect rect) {
    final layer = _layerKey.currentContext?.findRenderObject();
    if (layer is! RenderBox || !layer.hasSize) return false;
    return rect.top >= -8 &&
        rect.bottom <= layer.size.height + 8 &&
        rect.left >= -8 &&
        rect.right <= layer.size.width + 8;
  }

  @override
  Widget build(BuildContext context) {
    final showTutorial = _tutorial.active && !_tutorial.showThanks && _ready;
    final view = showTutorial ? _viewFor(_tutorial.step) : null;

    return Stack(
      key: _layerKey,
      children: [
        widget.child,
        if (view != null) ..._buildTutorial(context, view),
        if (!_tutorial.active && _homeShown && !_tutorial.showThanks)
          _buildHelpButton(context),
        const Positioned(top: 2, right: 2, child: _DemoLabel()),
        _buildBanner(),
        if (_tutorial.showThanks)
          Positioned.fill(
            child: _ThankYouScreen(onStay: _tutorial.markCompleted),
          ),
      ],
    );
  }

  List<Widget> _buildTutorial(BuildContext context, _StepView view) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final hole = _hole;
    final step = _tutorial.step;
    final done = _tutorial.stepDone;
    final info = TutorialController.isInfoStep(step);

    _TooltipCard card({required bool finished}) => _TooltipCard(
      title: finished ? (view.doneTitle ?? view.title) : view.title,
      text: finished ? (view.doneText ?? view.text) : view.text,
      tutorial: _tutorial,
      nextLabel: view.nextLabel,
      canNext: done,
      done: finished,
    );

    // Floating card that blocks nothing: action done (screen stays
    // normal), or the target is not on this screen yet.
    Widget floating(Widget child) {
      final bar = DemoNav.homeIsCurrent ? _rectOf(DemoKeys.navBar) : null;
      final bottom = bar != null
          ? size.height - bar.top + 10
          : media.padding.bottom + 12;
      return Positioned(left: 12, right: 12, bottom: bottom, child: child);
    }

    if (!info && done) return [floating(card(finished: true))];
    if (view.hasTarget && hole == null) {
      return [floating(card(finished: false))];
    }

    // Explanation without a target (welcome): dim + centred card.
    if (hole == null) {
      return [
        Positioned.fill(child: _SpotlightBarrier(hole: null)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: card(finished: false),
          ),
        ),
      ];
    }

    // Tooltip on the side of the target with more room, never over it.
    final topLimit = media.padding.top + 8;
    final bottomLimit = size.height - media.padding.bottom - 8;
    final spaceAbove = hole.top - 12 - topLimit;
    final spaceBelow = bottomLimit - hole.bottom - 12;
    final below = spaceBelow >= 220 || spaceBelow >= spaceAbove;
    final space = (below ? spaceBelow : spaceAbove).clamp(140.0, size.height);
    final tooltip = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: space),
      child: card(finished: false),
    );

    return [
      Positioned.fill(child: _SpotlightBarrier(hole: hole)),
      // White halo + accent ring drawn OUTSIDE the target, so the
      // target itself is never covered or dimmed.
      Positioned.fromRect(
        rect: hole.inflate(4),
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 4),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      Positioned.fromRect(
        rect: hole.inflate(1),
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent, width: 3),
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
      if (below)
        Positioned(left: 12, right: 12, top: hole.bottom + 12, child: tooltip)
      else
        Positioned(
          left: 12,
          right: 12,
          bottom: size.height - hole.top + 12,
          child: tooltip,
        ),
    ];
  }

  Widget _buildHelpButton(BuildContext context) {
    final bar = _rectOf(DemoKeys.navBar);
    final layer = _layerKey.currentContext?.findRenderObject();
    final height = layer is RenderBox && layer.hasSize
        ? layer.size.height
        : MediaQuery.of(context).size.height;
    final bottom = bar == null ? 90.0 : height - bar.top + 12;
    return Positioned(
      right: 12,
      bottom: bottom,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showDemoHelpMenu(context),
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.help_outline_rounded, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return ValueListenableBuilder<String?>(
      valueListenable: DemoStore.instance.banner,
      builder: (context, message, _) {
        if (message == null) return const SizedBox.shrink();
        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 12,
          right: 12,
          child: Material(
            elevation: 6,
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => DemoStore.instance.banner.value = null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: appFontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Help menu (floating "?" button on the main screens).
Future<void> showDemoHelpMenu(BuildContext context) {
  final tutorial = TutorialController.instance;
  final navigatorContext = appNavigatorKey.currentContext ?? context;
  return showModalBottomSheet<void>(
    context: navigatorContext,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!tutorial.done && tutorial.step > 1)
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(
                'Continue tutorial (step ${tutorial.step} of $kTutorialSteps)',
              ),
              onTap: () {
                Navigator.pop(sheet);
                tutorial.resume();
              },
            ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('How to test (restart tutorial)'),
            onTap: () {
              Navigator.pop(sheet);
              tutorial.restart();
            },
          ),
          ListTile(
            leading: const Icon(Icons.rate_review_outlined),
            title: const Text('Give feedback'),
            onTap: () {
              Navigator.pop(sheet);
              openUrlSameTab(kFeedbackFormUrl);
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: const Text('Reset demo'),
            onTap: () {
              Navigator.pop(sheet);
              confirmDemoReset(navigatorContext);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmDemoReset(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Reset demo?'),
      content: const Text(
        'This restores the starting data and restarts the tutorial.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (ok == true) await TutorialController.instance.resetAll();
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.title,
    required this.text,
    required this.tutorial,
    required this.nextLabel,
    required this.canNext,
    this.done = false,
  });

  final String title;
  final String text;
  final TutorialController tutorial;
  final String nextLabel;
  final bool canNext;

  /// The step's action was completed (shows a check mark).
  final bool done;

  @override
  Widget build(BuildContext context) {
    final step = tutorial.step;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: Colors.white,
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Step $step of $kTutorialSteps',
                    style: const TextStyle(
                      fontFamily: appHeadingFontFamily,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: step / kTutorialSteps,
                        minHeight: 5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (done) ...[
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: appHeadingFontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!canNext) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Do the highlighted action to continue.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: tutorial.skip,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Text(
                      'Skip tutorial',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (step > 1)
                        TextButton(
                          onPressed: tutorial.canGoBack ? tutorial.back : null,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                          ),
                          child: const Text('Back'),
                        ),
                      const SizedBox(width: 4),
                      // Disabled until the step's action is really done.
                      FilledButton(
                        onPressed: canNext ? tutorial.next : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 44),
                        ),
                        child: Text(nextLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoLabel extends StatelessWidget {
  const _DemoLabel();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Demo version',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
              fontFamily: appHeadingFontFamily,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Dims everything except [hole]. Taps inside the hole pass
// through to the real widget; taps elsewhere are absorbed.
// ------------------------------------------------------------

class _SpotlightBarrier extends LeafRenderObjectWidget {
  const _SpotlightBarrier({required this.hole});

  final Rect? hole;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSpotlight(hole);

  @override
  void updateRenderObject(BuildContext context, _RenderSpotlight renderObject) {
    renderObject.hole = hole;
  }
}

class _RenderSpotlight extends RenderBox {
  _RenderSpotlight(this._hole);

  Rect? _hole;

  set hole(Rect? value) {
    if (value == _hole) return;
    _hole = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_hole != null && _hole!.contains(position)) return false;
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    // Even-odd fill: the outer rectangle is dimmed and the inner rounded
    // rectangle (the target) is left completely untouched. (Path.combine
    // is not reliable in the web renderer.)
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(offset & size);
    if (_hole != null) {
      path.addRRect(
        RRect.fromRectAndRadius(
          _hole!.shift(offset),
          const Radius.circular(14),
        ),
      );
    }
    context.canvas.drawPath(path, paint);
  }

}

// ============================================================
// STEP 15: THANK YOU + automatic redirect to the feedback form
// ============================================================

class _ThankYouScreen extends StatefulWidget {
  const _ThankYouScreen({required this.onStay});

  final VoidCallback onStay;

  @override
  State<_ThankYouScreen> createState() => _ThankYouScreenState();
}

class _ThankYouScreenState extends State<_ThankYouScreen> {
  int _seconds = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_seconds <= 1) {
        timer.cancel();
        _go();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go() {
    _timer?.cancel();
    // Completed first, so coming Back from the form shows Home normally.
    TutorialController.instance.markCompleted();
    DemoNav.popToHome();
    DemoNav.switchTab?.call(0);
    openUrlSameTab(kFeedbackFormUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.celebration_rounded,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Thank you for testing!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFamily: appHeadingFontFamily,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Taking you to the feedback form in $_seconds…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _go,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(220, 50),
                  ),
                  child: const Text(
                    'Open feedback form now',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    _timer?.cancel();
                    widget.onStay();
                    DemoNav.popToHome();
                    DemoNav.switchTab?.call(0);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(160, 48),
                  ),
                  child: const Text('Stay in the app'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Phone-width frame for wide screens (desktop browsers)
// ============================================================

class DemoPhoneFrame extends StatelessWidget {
  const DemoPhoneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 600) return child;
        final media = MediaQuery.of(context);
        const width = 430.0;
        return ColoredBox(
          color: const Color(0xFFE9ECF2),
          child: Center(
            child: Container(
              width: width,
              height: constraints.maxHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: MediaQuery(
                data: media.copyWith(size: Size(width, constraints.maxHeight)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
