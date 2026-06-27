import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';

/// Constrains content width and accounts for floating navigation.
class ScopeScreenBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const ScopeScreenBody({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: Padding(
          padding: padding ??
              const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.screenPadding,
                AppSpacing.screenPadding,
                AppSpacing.xxl,
              ),
          child: child,
        ),
      ),
    );
  }
}
