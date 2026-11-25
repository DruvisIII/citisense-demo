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
      case DemoStage.resolved:
      case DemoStage.rated:
        return 14;
      case DemoStage.progress:
        return store.adminReplied ? 13 : 9;
      case DemoStage.pending:
        return 8;
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
    } else if (target == 8 || target == 9) {
      DemoNav.popToHome();
      DemoNav.switchTab?.call(target == 8 ? 1 : 2);
    } else if (target == 11 && DemoNav.isShown(DemoKeys.chatComposer)) {
      appNavigatorKey.currentState?.maybePop();
    }
    goTo(target);
  }

  /// "Next": does the step for the tester when they have not done it.
  void next() {
    final store = DemoStore.instance;
    final tab = DemoNav.tab.value;
    switch (step) {
      case 1:
      case 2:
        DemoNav.popToHome();
        DemoNav.switchTab?.call(0);
        goTo(step + 1);
      case 3:
        if (DemoNav.homeIsCurrent) {
          DemoNav.switchTab?.call(0);
          DemoNav.openReport?.call();
        } else {
          goTo(4);
        }
      case 4:
        if (DemoNav.isShown(DemoKeys.sampleSheet)) {
          appNavigatorKey.currentState?.maybePop();
        }
        if (!DemoNav.sampleChosen) DemoNav.chooseSample?.call();
        goTo(5);
      case 5:
        goTo(6);
      case 6:
        if (DemoNav.isShown(DemoKeys.mapConfirm)) {
          appNavigatorKey.currentState?.maybePop();
        }
        if (!DemoNav.locationConfirmed) DemoNav.confirmLocation?.call();
        goTo(7);
      case 7:
        if (store.stage == DemoStage.none) {
          DemoNav.submitReport?.call();
        } else {
          goTo(8);
        }
      case 8:
        if (tab != 1 || !DemoNav.homeIsCurrent) {
          DemoNav.popToHome();
          DemoNav.switchTab?.call(1);
        } else {
          goTo(9);
        }
      case 9:
        if (tab != 2 || !DemoNav.homeIsCurrent) {
          DemoNav.popToHome();
          DemoNav.switchTab?.call(2);
        } else {
          DemoNav.openDemoReport();
        }
      case 10:
        goTo(11);
      case 11:
        DemoNav.openDemoChat();
      case 12:
        if (!store.hasAskedFollowUp) {
          DemoNav.sendChat?.call();
        } else if (store.adminReplied) {
          goTo(13);
        }
      case 13:
        DemoNav.popToHome();
        DemoNav.switchTab?.call(1);
      case 14:
        if (store.stage == DemoStage.rated) {
          finish();
        } else if (!DemoNav.isShown(DemoKeys.rateSection)) {
          DemoNav.popToHome();
          DemoNav.openDemoReport();
        } else {
          DemoNav.submitRating?.call();
        }
    }
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
    DemoNav.switchTab?.call(step >= 14 ? 1 : 0);
    _save();
    notifyListeners();
  }

  /// "Done" after rating: show the thank-you screen (step 15).
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

  /// Automatic progress, checked many times per second while active.
  void tick() {
    if (!active || showThanks) return;
    final store = DemoStore.instance;

    // Never stay before something that already happened.
    if (step < minStep) return goTo(minStep);

    final formOpen = DemoKeys.photoBox.currentContext != null;
    switch (step) {
      case 3:
        if (formOpen) goTo(4);
      case 4:
        if (!formOpen) return goTo(3);
        if (DemoNav.sampleChosen && !DemoNav.isShown(DemoKeys.sampleSheet)) {
          goTo(5);
        }
      case 5:
        if (!formOpen) goTo(3);
      case 6:
        if (!formOpen) return goTo(3);
        if (DemoNav.locationConfirmed &&
            !DemoNav.isShown(DemoKeys.mapConfirm)) {
          goTo(7);
        }
      case 7:
        if (!formOpen) goTo(store.stage == DemoStage.none ? 3 : 8);
      case 8:
        if (DemoNav.homeIsCurrent && DemoNav.tab.value == 2) goTo(9);
      case 9:
        if (store.stage.index >= DemoStage.progress.index &&
            DemoNav.isShown(DemoKeys.detailsStatus)) {
          goTo(10);
        }
      case 10:
      case 11:
        if (DemoNav.isShown(DemoKeys.chatComposer)) {
          goTo(12);
        } else if (DemoKeys.detailsStatus.currentContext == null &&
            DemoNav.homeIsCurrent) {
          goTo(9);
        }
      case 12:
        if (store.adminReplied) {
          goTo(13);
        } else if (DemoKeys.chatComposer.currentContext == null &&
            DemoNav.homeIsCurrent) {
          goTo(9);
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
  });

  final String title;
  final String text;
  final GlobalKey? target;
  final int? onTab;

  /// Highlight one item of the bottom navigation bar (0-3).
  final int? navSlice;
  final bool scroll;
  final String nextLabel;

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
      );
    case 4:
      if (DemoNav.isShown(DemoKeys.sampleSheet)) {
        return _StepView(
          title: 'Choose a sample photo',
          text:
              'Pick any sample photo. In the real app you would use your camera.',
          target: DemoKeys.sampleSheet,
        );
      }
      return _StepView(
        title: 'Add a photo',
        text: 'Tap the photo box to choose one of the sample photos.',
        target: DemoKeys.photoBox,
      );
    case 5:
      return _StepView(
        title: 'Check the AI suggestion',
        text:
            'The simulated AI suggests a category from the photo. You can '
            'change it if it looks wrong. Press Confirm when it’s right.',
        target: DemoKeys.categoryField,
        scroll: true,
        nextLabel: 'Confirm',
      );
    case 6:
      if (DemoNav.isShown(DemoKeys.mapConfirm)) {
        return _StepView(
          title: 'Confirm the location',
          text: 'The pin is already in place. Just press Confirm.',
          target: DemoKeys.mapConfirm,
        );
      }
      return _StepView(
        title: 'Set the location',
        text: 'Tap “Set Location on Map” to see where the issue is pinned.',
        target: DemoKeys.locationButton,
        scroll: true,
      );
    case 7:
      return _StepView(
        title: 'Submit the report',
        text: 'Everything is filled in. Tap “Submit Report”.',
        target: DemoKeys.submitButton,
        scroll: true,
      );
    case 8:
      if (onHome && tab == 1) {
        return _StepView(
          title: 'Your new report',
          text:
              'Here is $id. Its status is Pending: the barangay has not acted on it yet.',
          target: DemoKeys.demoReportCard,
          onTab: 1,
          scroll: true,
        );
      }
      return _StepView(
        title: 'Open My Reports',
        text: 'Tap “My Reports” to find the report you just sent.',
        navSlice: 1,
      );
    case 9:
      if (onHome && tab == 2) {
        return _StepView(
          title: 'Your report was updated',
          text:
              'The barangay started working on it: $id changed from Pending '
              'to In progress. Tap the notification to open it.',
          target: DemoKeys.demoNotifCard,
          onTab: 2,
          scroll: true,
          nextLabel: 'Open it',
        );
      }
      return _StepView(
        title: 'Check your alerts',
        text: 'Tap “Notifications” to see what happened to your report.',
        navSlice: 2,
      );
    case 10:
      return _StepView(
        title: 'Report Details',
        text: 'The status now shows In progress, here and in My Reports.',
        target: DemoKeys.detailsStatus,
      );
    case 11:
      return _StepView(
        title: 'Ask for an update',
        text: 'Scroll down and tap “Ask your barangay about this report”.',
        target: DemoKeys.askButton,
        scroll: true,
      );
    case 12:
      if (store.hasAskedFollowUp) {
        return _StepView(
          title: 'Waiting for the barangay',
          text: 'The barangay is typing a reply (simulated)…',
          target: DemoKeys.chatComposer,
        );
      }
      return _StepView(
        title: 'Send a follow-up',
        text: 'We wrote a message for you. Just press Send.',
        target: DemoKeys.chatComposer,
        nextLabel: 'Send',
      );
    case 13:
      return _StepView(
        title: 'Go back to My Reports',
        text:
            'The barangay replied. Now go back (top-left arrow or your '
            'browser’s Back button) and open “My Reports”.',
        navSlice: 1,
        nextLabel: 'Take me there',
      );
    case 14:
      if (store.stage == DemoStage.rated) {
        return _StepView(
          title: 'Thanks for your feedback!',
          text: 'Press Done to finish the tutorial.',
          target: DemoKeys.rateDone,
          scroll: true,
          nextLabel: 'Done',
        );
      }
      if (DemoNav.isShown(DemoKeys.rateSection)) {
        return _StepView(
          title: 'Rate the resolution',
          text:
              'We suggested 5 stars and a sample comment. Change them if you '
              'like, then press “Submit Feedback”.',
          target: DemoKeys.rateSection,
          scroll: true,
          nextLabel: 'Submit',
        );
      }
      return _StepView(
        title: 'Your report is resolved',
        text: '$id now shows Resolved. Tap it to rate how it was handled.',
        target: onHome && tab == 1 ? DemoKeys.demoReportCard : null,
        onTab: 1,
        navSlice: onHome && tab == 1 ? null : 1,
        scroll: true,
        nextLabel: 'Open it',
      );
  }
  return _StepView(title: '', text: '');
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
  String _scrolledFor = '';

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
    if (!_tutorial.active) return;

    final view = _viewFor(_tutorial.step);
    Rect? rect;
    final target = view.target;
    if (target != null && DemoNav.isShown(target, onTab: view.onTab)) {
      rect = _rectOf(target);
      // Bring the highlighted widget into view once per step.
      final id = '${_tutorial.step}:${target.hashCode}';
      if (view.scroll && _scrolledFor != id && rect != null) {
        _scrolledFor = id;
        final ctx = target.currentContext!;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    } else if (view.navSlice != null && DemoNav.homeIsCurrent) {
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
    if (rect != null) rect = rect.inflate(6);
    if (rect != _hole) setState(() => _hole = rect);
  }

  @override
  Widget build(BuildContext context) {
    final showTutorial = _tutorial.active && !_tutorial.showThanks;
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
    final size = MediaQuery.of(context).size;
    final hole = _hole;

    // Expected highlight not on screen (e.g. a dropdown is open): show a
    // small floating card that blocks nothing else.
    if (view.hasTarget && hole == null) {
      return [
        Positioned(
          left: 12,
          right: 12,
          bottom: 84,
          child: _TooltipCard(view: view, tutorial: _tutorial, hole: null),
        ),
      ];
    }

    final card = _TooltipCard(
      view: view,
      tutorial: _tutorial,
      hole: hole,
      layerHeight: size.height,
    );

    Widget positioned;
    if (hole == null) {
      positioned = Center(
        child: Padding(padding: const EdgeInsets.all(16), child: card),
      );
    } else if (hole.center.dy < size.height / 2) {
      positioned = Positioned(
        left: 12,
        right: 12,
        top: (hole.bottom + 10).clamp(0, size.height - 220),
        child: card,
      );
    } else {
      positioned = Positioned(
        left: 12,
        right: 12,
        bottom: (size.height - hole.top + 10).clamp(0, size.height - 220),
        child: card,
      );
    }

    return [
      Positioned.fill(child: _SpotlightBarrier(hole: hole)),
      if (hole != null)
        Positioned.fromRect(
          rect: hole,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      positioned,
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
    required this.view,
    required this.tutorial,
    required this.hole,
    this.layerHeight = 0,
  });

  final _StepView view;
  final TutorialController tutorial;
  final Rect? hole;
  final double layerHeight;

  @override
  Widget build(BuildContext context) {
    final step = tutorial.step;
    final needsScroll =
        view.scroll &&
        hole != null &&
        (hole!.bottom > layerHeight - 60 || hole!.top < 0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: Colors.white,
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
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
              Text(
                view.title,
                style: const TextStyle(
                  fontFamily: appHeadingFontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                view.text,
                style: const TextStyle(
                  fontFamily: appFontFamily,
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              if (needsScroll) ...[
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.keyboard_double_arrow_down_rounded, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Scroll down',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                      FilledButton(
                        onPressed: tutorial.next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 44),
                        ),
                        child: Text(view.nextLabel),
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
    final canvas = context.canvas;
    final outer = Path()..addRect(offset & size);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    if (_hole == null) {
      canvas.drawPath(outer, paint);
      return;
    }
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          _hole!.shift(offset),
          const Radius.circular(14),
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      paint,
    );
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
