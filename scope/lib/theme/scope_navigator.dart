import 'package:flutter/material.dart';
import 'package:scope/theme/motion.dart';

/// Consistent page transitions across Scope.
abstract final class ScopeNavigator {
  static Future<T?> push<T>(BuildContext context, Widget page) {
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
