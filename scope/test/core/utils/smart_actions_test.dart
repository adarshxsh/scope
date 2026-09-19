import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_actions.dart';

void main() {
  group('SmartActions - targetUrl population and scheme filtering', () {
    test('attaches valid extracted HTTP/HTTPS URL as targetUrl', () {
      final notification = AppNotification(
        id: '1',
        packageName: 'com.example.app',
        title: 'Scholarship Portal Open',
        content: 'Apply now at https://scholarship.gov.in/portal',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'urls': ['https://scholarship.gov.in/portal'],
        },
      );

      final actions = SmartActions.forNotification(notification);
      final openAction = actions.firstWhere((a) => a.type == SmartActionType.openUrl);

      expect(openAction.targetUrl, equals('https://scholarship.gov.in/portal'));
    });

    test('filters out unsafe schemes and leaves targetUrl null if only unsafe schemes present', () {
      final notification = AppNotification(
        id: '2',
        packageName: 'com.example.app',
        title: 'Malicious Alert',
        content: 'Click file:///etc/passwd to view portal',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'urls': ['file:///etc/passwd', 'javascript:alert(1)'],
        },
      );

      final actions = SmartActions.forNotification(notification);
      final openAction = actions.firstWhere((a) => a.type == SmartActionType.openUrl);

      expect(openAction.targetUrl, isNull);
    });

    test('picks the first valid HTTP/HTTPS URL when multiple extracted URLs are present', () {
      final notification = AppNotification(
        id: '3',
        packageName: 'com.example.app',
        title: 'Portal Links',
        content: 'Check unsafe link intent://app or safe link https://valid.org/doc',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'urls': ['intent://app', 'https://valid.org/doc', 'http://second.org'],
        },
      );

      final actions = SmartActions.forNotification(notification);
      final openAction = actions.firstWhere((a) => a.type == SmartActionType.openUrl);

      expect(openAction.targetUrl, equals('https://valid.org/doc'));
    });
  });
}
