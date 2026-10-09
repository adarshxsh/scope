import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File localModelFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_ai_test');
    localModelFile = File('${tempDir.path}/model.tflite');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('GhostAI falls back without crashing when local storage model file is missing', () async {
    expect(localModelFile.existsSync(), isFalse);

    await GhostAI.instance.reloadModel(modelFile: localModelFile);

    // Fallback source should be bundled_asset or fallback_heuristics (if headless runner lacks native lib)
    expect(
      GhostAI.instance.modelSource,
      anyOf(equals('bundled_asset'), equals('fallback_heuristics')),
    );

    final notif = AppNotification(
      id: 'test-1',
      packageName: 'com.test',
      title: 'Alert',
      content: 'Important message',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final result = await GhostAI.predict(notif);
    expect(result.featureVector.length, equals(63));
    expect(result.reviewScore, isNotNull);
  });

  test('Placing valid model binary in local storage attempts reload and fallback recovers when removed', () async {
    final assetBytes = File('assets/model.tflite').readAsBytesSync();
    await localModelFile.writeAsBytes(assetBytes);
    expect(localModelFile.existsSync(), isTrue);

    // Dynamic model reload attempt from local file storage
    await GhostAI.instance.reloadModel(modelFile: localModelFile);
    expect(
      GhostAI.instance.modelSource,
      anyOf(equals('local_storage'), equals('fallback_heuristics')),
    );

    final notif = AppNotification(
      id: 'test-2',
      packageName: 'com.finance.app',
      title: 'OTP Code',
      content: 'Your OTP code is 987654. Valid for 5 minutes.',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final res1 = await GhostAI.predict(notif);
    expect(res1.reviewScore, equals(1.0)); // OTP override trigger
    expect(res1.featureVector.length, equals(63));

    // Remove local storage model file
    await localModelFile.delete();
    expect(localModelFile.existsSync(), isFalse);

    // Verify system falls back seamlessly without crashing
    await GhostAI.instance.reloadModel(modelFile: localModelFile);
    expect(
      GhostAI.instance.modelSource,
      anyOf(equals('bundled_asset'), equals('fallback_heuristics')),
    );

    final res2 = await GhostAI.predict(notif);
    expect(res2.reviewScore, equals(1.0));
    expect(res2.featureVector.length, equals(63));
  });
}
