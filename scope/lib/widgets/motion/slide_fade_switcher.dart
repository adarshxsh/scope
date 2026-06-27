import 'package:flutter/material.dart';
import 'package:scope/theme/motion.dart';

/// Fade + slide transition for single-item content swaps (Focus review cards).
class SlideFadeSwitcher extends StatelessWidget {
  final Widget child;
  final Object? transitionKey;

  const SlideFadeSwitcher({
    super.key,
    required this.child,
    this.transitionKey,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppMotion.enter));

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      child: KeyedSubtree(
        key: ValueKey(transitionKey),
        child: child,
      ),
    );
  }
}
