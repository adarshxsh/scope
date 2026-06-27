import 'package:flutter/material.dart';
import 'package:scope/theme/motion.dart';

/// Material 3 motion language — single source for all Scope animations.
abstract final class AppMotion {
  // Standard animation durations (180–300ms)
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 300);

  // Easing curves
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasis = Curves.easeOutBack;
  
  // Spring animations for gestures
  static const Curve spring = Curves.easeOutBack; 
  static const Curve smooth = Curves.fastOutSlowIn;

  // Scale transitions
  static const double pressScale = 0.98;
  static const double liftScale = 1.02;
  
  static const Offset slideBegin = Offset(0, 0.03);

  static Widget fadeSlide({
    required Animation<double> animation,
    required Widget child,
  }) {
    final slide = Tween<Offset>(begin: slideBegin, end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: enter),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }

  static Widget fadeSlideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return fadeSlide(animation: animation, child: child);
  }

  static Widget cardExit({
    required bool exiting,
    required Widget child,
  }) {
    return AnimatedOpacity(
      opacity: exiting ? 0 : 1,
      duration: standard,
      curve: exit,
      child: AnimatedScale(
        scale: exiting ? pressScale : 1,
        duration: standard,
        curve: exit,
        child: child,
      ),
    );
  }
}
