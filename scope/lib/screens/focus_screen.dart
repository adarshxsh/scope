import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/screens/focus_complete_screen.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/motion/slide_fade_switcher.dart';
import 'package:scope/widgets/progress_widget.dart';
import 'package:scope/widgets/review_card.dart';

/// Focus review session — guided, one notification at a time, no scrolling.
class FocusScreen extends StatefulWidget {
  final NotificationController controller;
  final VoidCallback onBackHome;

  const FocusScreen({
    super.key,
    required this.controller,
    required this.onBackHome,
  });

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  bool _isTransitioning = false;
  SmartActionType? _selectedAction;

  AppNotification? get _current => widget.controller.currentFocusNotification;

  void _startSession() {
    widget.controller.startFocusSession();
    setState(() {
      _selectedAction = null;
    });
  }

  Future<void> _handleAction(SmartAction action) async {
    final notification = _current;
    if (notification == null || _isTransitioning) return;

    setState(() => _selectedAction = action.type);
    await Future<void>.delayed(AppMotion.fast);

    switch (action.type) {
      case SmartActionType.archive:
        widget.controller.archive(notification.id);
        break;
      case SmartActionType.complete:
        widget.controller.complete(notification.id);
        break;
      case SmartActionType.addCalendar:
        widget.controller.recordCalendarEvent();
        widget.controller.recordAction();
        break;
      case SmartActionType.remind:
        widget.controller.recordReminder();
        widget.controller.recordAction();
        break;
      case SmartActionType.openUrl:
      case SmartActionType.openApp:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notification: notification,
              controller: widget.controller,
            ),
          ),
        );
        setState(() => _selectedAction = null);
        return;
      default:
        widget.controller.recordAction();
    }

    await _advance();
  }

  Future<void> _advance() async {
    if (_current == null) {
      _finishSession();
      return;
    }

    setState(() => _isTransitioning = true);
    widget.controller.recordReviewed();

    await Future<void>.delayed(AppMotion.standard);
    if (!mounted) return;

    final progress = widget.controller.focusSessionProgressCount;
    final total = widget.controller.focusSessionQueueIds.length;

    if (_current == null || progress >= total) {
      _finishSession();
      return;
    }

    setState(() {
      _selectedAction = null;
      _isTransitioning = false;
    });
  }

  void _handleSkip() {
    final notification = _current;
    if (notification == null || _isTransitioning) return;

    setState(() => _isTransitioning = true);
    Future<void>.delayed(AppMotion.standard, () {
      if (!mounted) return;
      widget.controller.skipFocusSessionItem(notification.id);
      setState(() {
        _isTransitioning = false;
        _selectedAction = null;
      });
    });
  }

  void _finishSession() {
    final stats = widget.controller.sessionStats;
    widget.controller.finishFocusSession();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FocusCompleteScreen(
          stats: stats,
          onBackHome: () {
            Navigator.pop(context);
            widget.onBackHome();
          },
          onReviewAgain: () {
            Navigator.pop(context);
            _startSession();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = widget.controller.focusAreaFilter;
    final filterType = widget.controller.filterType;
    final inSession = widget.controller.inFocusSession;

    String filterLabel = 'Filtering';
    if (filter != null) {
      filterLabel = 'Filtering · ${filter.label}';
    } else if (filterType == FocusFilterType.needsAction) {
      filterLabel = 'Filtering · Needs Action';
    } else if (filterType == FocusFilterType.important) {
      filterLabel = 'Filtering · Important';
    } else if (filterType == FocusFilterType.archived) {
      filterLabel = 'Filtering · Archived';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Focus', style: theme.textTheme.headlineLarge),
            if (filter != null || filterType != FocusFilterType.none) ...[
              const SizedBox(height: 4),
              Text(filterLabel, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            if (inSession && widget.controller.focusSessionQueueIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ProgressWidget(
                  completed: widget.controller.focusSessionProgressCount,
                  total: widget.controller.focusSessionQueueIds.length,
                  label: 'Session progress',
                ),
              ),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final inSession = widget.controller.inFocusSession;
    final queue = widget.controller.reviewQueue;

    if (queue.isEmpty && !inSession) {
      return const EmptyState.caughtUp();
    }

    if (!inSession) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${queue.length} notification${queue.length == 1 ? '' : 's'} ready',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Begin a guided review session.\nOne item at a time, no scrolling.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '~${widget.controller.estimatedReviewMinutes} min estimated',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _startSession,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Begin Review Session'),
              ),
            ),
          ],
        ),
      );
    }

    final notification = _current;
    if (notification == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishSession());
      return const EmptyState.caughtUp();
    }

    final actions = SmartActions.forNotification(notification);
    final primary = SmartActions.primaryFor(actions);
    final progress = widget.controller.focusSessionProgressCount;
    final total = widget.controller.focusSessionQueueIds.length;

    return Column(
      children: [
        Expanded(
          child: AnimatedOpacity(
            opacity: _isTransitioning ? 0.0 : 1.0,
            duration: AppMotion.standard,
            curve: AppMotion.exit,
            child: AnimatedScale(
              scale: _isTransitioning ? 0.96 : 1.0,
              duration: AppMotion.standard,
              curve: AppMotion.exit,
              child: SlideFadeSwitcher(
                transitionKey: notification.id,
                child: ReviewCard(
                  notification: notification,
                  actions: actions,
                  selectedAction: _selectedAction,
                  currentIndex: progress,
                  totalCount: total,
                  onAction: _handleAction,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (primary != null)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isTransitioning ? null : () => _handleAction(primary),
              icon: Icon(primary.icon, size: 20),
              label: Text(primary.label),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _isTransitioning ? null : _handleSkip,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Next'),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
