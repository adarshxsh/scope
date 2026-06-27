import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_theme.dart';

// ── Dismiss thresholds ────────────────────────────────────────────────────────
const double _kPosFraction = 0.28; // 28% of screen size triggers dismiss
const double _kMinVelocity = 650.0; // px/s fling speed

/// 2D Physics Card for Focus Session.
class PhysicsSwipeCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onComplete; // Swipe Up
  final VoidCallback? onArchive; // Swipe Down
  final VoidCallback? onNext; // Swipe Left
  final VoidCallback? onPrevious; // Swipe Right
  final bool enabled;

  const PhysicsSwipeCard({
    super.key,
    required this.child,
    this.onComplete,
    this.onArchive,
    this.onNext,
    this.onPrevious,
    this.enabled = true,
  });

  @override
  State<PhysicsSwipeCard> createState() => _PhysicsSwipeCardState();
}

class _PhysicsSwipeCardState extends State<PhysicsSwipeCard>
    with SingleTickerProviderStateMixin {
  late final _animController = AnimationController(vsync: this);
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);

  bool _hasFiredHaptic = false;
  bool _isDismissing = false;

  @override
  void dispose() {
    _animController.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    if (!widget.enabled) return;
    _animController.stop();
    _hasFiredHaptic = false;
    _isDismissing = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _isDismissing) return;

    _offset.value += d.delta;

    if (!_hasFiredHaptic) {
      final size = MediaQuery.sizeOf(context);
      final off = _offset.value;
      if (off.dy.abs() >= size.height * _kPosFraction ||
          off.dx.abs() >= size.width * _kPosFraction) {
        HapticFeedback.mediumImpact();
        _hasFiredHaptic = true;
      }
    }
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (!widget.enabled || _isDismissing) return;

    final pos = _offset.value;
    final vel = d.velocity.pixelsPerSecond;
    final size = MediaQuery.sizeOf(context);

    // Determine primary axis of movement
    final isVertical = pos.dy.abs() > pos.dx.abs();

    final overPos = isVertical
        ? pos.dy.abs() >= size.height * _kPosFraction
        : pos.dx.abs() >= size.width * _kPosFraction;

    final overVel = isVertical
        ? vel.dy.abs() >= _kMinVelocity
        : vel.dx.abs() >= _kMinVelocity;

    if (overPos || overVel) {
      _isDismissing = true;
      if (!_hasFiredHaptic) HapticFeedback.mediumImpact();

      // Exit direction
      final exitOffset = isVertical
          ? Offset(0, pos.dy < 0 ? -size.height * 1.5 : size.height * 1.5)
          : Offset(pos.dx < 0 ? -size.width * 1.5 : size.width * 1.5, 0);

      final tween = Tween<Offset>(begin: pos, end: exitOffset);
      
      // Simulate spring duration based on velocity
      final anim = tween.animate(CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ));

      anim.addListener(() {
        _offset.value = anim.value;
      });

      _animController.duration = const Duration(milliseconds: 350);
      await _animController.forward(from: 0);

      if (!mounted) return;

      if (isVertical) {
        if (pos.dy < 0) {
          widget.onComplete?.call();
        } else {
          widget.onArchive?.call();
        }
      } else {
        if (pos.dx < 0) {
          widget.onNext?.call();
        } else {
          widget.onPrevious?.call();
        }
      }

      // Reset
      _offset.value = Offset.zero;
      _isDismissing = false;
      _hasFiredHaptic = false;
    } else {
      // Snap back to center
      final tween = Tween<Offset>(begin: pos, end: Offset.zero);
      final anim = tween.animate(CurvedAnimation(
        parent: _animController,
        curve: Curves.fastOutSlowIn,
      ));
      anim.addListener(() {
        _offset.value = anim.value;
      });
      _animController.duration = const Duration(milliseconds: 300);
      _animController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: widget.enabled ? _onPanStart : null,
      onPanUpdate: widget.enabled ? _onPanUpdate : null,
      onPanEnd: widget.enabled ? _onPanEnd : null,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offset,
        builder: (context, pos, child) {
          // Normalize [-1, 1] for both axes based on 45% of screen size
          final normX = (pos.dx / (size.width * 0.45)).clamp(-1.0, 1.0);
          final normY = (pos.dy / (size.height * 0.45)).clamp(-1.0, 1.0);
          
          final absX = normX.abs();
          final absY = normY.abs();
          final maxAbs = math.max(absX, absY); // For scale/shadow

          final isUp = pos.dy < 0;
          final isDown = pos.dy > 0;
          
          final isPrimaryVertical = absY > absX;

          // 3D Tilt: rotateX based on Y drag, rotateY based on X drag
          final rotXRad = normY * -5.0 * math.pi / 180.0;
          final rotYRad = normX * 5.0 * math.pi / 180.0;
          // Z rotation for extra physical feel
          final rotZRad = normX * 3.0 * math.pi / 180.0; 

          final scale = 1.0 - maxAbs * 0.02; // subtle shrink
          final shadowBlur = 8.0 + maxAbs * 25.0; // deeper shadow
          final shadowOffY = 2.0 + maxAbs * 12.0;
          final shadowAlpha = 0.18 + maxAbs * 0.25;

          final indicatorT = ((maxAbs - 0.10) / 0.25).clamp(0.0, 1.0);
          final bgT = (maxAbs * 0.30).clamp(0.0, 0.30);

          Color? actionColor;
          if (isPrimaryVertical) {
            actionColor = isUp ? AppColors.complete : AppColors.remind;
          } else {
             // For horizontal, maybe standard blue or just transparent
             actionColor = AppColors.seed;
          }

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Background gradient
              if (isPrimaryVertical)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: bgT,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: isUp ? Alignment.topCenter : Alignment.bottomCenter,
                            end: isUp ? Alignment.bottomCenter : Alignment.topCenter,
                            colors: [
                              actionColor.withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.65],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Badges
              if (isPrimaryVertical && isUp)
                Positioned(
                  top: 16,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: indicatorT,
                      child: Transform.scale(
                        scale: 0.72 + indicatorT * 0.28,
                        child: const _ActionBadge(
                          icon: Icons.check_rounded,
                          label: 'Complete',
                          color: AppColors.complete,
                        ),
                      ),
                    ),
                  ),
                ),

              if (isPrimaryVertical && isDown)
                Positioned(
                  bottom: 16,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: indicatorT,
                      child: Transform.scale(
                        scale: 0.72 + indicatorT * 0.28,
                        child: const _ActionBadge(
                          icon: Icons.archive_outlined,
                          label: 'Archive',
                          color: AppColors.remind,
                        ),
                      ),
                    ),
                  ),
                ),

              // Left/Right badges (optional, keeping minimal for now)
              
              // 3D Card
              Positioned.fill(
                child: Transform(
                  transform: Matrix4.translationValues(pos.dx, pos.dy, 0.0)
                    ..setEntry(3, 2, 0.001) // perspective
                    ..rotateX(rotXRad)
                    ..rotateY(rotYRad)
                    ..rotateZ(rotZRad),
                  alignment: Alignment.center,
                  child: Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha),
                            blurRadius: shadowBlur,
                            offset: Offset(0, shadowOffY),
                          ),
                        ],
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ActionBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
