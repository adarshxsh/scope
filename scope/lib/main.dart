import 'package:flutter/material.dart';
import 'package:scope/screens/notification_feed_screen.dart';

void main() {
  runApp(const AttentionOSApp());
}

/// Root widget for the AttentionOS application.
///
/// Phase 1: Simple MaterialApp with a single route (notification feed).
/// Future phases will add routing, theming, and additional screens.
class AttentionOSApp extends StatelessWidget {
  const AttentionOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttentionOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const NotificationFeedScreen(),
    );
  }
}
