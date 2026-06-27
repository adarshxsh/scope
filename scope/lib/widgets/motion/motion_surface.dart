import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scope/theme/motion.dart';

/// A reusable interactive surface that scales down on press and provides haptic feedback.
/// Used for buttons, cards, and list items.
class MotionSurface extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;
  final BorderRadius? borderRadius;

  const MotionSurface({
    super.key, 
    this.onTap, 
    required this.child,
    this.enabled = true,
    this.borderRadius,
  });

  @override
  State<MotionSurface> createState() => _MotionSurfaceState();
}

class _MotionSurfaceState extends State<MotionSurface> {
  bool _pressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _pressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    HapticFeedback.lightImpact();
    setState(() => _pressed = false);
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? AppMotion.pressScale : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.smooth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: () {
            if (!widget.enabled || widget.onTap == null) return;
            HapticFeedback.lightImpact();
            widget.onTap?.call();
          },
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}
