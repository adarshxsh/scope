import 'package:flutter/material.dart';
import 'package:scope/core/security/pii_redactor.dart';

/// Reusable UI widget that encapsulates PII elements, defaulting to a masked state
/// with interactive tap-to-reveal controls.
class RedactedView extends StatefulWidget {
  final String? value;
  final String? maskedValue;
  final String? label;
  final TextStyle? style;
  final bool initialRedacted;
  final Widget Function(BuildContext context, bool isRedacted, String displayText)? builder;

  const RedactedView({
    super.key,
    required this.value,
    this.maskedValue,
    this.label,
    this.style,
    this.initialRedacted = true,
    this.builder,
  });

  @override
  State<RedactedView> createState() => _RedactedViewState();
}

class _RedactedViewState extends State<RedactedView> {
  late bool _isRedacted;

  @override
  void initState() {
    super.initState();
    _isRedacted = widget.initialRedacted;
  }

  void _toggleRedaction() {
    setState(() {
      _isRedacted = !_isRedacted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rawValue = widget.value ?? '';
    final displayText = _isRedacted
        ? (widget.maskedValue ?? (rawValue.isEmpty ? 'None' : PiiRedactor.redactText(rawValue)))
        : (rawValue.isEmpty ? 'None' : rawValue);

    if (widget.builder != null) {
      return GestureDetector(
        onTap: _toggleRedaction,
        behavior: HitTestBehavior.opaque,
        child: widget.builder!(context, _isRedacted, displayText),
      );
    }

    final theme = Theme.of(context);
    final textStyle = widget.style ?? theme.textTheme.bodyMedium;

    return InkWell(
      onTap: _toggleRedaction,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.label != null && widget.label!.isNotEmpty) ...[
              Text(
                '${widget.label}: ',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
            Flexible(
              child: Text(
                displayText,
                style: textStyle?.copyWith(
                  color: _isRedacted
                      ? (widget.value != null && widget.value!.isNotEmpty ? Colors.orange.shade300 : Colors.grey)
                      : (textStyle.color ?? theme.textTheme.bodyMedium?.color),
                  fontWeight: widget.value != null && widget.value!.isNotEmpty
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
            if (widget.value != null && widget.value!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Icon(
                _isRedacted ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 16,
                color: _isRedacted ? Colors.orange.shade300 : theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
