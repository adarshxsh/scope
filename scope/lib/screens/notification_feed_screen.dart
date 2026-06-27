/// Minimal notification feed screen for Phase 1.
///
/// Polls the [NotificationBridge] every few seconds to display
/// captured notifications in a scrollable list.
/// Shows a permission banner when listener access is not granted.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/testing/test_notification_generator.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/screens/diagnostic_screen.dart';

class NotificationFeedScreen extends StatefulWidget {
  /// Allow injecting dependencies for testing.
  final NotificationBridge? bridge;
  final NotificationStorage? storage;
  final GhostAnalysisEngine? engine;

  const NotificationFeedScreen({super.key, this.bridge, this.storage, this.engine});

  @override
  State<NotificationFeedScreen> createState() => _NotificationFeedScreenState();
}

class _NotificationFeedScreenState extends State<NotificationFeedScreen> {
  late final NotificationBridge _bridge;
  late final NotificationStorage _storage;

  GhostAnalysisEngine? _analysisEngineBacking;
  GhostAnalysisEngine get _analysisEngine {
    if (_analysisEngineBacking == null) {
      _analysisEngineBacking = widget.engine ?? GhostAnalysisEngine();
      _analysisEngineBacking!.initialize();
    }
    return _analysisEngineBacking!;
  }

  List<AppNotification> _notifications = [];
  bool _isListenerEnabled = false;
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? NotificationBridge();
    _storage = widget.storage ?? InMemoryNotificationStorage();
    // Pre-initialize rules asset loading
    _analysisEngine.initialize();

    // Initial check + start polling
    _checkPermissionAndFetch();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchNotifications(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndFetch() async {
    final enabled = await _bridge.isListenerEnabled();
    setState(() => _isListenerEnabled = enabled);
    await _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      // Pull new notifications from the Android side
      final newNotifications = await _bridge.getNotifications();

      // Run raw notifications through the Ghost AI analysis engine before storing
      final analyzedNotifications = <AppNotification>[];
      for (final raw in newNotifications) {
        final analyzed = await _analysisEngine.analyze(raw);
        analyzedNotifications.add(analyzed);
      }

      // Save to storage
      if (analyzedNotifications.isNotEmpty) {
        await _storage.saveAll(analyzedNotifications);
      }

      // Get all stored (sorted newest first)
      final all = await _storage.getAll();

      if (mounted) {
        setState(() {
          _notifications = all;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AttentionOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DiagnosticScreen(engine: _analysisEngine),
                ),
              );
            },
            tooltip: 'Diagnostics',
          ),
          TextButton.icon(
            icon: const Icon(Icons.science, size: 18),
            label: const Text('TEST'),
            onPressed: () async {
              // Generate mock notifications directly in Dart
              final generator = TestNotificationGenerator();
              final testNotifs = generator.generateAll();
              
              // Run through analysis engine
              final analyzedNotifs = <AppNotification>[];
              for (final raw in testNotifs) {
                final analyzed = await _analysisEngine.analyze(raw);
                analyzedNotifs.add(analyzed);
              }
              
              // Save them to local storage
              await _storage.saveAll(analyzedNotifs);
              
              // Refresh the UI
              await _fetchNotifications();
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('10 test notifications generated & analyzed locally!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissionAndFetch,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Permission banner
          if (!_isListenerEnabled)
            MaterialBanner(
              content: const Text(
                'Notification access is not enabled. '
                'Tap to open settings and grant permission.',
              ),
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              actions: [
                TextButton(
                  onPressed: () => _bridge.openNotificationSettings(),
                  child: const Text('OPEN SETTINGS'),
                ),
                TextButton(
                  onPressed: _checkPermissionAndFetch,
                  child: const Text('RE-CHECK'),
                ),
              ],
            ),

          // Notification count header
          if (_notifications.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_notifications.length} notification(s) captured',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await _storage.clear();
                      setState(() => _notifications = []);
                    },
                    child: const Text('CLEAR ALL'),
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No notifications captured yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Make sure notification access is enabled\n'
              'and some notifications arrive on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _notifications.length,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return _NotificationCard(notification: notification);
      },
    );
  }
}

/// Card widget for displaying a single notification.
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  Color _getBorderColor(String? priority) {
    switch (priority) {
      case 'critical':
        return Colors.red.shade400;
      case 'high':
        return Colors.orange.shade400;
      case 'medium':
        return Colors.blue.shade200;
      case 'low':
        return Colors.grey.shade300;
      default:
        return Colors.grey.shade200;
    }
  }

  Widget _buildPriorityBadge(String? priority) {
    if (priority == null) return const SizedBox.shrink();

    Color color;
    switch (priority) {
      case 'critical':
        color = Colors.red.shade700;
        break;
      case 'high':
        color = Colors.orange.shade800;
        break;
      case 'medium':
        color = Colors.blue.shade700;
        break;
      case 'low':
        color = Colors.grey.shade600;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 9,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(notification.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    final priority = notification.priority ?? 'medium';
    final isLow = priority == 'low';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: isLow ? 0.5 : 2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: _getBorderColor(notification.priority), width: isLow ? 0.5 : 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Opacity(
        opacity: isLow ? 0.65 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: notification.priority == 'critical'
                    ? Colors.red.shade100
                    : (notification.priority == 'high'
                        ? Colors.orange.shade100
                        : (notification.isOngoing
                            ? Colors.blue.shade100
                            : Colors.grey.shade200)),
                child: Icon(
                  notification.priority == 'critical'
                      ? Icons.gpp_bad
                      : (notification.priority == 'high'
                          ? Icons.warning_amber_rounded
                          : (notification.isOngoing
                              ? Icons.notifications_active
                              : Icons.notifications)),
                  color: notification.priority == 'critical'
                      ? Colors.red
                      : (notification.priority == 'high'
                          ? Colors.orange.shade800
                          : (notification.isOngoing ? Colors.blue : Colors.grey)),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title.isNotEmpty
                                ? notification.title
                                : '(No title)',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: notification.priority == 'critical' ||
                                          notification.priority == 'high'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                        ),
                        _buildPriorityBadge(notification.priority),
                      ],
                    ),
                    if (notification.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(notification.content),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${notification.packageName} · $timeStr'
                      '${notification.classifiedCategory != null ? ' · ${notification.classifiedCategory}' : (notification.category != null ? ' · ${notification.category}' : '')}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
