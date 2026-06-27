import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/main_shell.dart';
import 'package:scope/theme/app_theme.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AttentionOSApp(),
    ),
  );
}

/// Root widget for Scope (AttentionOS).
class AttentionOSApp extends StatefulWidget {
  const AttentionOSApp({super.key});

  @override
  State<AttentionOSApp> createState() => _AttentionOSAppState();
}

class _AttentionOSAppState extends State<AttentionOSApp> {
  late final NotificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NotificationController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MainShell(controller: _controller),
    );
  }
}
