import 'package:flutter/material.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/widgets/primitives/scope_chip.dart';

/// Contextual action chip — wraps [ScopeChip] with smart action data.
class SmartActionChip extends StatelessWidget {
  final SmartAction action;
  final VoidCallback? onPressed;
  final bool selected;
  final bool inverted;

  const SmartActionChip({
    super.key,
    required this.action,
    this.onPressed,
    this.selected = false,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    return ScopeChip(
      label: action.label,
      icon: action.icon,
      onPressed: onPressed,
      selected: selected,
      inverted: inverted,
      accent: action.color,
      tone: action.isPrimary ? ScopeChipTone.accent : ScopeChipTone.neutral,
    );
  }
}
