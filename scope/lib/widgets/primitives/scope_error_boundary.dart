import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';

/// Cold-start and general UI Error Boundary widget.
class ScopeErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, Object error, VoidCallback reset)? fallbackBuilder;

  const ScopeErrorBoundary({
    super.key,
    required this.child,
    this.fallbackBuilder,
  });

  @override
  State<ScopeErrorBoundary> createState() => _ScopeErrorBoundaryState();
}

class _ScopeErrorBoundaryState extends State<ScopeErrorBoundary> {
  Object? _error;

  void resetError() {
    setState(() {
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.fallbackBuilder != null) {
        return widget.fallbackBuilder!(context, _error!, resetError);
      }
      return _buildDefaultFallback(context);
    }

    return _ErrorWidgetScope(
      onError: (details) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _error == null) {
            setState(() {
              _error = details.exception;
            });
          }
        });
      },
      child: widget.child,
    );
  }

  Widget _buildDefaultFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.critical,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Something went wrong',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'An error occurred while loading or displaying content.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: resetError,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorWidgetScope extends StatefulWidget {
  final Widget child;
  final void Function(FlutterErrorDetails details) onError;

  const _ErrorWidgetScope({
    required this.child,
    required this.onError,
  });

  @override
  State<_ErrorWidgetScope> createState() => _ErrorWidgetScopeState();
}

class _ErrorWidgetScopeState extends State<_ErrorWidgetScope> {
  ErrorWidgetBuilder? _previousBuilder;

  @override
  void initState() {
    super.initState();
    _previousBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      widget.onError(details);
      return const SizedBox.shrink();
    };
  }

  @override
  void dispose() {
    if (_previousBuilder != null) {
      ErrorWidget.builder = _previousBuilder!;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
