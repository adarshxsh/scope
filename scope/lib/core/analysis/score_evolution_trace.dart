import 'dart:convert';

/// Represents a single stage in the priority score evolution trace.
class ScoreEvolutionStep {
  /// Name of the pipeline stage (e.g., 'NLP Category', 'Rule Engine', 'Score Fusion', 'Override Engine').
  final String stageName;

  /// Intermediate numerical score at this stage (0.0 to 1.0).
  final double score;

  /// Explanation of how the score was calculated or modified at this stage.
  final String description;

  /// Identifier of rule or trigger applied, if any.
  final String? ruleId;

  /// Specific override trigger applied, if any (e.g., 'expired_otp', 'duplicate', 'critical_bypass').
  final String? trigger;

  const ScoreEvolutionStep({
    required this.stageName,
    required this.score,
    required this.description,
    this.ruleId,
    this.trigger,
  });

  Map<String, dynamic> toMap() => {
        'stageName': stageName,
        'score': score,
        'description': description,
        if (ruleId != null) 'ruleId': ruleId,
        if (trigger != null) 'trigger': trigger,
      };

  factory ScoreEvolutionStep.fromMap(Map<String, dynamic> map) {
    final rawScore = (map['score'] as num?)?.toDouble() ?? 0.0;
    final sanitizedScore = rawScore.isFinite ? rawScore.clamp(0.0, 1.0) : 0.0;
    return ScoreEvolutionStep(
      stageName: map['stageName'] as String? ?? 'Stage',
      score: sanitizedScore,
      description: map['description'] as String? ?? '',
      ruleId: map['ruleId'] as String?,
      trigger: map['trigger'] as String?,
    );
  }

  @override
  String toString() =>
      'ScoreEvolutionStep($stageName: ${(score * 100).toStringAsFixed(0)}% - $description)';
}

/// Holds the full end-to-end score evolution trace across classification stages.
class ScoreEvolutionTrace {
  final List<ScoreEvolutionStep> steps;
  final String finalPriority;
  final double finalScore;
  final String? overrideTrigger;

  const ScoreEvolutionTrace({
    required this.steps,
    required this.finalPriority,
    required this.finalScore,
    this.overrideTrigger,
  });

  Map<String, dynamic> toMap() => {
        'steps': steps.map((s) => s.toMap()).toList(),
        'finalPriority': finalPriority,
        'finalScore': finalScore,
        if (overrideTrigger != null) 'overrideTrigger': overrideTrigger,
      };

  String toJson() => jsonEncode(toMap());

  factory ScoreEvolutionTrace.fromMap(Map<String, dynamic> map) {
    final rawFinalScore = (map['finalScore'] as num?)?.toDouble() ?? 0.0;
    final sanitizedFinalScore = rawFinalScore.isFinite ? rawFinalScore.clamp(0.0, 1.0) : 0.0;
    final rawSteps = map['steps'] as List?;
    final stepsList = rawSteps != null
        ? rawSteps
            .whereType<Map>()
            .map((e) => ScoreEvolutionStep.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <ScoreEvolutionStep>[];

    return ScoreEvolutionTrace(
      steps: stepsList,
      finalPriority: map['finalPriority'] as String? ?? 'low',
      finalScore: sanitizedFinalScore,
      overrideTrigger: map['overrideTrigger'] as String?,
    );
  }

  factory ScoreEvolutionTrace.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ScoreEvolutionTrace.fromMap(map);
    } catch (_) {
      return const ScoreEvolutionTrace(
        steps: [],
        finalPriority: 'low',
        finalScore: 0.0,
      );
    }
  }

  @override
  String toString() =>
      'ScoreEvolutionTrace(finalPriority: $finalPriority, finalScore: $finalScore, steps: ${steps.length})';
}
