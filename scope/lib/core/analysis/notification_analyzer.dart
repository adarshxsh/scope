import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';

/// Contract interface for a single notification analyzer component.
abstract class NotificationAnalyzer {
  /// Analyzes a notification and returns classification details.
  Future<AnalysisResult> analyze(AppNotification notification);
}
