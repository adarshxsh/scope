import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_theme.dart';

enum ScopeIconBoxSize { sm, md, lg }

/// Unified icon container — dark edition.
///
/// Default background is a slightly lighter dark chip.
/// Pass explicit [color] and [background] for semantic coloring.
class ScopeIconBox extends StatelessWidget {
  final IconData icon;
  final ScopeIconBoxSize size;
  final Color? color;
  final Color? background;

  const ScopeIconBox({
    super.key,
    required this.icon,
    this.size = ScopeIconBoxSize.md,
    this.color,
    this.background,
  });

  double get _boxSize => switch (size) {
        ScopeIconBoxSize.sm => 32,
        ScopeIconBoxSize.md => 40,
        ScopeIconBoxSize.lg => 48,
      };

  double get _iconSize => switch (size) {
        ScopeIconBoxSize.sm => 16,
        ScopeIconBoxSize.md => 20,
        ScopeIconBoxSize.lg => 24,
      };

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.onSurface.withValues(alpha: 0.70);
    final bg = background ?? AppColors.onSurface.withValues(alpha: 0.07);

    return Container(
      width: _boxSize,
      height: _boxSize,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
      ),
      child: Icon(icon, size: _iconSize, color: fg),
    );
  }
}
