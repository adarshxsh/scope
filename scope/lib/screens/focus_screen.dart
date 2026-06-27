import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/screens/focus_complete_screen.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/theme/scope_navigator.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/physics_card.dart';
import 'package:scope/widgets/primitives/scope_loading.dart';
import 'package:scope/widgets/primitives/scope_progress.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/review_card.dart';
import 'package:scope/widgets/saved_action_items_widget.dart';
import 'package:scope/widgets/scope_screen_body.dart';

/// Focus review session — one notification at a time.
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
  int _currentIndex = 0;
  bool _isTransitioning = false;
  SmartActionType? _selectedAction;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _startSession() {
    widget.controller.startFocusSession();
    setState(() => _selectedAction = null);
  }

  Future<void> _handleAction(SmartAction action, AppNotification notification) async {
    if (_isTransitioning) return;

    setState(() => _selectedAction = action.type);
    await Future<void>.delayed(AppMotion.fast);

    switch (action.type) {
      case SmartActionType.archive:
        widget.controller.archive(notification.id);
      case SmartActionType.complete:
        widget.controller.complete(notification.id);
      case SmartActionType.addCalendar:
      case SmartActionType.remind:
      case SmartActionType.track:
        widget.controller.saveActionItem(notification, action);
        widget.controller.recordAction();
        setState(() => _isTransitioning = false);
        if (widget.controller.reviewQueue.isEmpty) _finishSession();
        return;
      case SmartActionType.pay:
      case SmartActionType.download:
      case SmartActionType.viewStatement:
      case SmartActionType.reply:
      case SmartActionType.join:
      case SmartActionType.openUrl:
      case SmartActionType.openApp:
        if (!mounted) return;
        await ScopeNavigator.push(
          context,
          NotificationDetailScreen(
            notification: notification,
            controller: widget.controller,
          ),
        );
        setState(() => _selectedAction = null);
        return;
    }

    await _advance();
  }

  Future<void> _advance() async {
    setState(() => _isTransitioning = true);
    widget.controller.recordReviewed();

    await Future<void>.delayed(AppMotion.standard);
    if (!mounted) return;

    final progress = widget.controller.focusSessionProgressCount;
    final total = widget.controller.focusSessionQueueIds.length;

    if (progress >= total || widget.controller.reviewQueue.isEmpty) {
      _finishSession();
      return;
    }

    setState(() {
      _selectedAction = null;
      _currentIndex++;
      _isTransitioning = false;
    });
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _selectedAction = null;
      });
    }
  }

  void _handleDismissAction(AppNotification notification, SmartActionType type) {
    widget.controller.recordReviewed();
    if (type == SmartActionType.complete) {
      widget.controller.complete(notification.id);
    } else {
      widget.controller.archive(notification.id);
    }
    if (widget.controller.reviewQueue.isEmpty) _finishSession();
  }

  void _finishSession() {
    final stats = widget.controller.sessionStats;
    widget.controller.finishFocusSession();
    setState(() {
      _isTransitioning = false;
      _selectedAction = null;
    });
    ScopeNavigator.push(
      context,
      FocusCompleteScreen(
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
    );
  }

  String _filterLabel() {
    final filter = widget.controller.focusAreaFilter;
    final filterType = widget.controller.filterType;
    if (filter != null) return filter.label;
    return switch (filterType) {
      FocusFilterType.needsAction => 'Needs Action',
      FocusFilterType.important => 'Important',
      FocusFilterType.archived => 'Archived',
      _ => '',
    };
  }

  Widget _buildImmersiveSession() {
    final queue = widget.controller.reviewQueue;
    if (queue.isEmpty) return const SizedBox();

    final total = widget.controller.focusSessionQueueIds.isEmpty
        ? queue.length
        : widget.controller.focusSessionQueueIds.length;

    // Ensure index is within bounds
    if (_currentIndex >= queue.length) {
      _currentIndex = queue.length - 1;
    }

    // Total progress is what we've reviewed + our index in the remaining queue
    final progress = widget.controller.focusSessionProgressCount + _currentIndex + 1;

    final List<Widget> cardStack = [];

    // Next card (rendered underneath)
    if (_currentIndex + 1 < queue.length) {
      final nextNotification = queue[_currentIndex + 1];
      final nextActions = SmartActions.forNotification(nextNotification);

      cardStack.add(
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Transform.translate(
              offset: const Offset(0, -20), // Shift the bottom card UP so it peeks over the top card
              child: Transform.scale(
                scale: 0.92,
                alignment: Alignment.topCenter,
                child: ScopeSurface(
                variant: ScopeSurfaceVariant.glassDark,
                padding: const EdgeInsets.all(AppSpacing.lg),
                borderColor: AppColors.urgency(nextNotification.priority).withValues(alpha: 0.35),
                glow: nextNotification.priority == 'critical',
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: ReviewCard(
                    inverted: true,
                    notification: nextNotification,
                    actions: nextActions,
                    selectedAction: null,
                    currentIndex: progress, // visually shows next progress
                    totalCount: total,
                    onAction: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // Current card (rendered on top)
    final notification = queue[_currentIndex];
    final actions = SmartActions.forNotification(notification);
    final primary = SmartActions.primaryFor(actions);

    cardStack.add(
      Positioned.fill(
        key: ValueKey(notification.id),
        child: PhysicsSwipeCard(
          enabled: !_isTransitioning,
          onComplete: () => _handleDismissAction(notification, SmartActionType.complete),
          onArchive: () => _handleDismissAction(notification, SmartActionType.archive),
          onNext: _advance, // Swipe left
          onPrevious: _previous, // Swipe right
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ScopeSurface(
              variant: ScopeSurfaceVariant.glassDark,
              padding: const EdgeInsets.all(AppSpacing.lg),
              borderColor: AppColors.urgency(notification.priority).withValues(alpha: 0.35),
              glow: notification.priority == 'critical',
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ReviewCard(
                  inverted: true,
                  notification: notification,
                  actions: actions,
                  selectedAction: _selectedAction,
                  currentIndex: progress - 1,
                  totalCount: total,
                  onAction: (a) => _handleAction(a, notification),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.focusGradient),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: ScopeProgress(
                completed: progress,
                total: total,
                style: ScopeProgressStyle.compact,
                inverted: true,
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: cardStack,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'Swipe up complete · down archive · sides to skip',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white30,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  if (primary != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isTransitioning
                            ? null
                            : () => _handleAction(primary, notification),
                        icon: Icon(primary.icon, size: 20),
                        label: Text(primary.label),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isTransitioning ? null : _advance,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('Next'),
                    ),
                  ),
                ],
              ),
            ),
            SavedActionItemsWidget(controller: widget.controller),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inSession = widget.controller.inFocusSession;
    final queue = widget.controller.reviewQueue;
    final filterLabel = _filterLabel();

    if (!inSession && queue.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startSession();
      });
    }

    if (inSession && queue.isNotEmpty) return _buildImmersiveSession();

    return SafeArea(
      child: ScopeScreenBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Focus', style: theme.textTheme.headlineLarge),
            if (filterLabel.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(filterLabel, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: queue.isEmpty
                  ? const EmptyState.caughtUp()
                  : const ScopeLoading(message: 'Starting review…', compact: true),
            ),
          ],
        ),
      ),
    );
  }
}
