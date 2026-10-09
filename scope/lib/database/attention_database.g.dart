// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attention_database.dart';

// ignore_for_file: type=lint
class $NotificationsTableTable extends NotificationsTable
    with TableInfo<$NotificationsTableTable, NotificationEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isOngoingMeta =
      const VerificationMeta('isOngoing');
  @override
  late final GeneratedColumn<bool> isOngoing = GeneratedColumn<bool>(
      'is_ongoing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_ongoing" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
      'priority', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _priorityScoreMeta =
      const VerificationMeta('priorityScore');
  @override
  late final GeneratedColumn<double> priorityScore = GeneratedColumn<double>(
      'priority_score', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _classifiedCategoryMeta =
      const VerificationMeta('classifiedCategory');
  @override
  late final GeneratedColumn<String> classifiedCategory =
      GeneratedColumn<String>('classified_category', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _explanationMeta =
      const VerificationMeta('explanation');
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
      'explanation', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _latencyMsMeta =
      const VerificationMeta('latencyMs');
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
      'latency_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _ruleVersionMeta =
      const VerificationMeta('ruleVersion');
  @override
  late final GeneratedColumn<String> ruleVersion = GeneratedColumn<String>(
      'rule_version', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _modelVersionMeta =
      const VerificationMeta('modelVersion');
  @override
  late final GeneratedColumn<String> modelVersion = GeneratedColumn<String>(
      'model_version', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _engineVersionMeta =
      const VerificationMeta('engineVersion');
  @override
  late final GeneratedColumn<String> engineVersion = GeneratedColumn<String>(
      'engine_version', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _extractedFeaturesMeta =
      const VerificationMeta('extractedFeatures');
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
      extractedFeatures = GeneratedColumn<String>(
              'extracted_features', aliasedName, true,
              type: DriftSqlType.string, requiredDuringInsert: false)
          .withConverter<Map<String, dynamic>?>(
              $NotificationsTableTable.$converterextractedFeaturesn);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumnWithTypeConverter<ReviewState, String> state =
      GeneratedColumn<String>('state', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ReviewState>($NotificationsTableTable.$converterstate);
  static const VerificationMeta _snoozedUntilMeta =
      const VerificationMeta('snoozedUntil');
  @override
  late final GeneratedColumn<DateTime> snoozedUntil = GeneratedColumn<DateTime>(
      'snoozed_until', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastUpdatedMeta =
      const VerificationMeta('lastUpdated');
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'last_updated', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _policyScoreMeta =
      const VerificationMeta('policyScore');
  @override
  late final GeneratedColumn<double> policyScore = GeneratedColumn<double>(
      'policy_score', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _finalScoreMeta =
      const VerificationMeta('finalScore');
  @override
  late final GeneratedColumn<double> finalScore = GeneratedColumn<double>(
      'final_score', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _reviewedMeta =
      const VerificationMeta('reviewed');
  @override
  late final GeneratedColumn<bool> reviewed = GeneratedColumn<bool>(
      'reviewed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("reviewed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _dismissedMeta =
      const VerificationMeta('dismissed');
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
      'dismissed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("dismissed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        packageName,
        title,
        content,
        timestamp,
        category,
        isOngoing,
        priority,
        priorityScore,
        classifiedCategory,
        explanation,
        latencyMs,
        ruleVersion,
        modelVersion,
        engineVersion,
        extractedFeatures,
        state,
        snoozedUntil,
        lastUpdated,
        policyScore,
        finalScore,
        reviewed,
        dismissed,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications_table';
  @override
  VerificationContext validateIntegrity(Insertable<NotificationEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('is_ongoing')) {
      context.handle(_isOngoingMeta,
          isOngoing.isAcceptableOrUnknown(data['is_ongoing']!, _isOngoingMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('priority_score')) {
      context.handle(
          _priorityScoreMeta,
          priorityScore.isAcceptableOrUnknown(
              data['priority_score']!, _priorityScoreMeta));
    }
    if (data.containsKey('classified_category')) {
      context.handle(
          _classifiedCategoryMeta,
          classifiedCategory.isAcceptableOrUnknown(
              data['classified_category']!, _classifiedCategoryMeta));
    }
    if (data.containsKey('explanation')) {
      context.handle(
          _explanationMeta,
          explanation.isAcceptableOrUnknown(
              data['explanation']!, _explanationMeta));
    }
    if (data.containsKey('latency_ms')) {
      context.handle(_latencyMsMeta,
          latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta));
    }
    if (data.containsKey('rule_version')) {
      context.handle(
          _ruleVersionMeta,
          ruleVersion.isAcceptableOrUnknown(
              data['rule_version']!, _ruleVersionMeta));
    }
    if (data.containsKey('model_version')) {
      context.handle(
          _modelVersionMeta,
          modelVersion.isAcceptableOrUnknown(
              data['model_version']!, _modelVersionMeta));
    }
    if (data.containsKey('engine_version')) {
      context.handle(
          _engineVersionMeta,
          engineVersion.isAcceptableOrUnknown(
              data['engine_version']!, _engineVersionMeta));
    }
    context.handle(_extractedFeaturesMeta, const VerificationResult.success());
    context.handle(_stateMeta, const VerificationResult.success());
    if (data.containsKey('snoozed_until')) {
      context.handle(
          _snoozedUntilMeta,
          snoozedUntil.isAcceptableOrUnknown(
              data['snoozed_until']!, _snoozedUntilMeta));
    }
    if (data.containsKey('last_updated')) {
      context.handle(
          _lastUpdatedMeta,
          lastUpdated.isAcceptableOrUnknown(
              data['last_updated']!, _lastUpdatedMeta));
    }
    if (data.containsKey('policy_score')) {
      context.handle(
          _policyScoreMeta,
          policyScore.isAcceptableOrUnknown(
              data['policy_score']!, _policyScoreMeta));
    }
    if (data.containsKey('final_score')) {
      context.handle(
          _finalScoreMeta,
          finalScore.isAcceptableOrUnknown(
              data['final_score']!, _finalScoreMeta));
    }
    if (data.containsKey('reviewed')) {
      context.handle(_reviewedMeta,
          reviewed.isAcceptableOrUnknown(data['reviewed']!, _reviewedMeta));
    }
    if (data.containsKey('dismissed')) {
      context.handle(_dismissedMeta,
          dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category']),
      isOngoing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_ongoing'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}priority']),
      priorityScore: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}priority_score']),
      classifiedCategory: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}classified_category']),
      explanation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}explanation']),
      latencyMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}latency_ms']),
      ruleVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rule_version']),
      modelVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model_version']),
      engineVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}engine_version']),
      extractedFeatures: $NotificationsTableTable.$converterextractedFeaturesn
          .fromSql(attachedDatabase.typeMapping.read(DriftSqlType.string,
              data['${effectivePrefix}extracted_features'])),
      state: $NotificationsTableTable.$converterstate.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!),
      snoozedUntil: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}snoozed_until']),
      lastUpdated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_updated']),
      policyScore: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}policy_score']),
      finalScore: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}final_score']),
      reviewed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}reviewed'])!,
      dismissed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}dismissed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $NotificationsTableTable createAlias(String alias) {
    return $NotificationsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String>
      $converterextractedFeatures = const JsonConverter();
  static TypeConverter<Map<String, dynamic>?, String?>
      $converterextractedFeaturesn =
      NullAwareTypeConverter.wrap($converterextractedFeatures);
  static JsonTypeConverter2<ReviewState, String, String> $converterstate =
      const EnumNameConverter<ReviewState>(ReviewState.values);
}

class NotificationEntry extends DataClass
    implements Insertable<NotificationEntry> {
  final String id;
  final String packageName;
  final String title;
  final String content;
  final int timestamp;
  final String? category;
  final bool isOngoing;
  final String? priority;
  final double? priorityScore;
  final String? classifiedCategory;
  final String? explanation;
  final int? latencyMs;
  final String? ruleVersion;
  final String? modelVersion;
  final String? engineVersion;
  final Map<String, dynamic>? extractedFeatures;
  final ReviewState state;
  final DateTime? snoozedUntil;
  final DateTime? lastUpdated;
  final double? policyScore;
  final double? finalScore;
  final bool reviewed;
  final bool dismissed;
  final DateTime createdAt;
  const NotificationEntry(
      {required this.id,
      required this.packageName,
      required this.title,
      required this.content,
      required this.timestamp,
      this.category,
      required this.isOngoing,
      this.priority,
      this.priorityScore,
      this.classifiedCategory,
      this.explanation,
      this.latencyMs,
      this.ruleVersion,
      this.modelVersion,
      this.engineVersion,
      this.extractedFeatures,
      required this.state,
      this.snoozedUntil,
      this.lastUpdated,
      this.policyScore,
      this.finalScore,
      required this.reviewed,
      required this.dismissed,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['package_name'] = Variable<String>(packageName);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['timestamp'] = Variable<int>(timestamp);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['is_ongoing'] = Variable<bool>(isOngoing);
    if (!nullToAbsent || priority != null) {
      map['priority'] = Variable<String>(priority);
    }
    if (!nullToAbsent || priorityScore != null) {
      map['priority_score'] = Variable<double>(priorityScore);
    }
    if (!nullToAbsent || classifiedCategory != null) {
      map['classified_category'] = Variable<String>(classifiedCategory);
    }
    if (!nullToAbsent || explanation != null) {
      map['explanation'] = Variable<String>(explanation);
    }
    if (!nullToAbsent || latencyMs != null) {
      map['latency_ms'] = Variable<int>(latencyMs);
    }
    if (!nullToAbsent || ruleVersion != null) {
      map['rule_version'] = Variable<String>(ruleVersion);
    }
    if (!nullToAbsent || modelVersion != null) {
      map['model_version'] = Variable<String>(modelVersion);
    }
    if (!nullToAbsent || engineVersion != null) {
      map['engine_version'] = Variable<String>(engineVersion);
    }
    if (!nullToAbsent || extractedFeatures != null) {
      map['extracted_features'] = Variable<String>($NotificationsTableTable
          .$converterextractedFeaturesn
          .toSql(extractedFeatures));
    }
    {
      map['state'] = Variable<String>(
          $NotificationsTableTable.$converterstate.toSql(state));
    }
    if (!nullToAbsent || snoozedUntil != null) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil);
    }
    if (!nullToAbsent || lastUpdated != null) {
      map['last_updated'] = Variable<DateTime>(lastUpdated);
    }
    if (!nullToAbsent || policyScore != null) {
      map['policy_score'] = Variable<double>(policyScore);
    }
    if (!nullToAbsent || finalScore != null) {
      map['final_score'] = Variable<double>(finalScore);
    }
    map['reviewed'] = Variable<bool>(reviewed);
    map['dismissed'] = Variable<bool>(dismissed);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NotificationsTableCompanion toCompanion(bool nullToAbsent) {
    return NotificationsTableCompanion(
      id: Value(id),
      packageName: Value(packageName),
      title: Value(title),
      content: Value(content),
      timestamp: Value(timestamp),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      isOngoing: Value(isOngoing),
      priority: priority == null && nullToAbsent
          ? const Value.absent()
          : Value(priority),
      priorityScore: priorityScore == null && nullToAbsent
          ? const Value.absent()
          : Value(priorityScore),
      classifiedCategory: classifiedCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(classifiedCategory),
      explanation: explanation == null && nullToAbsent
          ? const Value.absent()
          : Value(explanation),
      latencyMs: latencyMs == null && nullToAbsent
          ? const Value.absent()
          : Value(latencyMs),
      ruleVersion: ruleVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(ruleVersion),
      modelVersion: modelVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(modelVersion),
      engineVersion: engineVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(engineVersion),
      extractedFeatures: extractedFeatures == null && nullToAbsent
          ? const Value.absent()
          : Value(extractedFeatures),
      state: Value(state),
      snoozedUntil: snoozedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(snoozedUntil),
      lastUpdated: lastUpdated == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdated),
      policyScore: policyScore == null && nullToAbsent
          ? const Value.absent()
          : Value(policyScore),
      finalScore: finalScore == null && nullToAbsent
          ? const Value.absent()
          : Value(finalScore),
      reviewed: Value(reviewed),
      dismissed: Value(dismissed),
      createdAt: Value(createdAt),
    );
  }

  factory NotificationEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationEntry(
      id: serializer.fromJson<String>(json['id']),
      packageName: serializer.fromJson<String>(json['packageName']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      category: serializer.fromJson<String?>(json['category']),
      isOngoing: serializer.fromJson<bool>(json['isOngoing']),
      priority: serializer.fromJson<String?>(json['priority']),
      priorityScore: serializer.fromJson<double?>(json['priorityScore']),
      classifiedCategory:
          serializer.fromJson<String?>(json['classifiedCategory']),
      explanation: serializer.fromJson<String?>(json['explanation']),
      latencyMs: serializer.fromJson<int?>(json['latencyMs']),
      ruleVersion: serializer.fromJson<String?>(json['ruleVersion']),
      modelVersion: serializer.fromJson<String?>(json['modelVersion']),
      engineVersion: serializer.fromJson<String?>(json['engineVersion']),
      extractedFeatures:
          serializer.fromJson<Map<String, dynamic>?>(json['extractedFeatures']),
      state: $NotificationsTableTable.$converterstate
          .fromJson(serializer.fromJson<String>(json['state'])),
      snoozedUntil: serializer.fromJson<DateTime?>(json['snoozedUntil']),
      lastUpdated: serializer.fromJson<DateTime?>(json['lastUpdated']),
      policyScore: serializer.fromJson<double?>(json['policyScore']),
      finalScore: serializer.fromJson<double?>(json['finalScore']),
      reviewed: serializer.fromJson<bool>(json['reviewed']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'packageName': serializer.toJson<String>(packageName),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'timestamp': serializer.toJson<int>(timestamp),
      'category': serializer.toJson<String?>(category),
      'isOngoing': serializer.toJson<bool>(isOngoing),
      'priority': serializer.toJson<String?>(priority),
      'priorityScore': serializer.toJson<double?>(priorityScore),
      'classifiedCategory': serializer.toJson<String?>(classifiedCategory),
      'explanation': serializer.toJson<String?>(explanation),
      'latencyMs': serializer.toJson<int?>(latencyMs),
      'ruleVersion': serializer.toJson<String?>(ruleVersion),
      'modelVersion': serializer.toJson<String?>(modelVersion),
      'engineVersion': serializer.toJson<String?>(engineVersion),
      'extractedFeatures':
          serializer.toJson<Map<String, dynamic>?>(extractedFeatures),
      'state': serializer.toJson<String>(
          $NotificationsTableTable.$converterstate.toJson(state)),
      'snoozedUntil': serializer.toJson<DateTime?>(snoozedUntil),
      'lastUpdated': serializer.toJson<DateTime?>(lastUpdated),
      'policyScore': serializer.toJson<double?>(policyScore),
      'finalScore': serializer.toJson<double?>(finalScore),
      'reviewed': serializer.toJson<bool>(reviewed),
      'dismissed': serializer.toJson<bool>(dismissed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NotificationEntry copyWith(
          {String? id,
          String? packageName,
          String? title,
          String? content,
          int? timestamp,
          Value<String?> category = const Value.absent(),
          bool? isOngoing,
          Value<String?> priority = const Value.absent(),
          Value<double?> priorityScore = const Value.absent(),
          Value<String?> classifiedCategory = const Value.absent(),
          Value<String?> explanation = const Value.absent(),
          Value<int?> latencyMs = const Value.absent(),
          Value<String?> ruleVersion = const Value.absent(),
          Value<String?> modelVersion = const Value.absent(),
          Value<String?> engineVersion = const Value.absent(),
          Value<Map<String, dynamic>?> extractedFeatures = const Value.absent(),
          ReviewState? state,
          Value<DateTime?> snoozedUntil = const Value.absent(),
          Value<DateTime?> lastUpdated = const Value.absent(),
          Value<double?> policyScore = const Value.absent(),
          Value<double?> finalScore = const Value.absent(),
          bool? reviewed,
          bool? dismissed,
          DateTime? createdAt}) =>
      NotificationEntry(
        id: id ?? this.id,
        packageName: packageName ?? this.packageName,
        title: title ?? this.title,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
        category: category.present ? category.value : this.category,
        isOngoing: isOngoing ?? this.isOngoing,
        priority: priority.present ? priority.value : this.priority,
        priorityScore:
            priorityScore.present ? priorityScore.value : this.priorityScore,
        classifiedCategory: classifiedCategory.present
            ? classifiedCategory.value
            : this.classifiedCategory,
        explanation: explanation.present ? explanation.value : this.explanation,
        latencyMs: latencyMs.present ? latencyMs.value : this.latencyMs,
        ruleVersion: ruleVersion.present ? ruleVersion.value : this.ruleVersion,
        modelVersion:
            modelVersion.present ? modelVersion.value : this.modelVersion,
        engineVersion:
            engineVersion.present ? engineVersion.value : this.engineVersion,
        extractedFeatures: extractedFeatures.present
            ? extractedFeatures.value
            : this.extractedFeatures,
        state: state ?? this.state,
        snoozedUntil:
            snoozedUntil.present ? snoozedUntil.value : this.snoozedUntil,
        lastUpdated: lastUpdated.present ? lastUpdated.value : this.lastUpdated,
        policyScore: policyScore.present ? policyScore.value : this.policyScore,
        finalScore: finalScore.present ? finalScore.value : this.finalScore,
        reviewed: reviewed ?? this.reviewed,
        dismissed: dismissed ?? this.dismissed,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('NotificationEntry(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('category: $category, ')
          ..write('isOngoing: $isOngoing, ')
          ..write('priority: $priority, ')
          ..write('priorityScore: $priorityScore, ')
          ..write('classifiedCategory: $classifiedCategory, ')
          ..write('explanation: $explanation, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('ruleVersion: $ruleVersion, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('engineVersion: $engineVersion, ')
          ..write('extractedFeatures: $extractedFeatures, ')
          ..write('state: $state, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('policyScore: $policyScore, ')
          ..write('finalScore: $finalScore, ')
          ..write('reviewed: $reviewed, ')
          ..write('dismissed: $dismissed, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        packageName,
        title,
        content,
        timestamp,
        category,
        isOngoing,
        priority,
        priorityScore,
        classifiedCategory,
        explanation,
        latencyMs,
        ruleVersion,
        modelVersion,
        engineVersion,
        extractedFeatures,
        state,
        snoozedUntil,
        lastUpdated,
        policyScore,
        finalScore,
        reviewed,
        dismissed,
        createdAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationEntry &&
          other.id == this.id &&
          other.packageName == this.packageName &&
          other.title == this.title &&
          other.content == this.content &&
          other.timestamp == this.timestamp &&
          other.category == this.category &&
          other.isOngoing == this.isOngoing &&
          other.priority == this.priority &&
          other.priorityScore == this.priorityScore &&
          other.classifiedCategory == this.classifiedCategory &&
          other.explanation == this.explanation &&
          other.latencyMs == this.latencyMs &&
          other.ruleVersion == this.ruleVersion &&
          other.modelVersion == this.modelVersion &&
          other.engineVersion == this.engineVersion &&
          other.extractedFeatures == this.extractedFeatures &&
          other.state == this.state &&
          other.snoozedUntil == this.snoozedUntil &&
          other.lastUpdated == this.lastUpdated &&
          other.policyScore == this.policyScore &&
          other.finalScore == this.finalScore &&
          other.reviewed == this.reviewed &&
          other.dismissed == this.dismissed &&
          other.createdAt == this.createdAt);
}

class NotificationsTableCompanion extends UpdateCompanion<NotificationEntry> {
  final Value<String> id;
  final Value<String> packageName;
  final Value<String> title;
  final Value<String> content;
  final Value<int> timestamp;
  final Value<String?> category;
  final Value<bool> isOngoing;
  final Value<String?> priority;
  final Value<double?> priorityScore;
  final Value<String?> classifiedCategory;
  final Value<String?> explanation;
  final Value<int?> latencyMs;
  final Value<String?> ruleVersion;
  final Value<String?> modelVersion;
  final Value<String?> engineVersion;
  final Value<Map<String, dynamic>?> extractedFeatures;
  final Value<ReviewState> state;
  final Value<DateTime?> snoozedUntil;
  final Value<DateTime?> lastUpdated;
  final Value<double?> policyScore;
  final Value<double?> finalScore;
  final Value<bool> reviewed;
  final Value<bool> dismissed;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const NotificationsTableCompanion({
    this.id = const Value.absent(),
    this.packageName = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.category = const Value.absent(),
    this.isOngoing = const Value.absent(),
    this.priority = const Value.absent(),
    this.priorityScore = const Value.absent(),
    this.classifiedCategory = const Value.absent(),
    this.explanation = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.ruleVersion = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.engineVersion = const Value.absent(),
    this.extractedFeatures = const Value.absent(),
    this.state = const Value.absent(),
    this.snoozedUntil = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.policyScore = const Value.absent(),
    this.finalScore = const Value.absent(),
    this.reviewed = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationsTableCompanion.insert({
    required String id,
    required String packageName,
    required String title,
    required String content,
    required int timestamp,
    this.category = const Value.absent(),
    this.isOngoing = const Value.absent(),
    this.priority = const Value.absent(),
    this.priorityScore = const Value.absent(),
    this.classifiedCategory = const Value.absent(),
    this.explanation = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.ruleVersion = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.engineVersion = const Value.absent(),
    this.extractedFeatures = const Value.absent(),
    required ReviewState state,
    this.snoozedUntil = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.policyScore = const Value.absent(),
    this.finalScore = const Value.absent(),
    this.reviewed = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        packageName = Value(packageName),
        title = Value(title),
        content = Value(content),
        timestamp = Value(timestamp),
        state = Value(state);
  static Insertable<NotificationEntry> custom({
    Expression<String>? id,
    Expression<String>? packageName,
    Expression<String>? title,
    Expression<String>? content,
    Expression<int>? timestamp,
    Expression<String>? category,
    Expression<bool>? isOngoing,
    Expression<String>? priority,
    Expression<double>? priorityScore,
    Expression<String>? classifiedCategory,
    Expression<String>? explanation,
    Expression<int>? latencyMs,
    Expression<String>? ruleVersion,
    Expression<String>? modelVersion,
    Expression<String>? engineVersion,
    Expression<String>? extractedFeatures,
    Expression<String>? state,
    Expression<DateTime>? snoozedUntil,
    Expression<DateTime>? lastUpdated,
    Expression<double>? policyScore,
    Expression<double>? finalScore,
    Expression<bool>? reviewed,
    Expression<bool>? dismissed,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (packageName != null) 'package_name': packageName,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (timestamp != null) 'timestamp': timestamp,
      if (category != null) 'category': category,
      if (isOngoing != null) 'is_ongoing': isOngoing,
      if (priority != null) 'priority': priority,
      if (priorityScore != null) 'priority_score': priorityScore,
      if (classifiedCategory != null) 'classified_category': classifiedCategory,
      if (explanation != null) 'explanation': explanation,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (ruleVersion != null) 'rule_version': ruleVersion,
      if (modelVersion != null) 'model_version': modelVersion,
      if (engineVersion != null) 'engine_version': engineVersion,
      if (extractedFeatures != null) 'extracted_features': extractedFeatures,
      if (state != null) 'state': state,
      if (snoozedUntil != null) 'snoozed_until': snoozedUntil,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (policyScore != null) 'policy_score': policyScore,
      if (finalScore != null) 'final_score': finalScore,
      if (reviewed != null) 'reviewed': reviewed,
      if (dismissed != null) 'dismissed': dismissed,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? packageName,
      Value<String>? title,
      Value<String>? content,
      Value<int>? timestamp,
      Value<String?>? category,
      Value<bool>? isOngoing,
      Value<String?>? priority,
      Value<double?>? priorityScore,
      Value<String?>? classifiedCategory,
      Value<String?>? explanation,
      Value<int?>? latencyMs,
      Value<String?>? ruleVersion,
      Value<String?>? modelVersion,
      Value<String?>? engineVersion,
      Value<Map<String, dynamic>?>? extractedFeatures,
      Value<ReviewState>? state,
      Value<DateTime?>? snoozedUntil,
      Value<DateTime?>? lastUpdated,
      Value<double?>? policyScore,
      Value<double?>? finalScore,
      Value<bool>? reviewed,
      Value<bool>? dismissed,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return NotificationsTableCompanion(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      title: title ?? this.title,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      isOngoing: isOngoing ?? this.isOngoing,
      priority: priority ?? this.priority,
      priorityScore: priorityScore ?? this.priorityScore,
      classifiedCategory: classifiedCategory ?? this.classifiedCategory,
      explanation: explanation ?? this.explanation,
      latencyMs: latencyMs ?? this.latencyMs,
      ruleVersion: ruleVersion ?? this.ruleVersion,
      modelVersion: modelVersion ?? this.modelVersion,
      engineVersion: engineVersion ?? this.engineVersion,
      extractedFeatures: extractedFeatures ?? this.extractedFeatures,
      state: state ?? this.state,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      policyScore: policyScore ?? this.policyScore,
      finalScore: finalScore ?? this.finalScore,
      reviewed: reviewed ?? this.reviewed,
      dismissed: dismissed ?? this.dismissed,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (isOngoing.present) {
      map['is_ongoing'] = Variable<bool>(isOngoing.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (priorityScore.present) {
      map['priority_score'] = Variable<double>(priorityScore.value);
    }
    if (classifiedCategory.present) {
      map['classified_category'] = Variable<String>(classifiedCategory.value);
    }
    if (explanation.present) {
      map['explanation'] = Variable<String>(explanation.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (ruleVersion.present) {
      map['rule_version'] = Variable<String>(ruleVersion.value);
    }
    if (modelVersion.present) {
      map['model_version'] = Variable<String>(modelVersion.value);
    }
    if (engineVersion.present) {
      map['engine_version'] = Variable<String>(engineVersion.value);
    }
    if (extractedFeatures.present) {
      map['extracted_features'] = Variable<String>($NotificationsTableTable
          .$converterextractedFeaturesn
          .toSql(extractedFeatures.value));
    }
    if (state.present) {
      map['state'] = Variable<String>(
          $NotificationsTableTable.$converterstate.toSql(state.value));
    }
    if (snoozedUntil.present) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (policyScore.present) {
      map['policy_score'] = Variable<double>(policyScore.value);
    }
    if (finalScore.present) {
      map['final_score'] = Variable<double>(finalScore.value);
    }
    if (reviewed.present) {
      map['reviewed'] = Variable<bool>(reviewed.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationsTableCompanion(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('category: $category, ')
          ..write('isOngoing: $isOngoing, ')
          ..write('priority: $priority, ')
          ..write('priorityScore: $priorityScore, ')
          ..write('classifiedCategory: $classifiedCategory, ')
          ..write('explanation: $explanation, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('ruleVersion: $ruleVersion, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('engineVersion: $engineVersion, ')
          ..write('extractedFeatures: $extractedFeatures, ')
          ..write('state: $state, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('policyScore: $policyScore, ')
          ..write('finalScore: $finalScore, ')
          ..write('reviewed: $reviewed, ')
          ..write('dismissed: $dismissed, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewQueueTableTable extends ReviewQueueTable
    with TableInfo<$ReviewQueueTableTable, ReviewQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewQueueTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _notificationIdMeta =
      const VerificationMeta('notificationId');
  @override
  late final GeneratedColumn<String> notificationId = GeneratedColumn<String>(
      'notification_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES notifications_table (id)'));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
      'priority', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enqueueTimeMeta =
      const VerificationMeta('enqueueTime');
  @override
  late final GeneratedColumn<DateTime> enqueueTime = GeneratedColumn<DateTime>(
      'enqueue_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _expiryTimeMeta =
      const VerificationMeta('expiryTime');
  @override
  late final GeneratedColumn<DateTime> expiryTime = GeneratedColumn<DateTime>(
      'expiry_time', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumnWithTypeConverter<ReviewState, String> status =
      GeneratedColumn<String>('status', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ReviewState>($ReviewQueueTableTable.$converterstatus);
  @override
  List<GeneratedColumn> get $columns =>
      [id, notificationId, priority, enqueueTime, expiryTime, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_queue_table';
  @override
  VerificationContext validateIntegrity(Insertable<ReviewQueueEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('notification_id')) {
      context.handle(
          _notificationIdMeta,
          notificationId.isAcceptableOrUnknown(
              data['notification_id']!, _notificationIdMeta));
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('enqueue_time')) {
      context.handle(
          _enqueueTimeMeta,
          enqueueTime.isAcceptableOrUnknown(
              data['enqueue_time']!, _enqueueTimeMeta));
    } else if (isInserting) {
      context.missing(_enqueueTimeMeta);
    }
    if (data.containsKey('expiry_time')) {
      context.handle(
          _expiryTimeMeta,
          expiryTime.isAcceptableOrUnknown(
              data['expiry_time']!, _expiryTimeMeta));
    }
    context.handle(_statusMeta, const VerificationResult.success());
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewQueueEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      notificationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}notification_id'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}priority'])!,
      enqueueTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}enqueue_time'])!,
      expiryTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}expiry_time']),
      status: $ReviewQueueTableTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!),
    );
  }

  @override
  $ReviewQueueTableTable createAlias(String alias) {
    return $ReviewQueueTableTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ReviewState, String, String> $converterstatus =
      const EnumNameConverter<ReviewState>(ReviewState.values);
}

class ReviewQueueEntry extends DataClass
    implements Insertable<ReviewQueueEntry> {
  final int id;
  final String notificationId;
  final String priority;
  final DateTime enqueueTime;
  final DateTime? expiryTime;
  final ReviewState status;
  const ReviewQueueEntry(
      {required this.id,
      required this.notificationId,
      required this.priority,
      required this.enqueueTime,
      this.expiryTime,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['notification_id'] = Variable<String>(notificationId);
    map['priority'] = Variable<String>(priority);
    map['enqueue_time'] = Variable<DateTime>(enqueueTime);
    if (!nullToAbsent || expiryTime != null) {
      map['expiry_time'] = Variable<DateTime>(expiryTime);
    }
    {
      map['status'] = Variable<String>(
          $ReviewQueueTableTable.$converterstatus.toSql(status));
    }
    return map;
  }

  ReviewQueueTableCompanion toCompanion(bool nullToAbsent) {
    return ReviewQueueTableCompanion(
      id: Value(id),
      notificationId: Value(notificationId),
      priority: Value(priority),
      enqueueTime: Value(enqueueTime),
      expiryTime: expiryTime == null && nullToAbsent
          ? const Value.absent()
          : Value(expiryTime),
      status: Value(status),
    );
  }

  factory ReviewQueueEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewQueueEntry(
      id: serializer.fromJson<int>(json['id']),
      notificationId: serializer.fromJson<String>(json['notificationId']),
      priority: serializer.fromJson<String>(json['priority']),
      enqueueTime: serializer.fromJson<DateTime>(json['enqueueTime']),
      expiryTime: serializer.fromJson<DateTime?>(json['expiryTime']),
      status: $ReviewQueueTableTable.$converterstatus
          .fromJson(serializer.fromJson<String>(json['status'])),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'notificationId': serializer.toJson<String>(notificationId),
      'priority': serializer.toJson<String>(priority),
      'enqueueTime': serializer.toJson<DateTime>(enqueueTime),
      'expiryTime': serializer.toJson<DateTime?>(expiryTime),
      'status': serializer.toJson<String>(
          $ReviewQueueTableTable.$converterstatus.toJson(status)),
    };
  }

  ReviewQueueEntry copyWith(
          {int? id,
          String? notificationId,
          String? priority,
          DateTime? enqueueTime,
          Value<DateTime?> expiryTime = const Value.absent(),
          ReviewState? status}) =>
      ReviewQueueEntry(
        id: id ?? this.id,
        notificationId: notificationId ?? this.notificationId,
        priority: priority ?? this.priority,
        enqueueTime: enqueueTime ?? this.enqueueTime,
        expiryTime: expiryTime.present ? expiryTime.value : this.expiryTime,
        status: status ?? this.status,
      );
  @override
  String toString() {
    return (StringBuffer('ReviewQueueEntry(')
          ..write('id: $id, ')
          ..write('notificationId: $notificationId, ')
          ..write('priority: $priority, ')
          ..write('enqueueTime: $enqueueTime, ')
          ..write('expiryTime: $expiryTime, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, notificationId, priority, enqueueTime, expiryTime, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewQueueEntry &&
          other.id == this.id &&
          other.notificationId == this.notificationId &&
          other.priority == this.priority &&
          other.enqueueTime == this.enqueueTime &&
          other.expiryTime == this.expiryTime &&
          other.status == this.status);
}

class ReviewQueueTableCompanion extends UpdateCompanion<ReviewQueueEntry> {
  final Value<int> id;
  final Value<String> notificationId;
  final Value<String> priority;
  final Value<DateTime> enqueueTime;
  final Value<DateTime?> expiryTime;
  final Value<ReviewState> status;
  const ReviewQueueTableCompanion({
    this.id = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.priority = const Value.absent(),
    this.enqueueTime = const Value.absent(),
    this.expiryTime = const Value.absent(),
    this.status = const Value.absent(),
  });
  ReviewQueueTableCompanion.insert({
    this.id = const Value.absent(),
    required String notificationId,
    required String priority,
    required DateTime enqueueTime,
    this.expiryTime = const Value.absent(),
    required ReviewState status,
  })  : notificationId = Value(notificationId),
        priority = Value(priority),
        enqueueTime = Value(enqueueTime),
        status = Value(status);
  static Insertable<ReviewQueueEntry> custom({
    Expression<int>? id,
    Expression<String>? notificationId,
    Expression<String>? priority,
    Expression<DateTime>? enqueueTime,
    Expression<DateTime>? expiryTime,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notificationId != null) 'notification_id': notificationId,
      if (priority != null) 'priority': priority,
      if (enqueueTime != null) 'enqueue_time': enqueueTime,
      if (expiryTime != null) 'expiry_time': expiryTime,
      if (status != null) 'status': status,
    });
  }

  ReviewQueueTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? notificationId,
      Value<String>? priority,
      Value<DateTime>? enqueueTime,
      Value<DateTime?>? expiryTime,
      Value<ReviewState>? status}) {
    return ReviewQueueTableCompanion(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      priority: priority ?? this.priority,
      enqueueTime: enqueueTime ?? this.enqueueTime,
      expiryTime: expiryTime ?? this.expiryTime,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<String>(notificationId.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (enqueueTime.present) {
      map['enqueue_time'] = Variable<DateTime>(enqueueTime.value);
    }
    if (expiryTime.present) {
      map['expiry_time'] = Variable<DateTime>(expiryTime.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
          $ReviewQueueTableTable.$converterstatus.toSql(status.value));
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewQueueTableCompanion(')
          ..write('id: $id, ')
          ..write('notificationId: $notificationId, ')
          ..write('priority: $priority, ')
          ..write('enqueueTime: $enqueueTime, ')
          ..write('expiryTime: $expiryTime, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $FocusSessionsTableTable extends FocusSessionsTable
    with TableInfo<$FocusSessionsTableTable, FocusSessionEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sessionStartMeta =
      const VerificationMeta('sessionStart');
  @override
  late final GeneratedColumn<DateTime> sessionStart = GeneratedColumn<DateTime>(
      'session_start', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sessionEndMeta =
      const VerificationMeta('sessionEnd');
  @override
  late final GeneratedColumn<DateTime> sessionEnd = GeneratedColumn<DateTime>(
      'session_end', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _interruptionsMeta =
      const VerificationMeta('interruptions');
  @override
  late final GeneratedColumn<int> interruptions = GeneratedColumn<int>(
      'interruptions', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _completionMeta =
      const VerificationMeta('completion');
  @override
  late final GeneratedColumn<bool> completion = GeneratedColumn<bool>(
      'completion', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completion" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _durationMeta =
      const VerificationMeta('duration');
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
      'duration', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sessionStart, sessionEnd, interruptions, completion, duration];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions_table';
  @override
  VerificationContext validateIntegrity(Insertable<FocusSessionEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_start')) {
      context.handle(
          _sessionStartMeta,
          sessionStart.isAcceptableOrUnknown(
              data['session_start']!, _sessionStartMeta));
    } else if (isInserting) {
      context.missing(_sessionStartMeta);
    }
    if (data.containsKey('session_end')) {
      context.handle(
          _sessionEndMeta,
          sessionEnd.isAcceptableOrUnknown(
              data['session_end']!, _sessionEndMeta));
    }
    if (data.containsKey('interruptions')) {
      context.handle(
          _interruptionsMeta,
          interruptions.isAcceptableOrUnknown(
              data['interruptions']!, _interruptionsMeta));
    }
    if (data.containsKey('completion')) {
      context.handle(
          _completionMeta,
          completion.isAcceptableOrUnknown(
              data['completion']!, _completionMeta));
    }
    if (data.containsKey('duration')) {
      context.handle(_durationMeta,
          duration.isAcceptableOrUnknown(data['duration']!, _durationMeta));
    } else if (isInserting) {
      context.missing(_durationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FocusSessionEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSessionEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sessionStart: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}session_start'])!,
      sessionEnd: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}session_end']),
      interruptions: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}interruptions'])!,
      completion: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completion'])!,
      duration: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration'])!,
    );
  }

  @override
  $FocusSessionsTableTable createAlias(String alias) {
    return $FocusSessionsTableTable(attachedDatabase, alias);
  }
}

class FocusSessionEntry extends DataClass
    implements Insertable<FocusSessionEntry> {
  final int id;
  final DateTime sessionStart;
  final DateTime? sessionEnd;
  final int interruptions;
  final bool completion;
  final int duration;
  const FocusSessionEntry(
      {required this.id,
      required this.sessionStart,
      this.sessionEnd,
      required this.interruptions,
      required this.completion,
      required this.duration});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_start'] = Variable<DateTime>(sessionStart);
    if (!nullToAbsent || sessionEnd != null) {
      map['session_end'] = Variable<DateTime>(sessionEnd);
    }
    map['interruptions'] = Variable<int>(interruptions);
    map['completion'] = Variable<bool>(completion);
    map['duration'] = Variable<int>(duration);
    return map;
  }

  FocusSessionsTableCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsTableCompanion(
      id: Value(id),
      sessionStart: Value(sessionStart),
      sessionEnd: sessionEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionEnd),
      interruptions: Value(interruptions),
      completion: Value(completion),
      duration: Value(duration),
    );
  }

  factory FocusSessionEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSessionEntry(
      id: serializer.fromJson<int>(json['id']),
      sessionStart: serializer.fromJson<DateTime>(json['sessionStart']),
      sessionEnd: serializer.fromJson<DateTime?>(json['sessionEnd']),
      interruptions: serializer.fromJson<int>(json['interruptions']),
      completion: serializer.fromJson<bool>(json['completion']),
      duration: serializer.fromJson<int>(json['duration']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionStart': serializer.toJson<DateTime>(sessionStart),
      'sessionEnd': serializer.toJson<DateTime?>(sessionEnd),
      'interruptions': serializer.toJson<int>(interruptions),
      'completion': serializer.toJson<bool>(completion),
      'duration': serializer.toJson<int>(duration),
    };
  }

  FocusSessionEntry copyWith(
          {int? id,
          DateTime? sessionStart,
          Value<DateTime?> sessionEnd = const Value.absent(),
          int? interruptions,
          bool? completion,
          int? duration}) =>
      FocusSessionEntry(
        id: id ?? this.id,
        sessionStart: sessionStart ?? this.sessionStart,
        sessionEnd: sessionEnd.present ? sessionEnd.value : this.sessionEnd,
        interruptions: interruptions ?? this.interruptions,
        completion: completion ?? this.completion,
        duration: duration ?? this.duration,
      );
  @override
  String toString() {
    return (StringBuffer('FocusSessionEntry(')
          ..write('id: $id, ')
          ..write('sessionStart: $sessionStart, ')
          ..write('sessionEnd: $sessionEnd, ')
          ..write('interruptions: $interruptions, ')
          ..write('completion: $completion, ')
          ..write('duration: $duration')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sessionStart, sessionEnd, interruptions, completion, duration);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSessionEntry &&
          other.id == this.id &&
          other.sessionStart == this.sessionStart &&
          other.sessionEnd == this.sessionEnd &&
          other.interruptions == this.interruptions &&
          other.completion == this.completion &&
          other.duration == this.duration);
}

class FocusSessionsTableCompanion extends UpdateCompanion<FocusSessionEntry> {
  final Value<int> id;
  final Value<DateTime> sessionStart;
  final Value<DateTime?> sessionEnd;
  final Value<int> interruptions;
  final Value<bool> completion;
  final Value<int> duration;
  const FocusSessionsTableCompanion({
    this.id = const Value.absent(),
    this.sessionStart = const Value.absent(),
    this.sessionEnd = const Value.absent(),
    this.interruptions = const Value.absent(),
    this.completion = const Value.absent(),
    this.duration = const Value.absent(),
  });
  FocusSessionsTableCompanion.insert({
    this.id = const Value.absent(),
    required DateTime sessionStart,
    this.sessionEnd = const Value.absent(),
    this.interruptions = const Value.absent(),
    this.completion = const Value.absent(),
    required int duration,
  })  : sessionStart = Value(sessionStart),
        duration = Value(duration);
  static Insertable<FocusSessionEntry> custom({
    Expression<int>? id,
    Expression<DateTime>? sessionStart,
    Expression<DateTime>? sessionEnd,
    Expression<int>? interruptions,
    Expression<bool>? completion,
    Expression<int>? duration,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionStart != null) 'session_start': sessionStart,
      if (sessionEnd != null) 'session_end': sessionEnd,
      if (interruptions != null) 'interruptions': interruptions,
      if (completion != null) 'completion': completion,
      if (duration != null) 'duration': duration,
    });
  }

  FocusSessionsTableCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? sessionStart,
      Value<DateTime?>? sessionEnd,
      Value<int>? interruptions,
      Value<bool>? completion,
      Value<int>? duration}) {
    return FocusSessionsTableCompanion(
      id: id ?? this.id,
      sessionStart: sessionStart ?? this.sessionStart,
      sessionEnd: sessionEnd ?? this.sessionEnd,
      interruptions: interruptions ?? this.interruptions,
      completion: completion ?? this.completion,
      duration: duration ?? this.duration,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionStart.present) {
      map['session_start'] = Variable<DateTime>(sessionStart.value);
    }
    if (sessionEnd.present) {
      map['session_end'] = Variable<DateTime>(sessionEnd.value);
    }
    if (interruptions.present) {
      map['interruptions'] = Variable<int>(interruptions.value);
    }
    if (completion.present) {
      map['completion'] = Variable<bool>(completion.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsTableCompanion(')
          ..write('id: $id, ')
          ..write('sessionStart: $sessionStart, ')
          ..write('sessionEnd: $sessionEnd, ')
          ..write('interruptions: $interruptions, ')
          ..write('completion: $completion, ')
          ..write('duration: $duration')
          ..write(')'))
        .toString();
  }
}

class $DailyBriefTableTable extends DailyBriefTable
    with TableInfo<$DailyBriefTableTable, DailyBriefEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyBriefTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _notificationsReviewedMeta =
      const VerificationMeta('notificationsReviewed');
  @override
  late final GeneratedColumn<int> notificationsReviewed = GeneratedColumn<int>(
      'notifications_reviewed', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _actionsCompletedMeta =
      const VerificationMeta('actionsCompleted');
  @override
  late final GeneratedColumn<int> actionsCompleted = GeneratedColumn<int>(
      'actions_completed', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _calendarEventsCreatedMeta =
      const VerificationMeta('calendarEventsCreated');
  @override
  late final GeneratedColumn<int> calendarEventsCreated = GeneratedColumn<int>(
      'calendar_events_created', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _remindersCreatedMeta =
      const VerificationMeta('remindersCreated');
  @override
  late final GeneratedColumn<int> remindersCreated = GeneratedColumn<int>(
      'reminders_created', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _archivedCountMeta =
      const VerificationMeta('archivedCount');
  @override
  late final GeneratedColumn<int> archivedCount = GeneratedColumn<int>(
      'archived_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        date,
        notificationsReviewed,
        actionsCompleted,
        calendarEventsCreated,
        remindersCreated,
        archivedCount
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_brief_table';
  @override
  VerificationContext validateIntegrity(Insertable<DailyBriefEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('notifications_reviewed')) {
      context.handle(
          _notificationsReviewedMeta,
          notificationsReviewed.isAcceptableOrUnknown(
              data['notifications_reviewed']!, _notificationsReviewedMeta));
    }
    if (data.containsKey('actions_completed')) {
      context.handle(
          _actionsCompletedMeta,
          actionsCompleted.isAcceptableOrUnknown(
              data['actions_completed']!, _actionsCompletedMeta));
    }
    if (data.containsKey('calendar_events_created')) {
      context.handle(
          _calendarEventsCreatedMeta,
          calendarEventsCreated.isAcceptableOrUnknown(
              data['calendar_events_created']!, _calendarEventsCreatedMeta));
    }
    if (data.containsKey('reminders_created')) {
      context.handle(
          _remindersCreatedMeta,
          remindersCreated.isAcceptableOrUnknown(
              data['reminders_created']!, _remindersCreatedMeta));
    }
    if (data.containsKey('archived_count')) {
      context.handle(
          _archivedCountMeta,
          archivedCount.isAcceptableOrUnknown(
              data['archived_count']!, _archivedCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyBriefEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyBriefEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      notificationsReviewed: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}notifications_reviewed'])!,
      actionsCompleted: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}actions_completed'])!,
      calendarEventsCreated: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}calendar_events_created'])!,
      remindersCreated: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reminders_created'])!,
      archivedCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}archived_count'])!,
    );
  }

  @override
  $DailyBriefTableTable createAlias(String alias) {
    return $DailyBriefTableTable(attachedDatabase, alias);
  }
}

class DailyBriefEntry extends DataClass implements Insertable<DailyBriefEntry> {
  final int id;
  final String date;
  final int notificationsReviewed;
  final int actionsCompleted;
  final int calendarEventsCreated;
  final int remindersCreated;
  final int archivedCount;
  const DailyBriefEntry(
      {required this.id,
      required this.date,
      required this.notificationsReviewed,
      required this.actionsCompleted,
      required this.calendarEventsCreated,
      required this.remindersCreated,
      required this.archivedCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<String>(date);
    map['notifications_reviewed'] = Variable<int>(notificationsReviewed);
    map['actions_completed'] = Variable<int>(actionsCompleted);
    map['calendar_events_created'] = Variable<int>(calendarEventsCreated);
    map['reminders_created'] = Variable<int>(remindersCreated);
    map['archived_count'] = Variable<int>(archivedCount);
    return map;
  }

  DailyBriefTableCompanion toCompanion(bool nullToAbsent) {
    return DailyBriefTableCompanion(
      id: Value(id),
      date: Value(date),
      notificationsReviewed: Value(notificationsReviewed),
      actionsCompleted: Value(actionsCompleted),
      calendarEventsCreated: Value(calendarEventsCreated),
      remindersCreated: Value(remindersCreated),
      archivedCount: Value(archivedCount),
    );
  }

  factory DailyBriefEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyBriefEntry(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      notificationsReviewed:
          serializer.fromJson<int>(json['notificationsReviewed']),
      actionsCompleted: serializer.fromJson<int>(json['actionsCompleted']),
      calendarEventsCreated:
          serializer.fromJson<int>(json['calendarEventsCreated']),
      remindersCreated: serializer.fromJson<int>(json['remindersCreated']),
      archivedCount: serializer.fromJson<int>(json['archivedCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<String>(date),
      'notificationsReviewed': serializer.toJson<int>(notificationsReviewed),
      'actionsCompleted': serializer.toJson<int>(actionsCompleted),
      'calendarEventsCreated': serializer.toJson<int>(calendarEventsCreated),
      'remindersCreated': serializer.toJson<int>(remindersCreated),
      'archivedCount': serializer.toJson<int>(archivedCount),
    };
  }

  DailyBriefEntry copyWith(
          {int? id,
          String? date,
          int? notificationsReviewed,
          int? actionsCompleted,
          int? calendarEventsCreated,
          int? remindersCreated,
          int? archivedCount}) =>
      DailyBriefEntry(
        id: id ?? this.id,
        date: date ?? this.date,
        notificationsReviewed:
            notificationsReviewed ?? this.notificationsReviewed,
        actionsCompleted: actionsCompleted ?? this.actionsCompleted,
        calendarEventsCreated:
            calendarEventsCreated ?? this.calendarEventsCreated,
        remindersCreated: remindersCreated ?? this.remindersCreated,
        archivedCount: archivedCount ?? this.archivedCount,
      );
  @override
  String toString() {
    return (StringBuffer('DailyBriefEntry(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('notificationsReviewed: $notificationsReviewed, ')
          ..write('actionsCompleted: $actionsCompleted, ')
          ..write('calendarEventsCreated: $calendarEventsCreated, ')
          ..write('remindersCreated: $remindersCreated, ')
          ..write('archivedCount: $archivedCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, notificationsReviewed,
      actionsCompleted, calendarEventsCreated, remindersCreated, archivedCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyBriefEntry &&
          other.id == this.id &&
          other.date == this.date &&
          other.notificationsReviewed == this.notificationsReviewed &&
          other.actionsCompleted == this.actionsCompleted &&
          other.calendarEventsCreated == this.calendarEventsCreated &&
          other.remindersCreated == this.remindersCreated &&
          other.archivedCount == this.archivedCount);
}

class DailyBriefTableCompanion extends UpdateCompanion<DailyBriefEntry> {
  final Value<int> id;
  final Value<String> date;
  final Value<int> notificationsReviewed;
  final Value<int> actionsCompleted;
  final Value<int> calendarEventsCreated;
  final Value<int> remindersCreated;
  final Value<int> archivedCount;
  const DailyBriefTableCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.notificationsReviewed = const Value.absent(),
    this.actionsCompleted = const Value.absent(),
    this.calendarEventsCreated = const Value.absent(),
    this.remindersCreated = const Value.absent(),
    this.archivedCount = const Value.absent(),
  });
  DailyBriefTableCompanion.insert({
    this.id = const Value.absent(),
    required String date,
    this.notificationsReviewed = const Value.absent(),
    this.actionsCompleted = const Value.absent(),
    this.calendarEventsCreated = const Value.absent(),
    this.remindersCreated = const Value.absent(),
    this.archivedCount = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyBriefEntry> custom({
    Expression<int>? id,
    Expression<String>? date,
    Expression<int>? notificationsReviewed,
    Expression<int>? actionsCompleted,
    Expression<int>? calendarEventsCreated,
    Expression<int>? remindersCreated,
    Expression<int>? archivedCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (notificationsReviewed != null)
        'notifications_reviewed': notificationsReviewed,
      if (actionsCompleted != null) 'actions_completed': actionsCompleted,
      if (calendarEventsCreated != null)
        'calendar_events_created': calendarEventsCreated,
      if (remindersCreated != null) 'reminders_created': remindersCreated,
      if (archivedCount != null) 'archived_count': archivedCount,
    });
  }

  DailyBriefTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? date,
      Value<int>? notificationsReviewed,
      Value<int>? actionsCompleted,
      Value<int>? calendarEventsCreated,
      Value<int>? remindersCreated,
      Value<int>? archivedCount}) {
    return DailyBriefTableCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      notificationsReviewed:
          notificationsReviewed ?? this.notificationsReviewed,
      actionsCompleted: actionsCompleted ?? this.actionsCompleted,
      calendarEventsCreated:
          calendarEventsCreated ?? this.calendarEventsCreated,
      remindersCreated: remindersCreated ?? this.remindersCreated,
      archivedCount: archivedCount ?? this.archivedCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (notificationsReviewed.present) {
      map['notifications_reviewed'] =
          Variable<int>(notificationsReviewed.value);
    }
    if (actionsCompleted.present) {
      map['actions_completed'] = Variable<int>(actionsCompleted.value);
    }
    if (calendarEventsCreated.present) {
      map['calendar_events_created'] =
          Variable<int>(calendarEventsCreated.value);
    }
    if (remindersCreated.present) {
      map['reminders_created'] = Variable<int>(remindersCreated.value);
    }
    if (archivedCount.present) {
      map['archived_count'] = Variable<int>(archivedCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyBriefTableCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('notificationsReviewed: $notificationsReviewed, ')
          ..write('actionsCompleted: $actionsCompleted, ')
          ..write('calendarEventsCreated: $calendarEventsCreated, ')
          ..write('remindersCreated: $remindersCreated, ')
          ..write('archivedCount: $archivedCount')
          ..write(')'))
        .toString();
  }
}

abstract class _$AttentionDatabase extends GeneratedDatabase {
  _$AttentionDatabase(QueryExecutor e) : super(e);
  late final $NotificationsTableTable notificationsTable =
      $NotificationsTableTable(this);
  late final $ReviewQueueTableTable reviewQueueTable =
      $ReviewQueueTableTable(this);
  late final $FocusSessionsTableTable focusSessionsTable =
      $FocusSessionsTableTable(this);
  late final $DailyBriefTableTable dailyBriefTable =
      $DailyBriefTableTable(this);
  late final NotificationDao notificationDao =
      NotificationDao(this as AttentionDatabase);
  late final ReviewQueueDao reviewQueueDao =
      ReviewQueueDao(this as AttentionDatabase);
  late final FocusSessionDao focusSessionDao =
      FocusSessionDao(this as AttentionDatabase);
  late final DailyBriefDao dailyBriefDao =
      DailyBriefDao(this as AttentionDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        notificationsTable,
        reviewQueueTable,
        focusSessionsTable,
        dailyBriefTable
      ];
}
