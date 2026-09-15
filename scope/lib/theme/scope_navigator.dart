import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scope/screens/ai_playground_screen.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/theme/motion.dart';

/// Consistent page transitions across Scope.
abstract final class ScopeNavigator {
  static Future<T?> push<T>(BuildContext context, Widget page) {
    if (kReleaseMode && (page is DiagnosticScreen || page is AiPlaygroundScreen)) {
      throw UnsupportedError('${page.runtimeType} is disabled in release mode.');
    }
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: AppMotion.standard,
        reverseTransitionDuration: AppMotion.fast,
        transitionsBuilder: AppMotion.fadeSlideTransition,
      ),
    );
  }

  static Future<T?> pushReplacement<T>(BuildContext context, Widget page) {
    if (kReleaseMode && (page is DiagnosticScreen || page is AiPlaygroundScreen)) {
      throw UnsupportedError('${page.runtimeType} is disabled in release mode.');
    }
    return Navigator.of(context).pushReplacement<T, void>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: AppMotion.standard,
        reverseTransitionDuration: AppMotion.fast,
        transitionsBuilder: AppMotion.fadeSlideTransition,
      ),
    );
  }
}
