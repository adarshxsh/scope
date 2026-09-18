import 'package:flutter/material.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_action_validator.dart';
import 'package:scope/core/utils/smart_actions.dart';

/// Result of executing a SmartAction launch.
class SmartActionLaunchResult {
  final bool isSuccess;
  final bool isBlocked;
  final String message;
  final ValidationStatus? validationStatus;
  final String? fallbackReason;

  const SmartActionLaunchResult.success({
    required this.message,
  })  : isSuccess = true,
        isBlocked = false,
        validationStatus = ValidationStatus.valid,
        fallbackReason = null;

  const SmartActionLaunchResult.blocked({
    required this.message,
    required this.validationStatus,
  })  : isSuccess = false,
        isBlocked = true,
        fallbackReason = null;

  const SmartActionLaunchResult.fallback({
    required this.message,
    required this.fallbackReason,
    this.validationStatus = ValidationStatus.valid,
  })  : isSuccess = false,
        isBlocked = false;
}

/// Service that coordinates validation, audit logging, and fallback recovery
/// when executing Smart Action URLs and App Intents.
class SmartActionLauncherService {
  final NotificationBridge _bridge;

  SmartActionLauncherService({NotificationBridge? bridge})
      : _bridge = bridge ?? NotificationBridge();

  /// Launches a SmartAction safely with security guardrails, audit logging,
  /// and fallback recovery paths.
  Future<SmartActionLaunchResult> launchAction({
    BuildContext? context,
    required SmartAction action,
    required AppNotification notification,
  }) async {
    final validation = SmartActionValidator.validateAction(action, notification);

    final auditEntry = ActionAuditLogEntry(
      notificationId: notification.id,
      actionType: action.type,
      originalUrlRedacted: validation.redactedUrlForAudit,
      targetPackage: validation.targetPackage,
      status: validation.status,
      isAllowed: validation.isValid,
      reason: validation.reason,
    );
    SmartActionValidator.recordAuditLog(auditEntry);

    if (!validation.isValid) {
      final blockedResult = SmartActionLaunchResult.blocked(
        message: 'Action blocked: ${validation.reason}',
        validationStatus: validation.status,
      );

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(blockedResult.message),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return blockedResult;
    }

    // Handle URL launching
    if (validation.sanitizedUrl != null) {
      final launched = await _bridge.launchUrl(validation.sanitizedUrl!);
      if (launched) {
        final successResult = SmartActionLaunchResult.success(
          message: 'Launched: ${action.label}',
        );
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening ${action.label}...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return successResult;
      } else {
        // Fallback path when URL launch fails (e.g. no browser)
        final fallbackResult = SmartActionLaunchResult.fallback(
          message: 'Unable to open link. No compatible browser found.',
          fallbackReason: 'URL launch handler returned false.',
        );

        SmartActionValidator.recordAuditLog(ActionAuditLogEntry(
          notificationId: notification.id,
          actionType: action.type,
          originalUrlRedacted: validation.redactedUrlForAudit,
          status: ValidationStatus.malformedUrl,
          isAllowed: false,
          reason: 'Fallback triggered: URL launch failed on target platform.',
        ));

        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(fallbackResult.message),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return fallbackResult;
      }
    }

    // Handle App launch
    if (validation.targetPackage != null) {
      final launched = await _bridge.launchApp(validation.targetPackage!);
      if (launched) {
        final successResult = SmartActionLaunchResult.success(
          message: 'Opened app for ${action.label}',
        );
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening ${validation.targetPackage}...'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return successResult;
      } else {
        // Fallback path when target app is not installed
        final fallbackResult = SmartActionLaunchResult.fallback(
          message: 'App not installed (${validation.targetPackage}).',
          fallbackReason: 'Target package is not installed on device.',
        );

        SmartActionValidator.recordAuditLog(ActionAuditLogEntry(
          notificationId: notification.id,
          actionType: action.type,
          targetPackage: validation.targetPackage,
          status: ValidationStatus.invalidPackageName,
          isAllowed: false,
          reason: 'Fallback triggered: Target app not installed.',
        ));

        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(fallbackResult.message),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return fallbackResult;
      }
    }

    return const SmartActionLaunchResult.success(
      message: 'Internal action processed.',
    );
  }
}
