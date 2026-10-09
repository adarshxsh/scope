import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/telemetry/inference_telemetry_buffer.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';

final telemetryBufferProvider = Provider<InferenceTelemetryBuffer>((ref) {
  return InferenceTelemetryBuffer.instance;
});

final realtimeTelemetryStatsProvider = Provider<TelemetryStats>((ref) {
  ref.watch(telemetryBufferProvider);
  return InferenceTelemetryBuffer.instance.getRealtimeSessionStats();
});

final historicalTelemetryProvider = StreamProvider<List<InferenceTelemetryEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.inferenceTelemetryDao.watchAll();
});
