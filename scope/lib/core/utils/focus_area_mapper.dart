import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';

/// Semantic focus areas shown on the home dashboard.
enum FocusArea {
  education,
  finance,
  government,
  health,
  meetings,
  payments,
  deliveries,
}

extension FocusAreaX on FocusArea {
  String get label => switch (this) {
        FocusArea.education => 'Education',
        FocusArea.finance => 'Finance',
        FocusArea.government => 'Government',
        FocusArea.health => 'Health',
        FocusArea.meetings => 'Meetings',
        FocusArea.payments => 'Payments',
        FocusArea.deliveries => 'Deliveries',
      };

  IconData get icon => switch (this) {
        FocusArea.education => Icons.school_outlined,
        FocusArea.finance => Icons.account_balance_outlined,
        FocusArea.government => Icons.account_balance_wallet_outlined,
        FocusArea.health => Icons.health_and_safety_outlined,
        FocusArea.meetings => Icons.groups_outlined,
        FocusArea.payments => Icons.payments_outlined,
        FocusArea.deliveries => Icons.local_shipping_outlined,
      };

  /// Short contextual description for dashboard cards.
  String descriptionFor(int count, List<AppNotification> items) {
    if (count == 0) return 'No pending items';

    return switch (this) {
      FocusArea.education => _deadlineLabel(count, items, 'deadline'),
      FocusArea.finance => '$count update${count == 1 ? '' : 's'}',
      FocusArea.government => count == 1 ? '1 verification' : '$count verifications',
      FocusArea.health => count == 1 ? '1 appointment' : '$count appointments',
      FocusArea.meetings => count == 1 ? '1 meeting' : '$count meetings',
      FocusArea.payments => count == 1 ? '1 payment' : '$count payments',
      FocusArea.deliveries => count == 1 ? '1 delivery' : '$count deliveries',
    };
  }

  String _deadlineLabel(int count, List<AppNotification> items, String keyword) {
    final withDeadline = items.where((n) => n.extractedFeatures?['hasDeadline'] == true).length;
    if (withDeadline > 0) {
      return withDeadline == 1 ? '1 deadline' : '$withDeadline deadlines';
    }
    return count == 1 ? '1 item' : '$count items';
  }
}

/// Maps analyzed notifications to dashboard focus areas.
abstract final class FocusAreaMapper {
  static FocusArea? areaFor(AppNotification notification) {
    final pkg = notification.packageName.toLowerCase();
    final category =
        (notification.classifiedCategory ?? notification.category ?? '').toLowerCase();
    final text = '${notification.title} ${notification.content}'.toLowerCase();

    if (_matchesAny(pkg, ['scholarship', 'edu', 'classroom', 'coursera']) ||
        _matchesAny(text, ['scholarship', 'gsoc', 'application', 'exam', 'course'])) {
      return FocusArea.education;
    }
    if (_matchesAny(pkg, ['gov', 'uidai', 'income tax', 'passport'])) {
      return FocusArea.government;
    }
    if (_matchesAny(pkg, ['apollo', 'health', 'practo', 'hospital']) ||
        category == 'health' ||
        _matchesAny(text, ['appointment', 'doctor', 'hospital'])) {
      return FocusArea.health;
    }
    if (_matchesAny(pkg, ['slack', 'teams', 'zoom', 'meet', 'calendar']) ||
        _matchesAny(text, ['meeting', 'standup', 'join', 'call'])) {
      return FocusArea.meetings;
    }
    if (_matchesAny(pkg, ['amazon', 'flipkart', 'myntra', 'delivery', 'swiggy', 'zomato']) ||
        _matchesAny(text, ['delivery', 'shipped', 'track', 'package', 'order'])) {
      return FocusArea.deliveries;
    }

    final features = notification.extractedFeatures;
    final hasAmount = features?['amount'] != null;
    if (hasAmount ||
        _matchesAny(pkg, ['hdfc', 'sbi', 'paytm', 'phonepe', 'gpay', 'bank']) ||
        category == 'finance') {
      return hasAmount ? FocusArea.payments : FocusArea.finance;
    }

    if (category == 'finance' || _matchesAny(pkg, ['bank', 'finance'])) {
      return FocusArea.finance;
    }

    return null;
  }

  static Map<FocusArea, int> countsFor(Iterable<AppNotification> notifications) {
    final counts = {for (final area in FocusArea.values) area: 0};
    for (final n in notifications) {
      final area = areaFor(n);
      if (area != null) counts[area] = counts[area]! + 1;
    }
    return counts;
  }

  static bool _matchesAny(String haystack, List<String> needles) {
    return needles.any(haystack.contains);
  }
}
