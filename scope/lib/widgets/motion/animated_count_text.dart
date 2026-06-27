import 'package:flutter/material.dart';
import 'package:scope/theme/motion.dart';

/// Counts upward with a subtle fade for progress and stat displays.
class AnimatedCountText extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String suffix;

  const AnimatedCountText({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: AppMotion.slow,
      curve: AppMotion.enter,
      builder: (context, animatedValue, _) {
        return Text('$animatedValue$suffix', style: style);
      },
    );
  }
}
