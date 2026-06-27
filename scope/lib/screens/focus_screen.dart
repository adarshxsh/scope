import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/screens/focus_complete_screen.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/motion/slide_fade_switcher.dart';
import 'package:scope/widgets/progress_widget.dart';
import 'package:scope/widgets/review_card.dart';
import 'package:scope/widgets/smart_action_chip.dart';

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

  AppNotification? get _current {
    if (widget.controller.inFocusSession) {
      return widget.controller.currentFocusNotification;
    }
    return widget.controller.reviewQueue.isEmpty
        ? null
        : widget.controller.reviewQueue.first;
  }

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

  String _applicationName(AppNotification notification) {
    final pkg = notification.packageName;
    if (pkg.contains('.')) {
      final parts = pkg.split('.');
      return parts.last.replaceAll('_', ' ').toUpperCase();
    }
    return pkg;
  }

  String _summaryText(AppNotification notification) {
    final features = notification.extractedFeatures;
    if (features?['hasDeadline'] == true) {
      return 'Application closes soon.';
    }
    if (notification.content.isNotEmpty) {
      final content = notification.content;
      return content.length > 120 ? '${content.substring(0, 117)}...' : content;
    }
    return 'Review and choose your next action.';
  }

  bool _hasDetectedInfo(ExtractedFeatures features) {
    return features.hasDeadline ||
        features.amount != null ||
        features.urls.isNotEmpty ||
        features.phoneNumbers.isNotEmpty;
  }

  Widget _buildFullscreenReels(BuildContext context) {
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
    );
    final notification = _current!;
    final queue = widget.controller.reviewQueue;
    final actions = SmartActions.forNotification(notification);
    final quickActions = actions.where((a) => a.type != SmartActionType.archive).toList();
    final primary = SmartActions.primaryFor(actions);
    final progress = widget.controller.focusSessionProgressCount;
    final total = widget.controller.focusSessionQueueIds.isEmpty
        ? queue.length
        : widget.controller.focusSessionQueueIds.length;

    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();

    final urgencyAccent = AppTheme.urgencyColor(notification.priority);

    return Theme(
      data: theme,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF090D16), Color(0xFF131124)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 200) {
                  _handleSkip();
                }
              },
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
                    child: Column(
                      children: [
                        // Progress bar at the top
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: total > 0 ? progress / total : 0.0,
                              backgroundColor: Colors.white10,
                              color: theme.colorScheme.primary,
                              minHeight: 3,
                            ),
                          ),
                        ),
                        // Top Header Row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
                                onPressed: () {
                                  _handleAction(const SmartAction(
                                    label: 'Archive',
                                    icon: Icons.archive,
                                    type: SmartActionType.archive,
                                  ));
                                },
                                tooltip: 'Archive notification',
                              ),
                              const Spacer(),
                              Text(
                                _applicationName(notification),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${progress + 1} / $total',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Main content scrollable area
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Urgency level indicator
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: urgencyAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: urgencyAccent.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      notification.priority?.toUpperCase() ?? 'NORMAL',
                                      style: TextStyle(
                                        color: urgencyAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Notification Title
                                  Text(
                                    notification.title.isNotEmpty ? notification.title : notification.packageName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Notification Content
                                  Text(
                                    _summaryText(notification),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Divider(color: Colors.white10),
                                  const SizedBox(height: 16),
                                  AIReasonWidget(notification: notification),
                                  if (_hasDetectedInfo(features)) ...[
                                    const SizedBox(height: 20),
                                    _DetectedInfoDark(features: features),
                                  ],
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Bottom Actions area overlay
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (quickActions.isNotEmpty) ...[
                                const Text(
                                  'Quick Actions',
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: quickActions.map((action) {
                                    return SmartActionChip(
                                      action: action,
                                      selected: _selectedAction == action.type,
                                      onPressed: () => _handleAction(action),
                                    );
                                  }).toList(),
                                ),
                              ],
                              if (primary != null) ...[
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: FilledButton.icon(
                                    onPressed: _isTransitioning ? null : () => _handleAction(primary),
                                    icon: Icon(primary.icon, size: 22),
                                    label: Text(primary.label),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.colorScheme.primary,
                                      foregroundColor: theme.colorScheme.onPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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

    if (!inSession && widget.controller.reviewQueue.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.startFocusSession();
      });
    }

    if (inSession && widget.controller.reviewQueue.isNotEmpty) {
      return _buildFullscreenReels(context);
    }

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
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final inSession = widget.controller.inFocusSession;
    final queue = widget.controller.reviewQueue;

    if (queue.isEmpty) {
      return const EmptyState.caughtUp();
    }

    if (!inSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.startFocusSession();
      });
    }

    final notification = _current;
    if (notification == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishSession());
      return const EmptyState.caughtUp();
    }

    final actions = SmartActions.forNotification(notification);
    final primary = SmartActions.primaryFor(actions);
    final progress = widget.controller.focusSessionProgressCount;
    final total = widget.controller.focusSessionQueueIds.isEmpty
        ? queue.length
        : widget.controller.focusSessionQueueIds.length;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 200) {
                _handleSkip();
              }
            },
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
      ],
    );
  }
}

class _DetectedInfoDark extends StatelessWidget {
  final ExtractedFeatures features;

  const _DetectedInfoDark({required this.features});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detected',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        if (features.hasDeadline) _row(context, Icons.event, 'Deadline detected'),
        if (features.amount != null) _row(context, Icons.currency_rupee, '₹${features.amount}'),
        if (features.urls.isNotEmpty) _row(context, Icons.link, features.urls.first),
        if (features.phoneNumbers.isNotEmpty) _row(context, Icons.phone, features.phoneNumbers.first),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
