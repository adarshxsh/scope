import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';

/// A contextual action suggested for a notification.
class SmartAction {
  final String label;
  final IconData icon;
  final SmartActionType type;
  final Color? color;
  final bool isPrimary;

  const SmartAction({
    required this.label,
    required this.icon,
    required this.type,
    this.color,
    this.isPrimary = false,
  });
}

enum SmartActionType {
  openApp,
  openUrl,
  addCalendar,
  remind,
  archive,
  complete,
  pay,
  track,
  download,
  reply,
  join,
  viewStatement,
}

/// Generates contextual smart actions from notification content and analysis.
abstract final class SmartActions {
  static const _calendarBlue = Color(0xFF1565C0);
  static const _remindOrange = Color(0xFFE65100);
  static const _completeGreen = Color(0xFF2E7D32);
  static const _financePurple = Color(0xFF6A1B9A);
  static const _portalTeal = Color(0xFF00695C);

  static List<SmartAction> forNotification(AppNotification notification) {
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final text = '${notification.title} ${notification.content}'.toLowerCase();
    final pkg = notification.packageName.toLowerCase();
    final area = FocusAreaMapper.areaFor(notification);
    final actions = <SmartAction>[];

    if (features.hasDeadline ||
        _containsAny(text, ['appointment', 'meeting', 'deadline', 'closes'])) {
      actions.add(const SmartAction(
        label: 'Add Calendar',
        icon: Icons.calendar_today_outlined,
        type: SmartActionType.addCalendar,
        color: _calendarBlue,
        isPrimary: true,
      ));
    }

    if (features.urls.isNotEmpty ||
        _containsAny(text, ['portal', 'apply', 'website', 'visit', 'scholarship'])) {
      actions.add(SmartAction(
        label: _containsAny(text, ['portal', 'scholarship', 'apply']) ? 'Open Portal' : 'Open Website',
        icon: Icons.language_outlined,
        type: SmartActionType.openUrl,
        color: _portalTeal,
        isPrimary: actions.isEmpty,
      ));
    }

    if (_containsAny(text, ['meeting', 'standup', 'zoom', 'teams'])) {
      actions.add(SmartAction(
        label: 'Join',
        icon: Icons.videocam_outlined,
        type: SmartActionType.join,
        color: _calendarBlue,
        isPrimary: actions.isEmpty,
      ));
    }

    if (_containsAny(text, ['pdf', 'document', 'download']) || area == FocusArea.government) {
      actions.add(const SmartAction(
        label: 'Download PDF',
        icon: Icons.download_outlined,
        type: SmartActionType.download,
        color: _portalTeal,
      ));
    }

    if (_containsAny(pkg, ['hdfc', 'sbi', 'paytm', 'phonepe', 'gpay']) ||
        features.amount != null) {
      actions.add(SmartAction(
        label: 'Pay',
        icon: Icons.payment,
        type: SmartActionType.pay,
        color: _financePurple,
        isPrimary: actions.isEmpty,
      ));
      actions.add(const SmartAction(
        label: 'View Statement',
        icon: Icons.receipt_long_outlined,
        type: SmartActionType.viewStatement,
        color: _financePurple,
      ));
    }

    if (_containsAny(text, ['delivery', 'shipped', 'track', 'package'])) {
      actions.add(SmartAction(
        label: 'Track Package',
        icon: Icons.local_shipping_outlined,
        type: SmartActionType.track,
        color: _portalTeal,
        isPrimary: actions.isEmpty,
      ));
    }

    if (_containsAny(text, ['reply', '@', 'message', 'chat'])) {
      actions.add(const SmartAction(
        label: 'Reply',
        icon: Icons.reply_outlined,
        type: SmartActionType.reply,
        color: _calendarBlue,
      ));
    }



    actions.add(const SmartAction(
      label: 'Archive',
      icon: Icons.archive_outlined,
      type: SmartActionType.archive,
    ));

    actions.add(const SmartAction(
      label: 'Mark Complete',
      icon: Icons.check_circle_outline,
      type: SmartActionType.complete,
      color: _completeGreen,
    ));

    return _dedupe(actions);
  }

  static SmartAction? primaryFor(List<SmartAction> actions) {
    for (final action in actions) {
      if (action.isPrimary) return action;
    }
    return actions.isNotEmpty ? actions.first : null;
  }

  static List<SmartAction> _dedupe(List<SmartAction> actions) {
    final seen = <SmartActionType>{};
    return actions.where((a) => seen.add(a.type)).toList();
  }

  static bool _containsAny(String haystack, List<String> needles) {
    return needles.any(haystack.contains);
  }
}
