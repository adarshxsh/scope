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
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packageNameMeta = const VerificationMeta(
    'packageName',
  );
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
    'package_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOngoingMeta = const VerificationMeta(
    'isOngoing',
  );
  @override
  late final GeneratedColumn<bool> isOngoing = GeneratedColumn<bool>(
    'is_ongoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_ongoing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityScoreMeta = const VerificationMeta(
    'priorityScore',
  );
  @override
  late final GeneratedColumn<double> priorityScore = GeneratedColumn<double>(
    'priority_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classifiedCategoryMeta =
      const VerificationMeta('classifiedCategory');
  @override
  late final GeneratedColumn<String> classifiedCategory =
      GeneratedColumn<String>(
        'classified_category',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _explanationMeta = const VerificationMeta(
    'explanation',
  );
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
    'explanation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ruleVersionMeta = const VerificationMeta(
    'ruleVersion',
  );
  @override
  late final GeneratedColumn<String> ruleVersion = GeneratedColumn<String>(
    'rule_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelVersionMeta = const VerificationMeta(
    'modelVersion',
  );
  @override
  late final GeneratedColumn<String> modelVersion = GeneratedColumn<String>(
    'model_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _engineVersionMeta = const VerificationMeta(
    'engineVersion',
  );
  @override
  late final GeneratedColumn<String> engineVersion = GeneratedColumn<String>(
    'engine_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
  extractedFeatures =
      GeneratedColumn<String>(
        'extracted_features',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Map<String, dynamic>?>(
        $NotificationsTableTable.$converterextractedFeaturesn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<ReviewState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ReviewState>($NotificationsTableTable.$converterstate);
  static const VerificationMeta _snoozedUntilMeta = const VerificationMeta(
    'snoozedUntil',
  );
  @override
  late final GeneratedColumn<DateTime> snoozedUntil = GeneratedColumn<DateTime>(
    'snoozed_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _policyScoreMeta = const VerificationMeta(
    'policyScore',
  );
  @override
  late final GeneratedColumn<double> policyScore = GeneratedColumn<double>(
    'policy_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finalScoreMeta = const VerificationMeta(
    'finalScore',
  );
  @override
  late final GeneratedColumn<double> finalScore = GeneratedColumn<double>(
    'final_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewedMeta = const VerificationMeta(
    'reviewed',
  );
  @override
  late final GeneratedColumn<bool> reviewed = GeneratedColumn<bool>(
    'reviewed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reviewed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dismissedMeta = const VerificationMeta(
    'dismissed',
  );
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
    'dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dismissed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _vectorClockMeta = const VerificationMeta(
    'vectorClock',
  );
  @override
  late final GeneratedColumn<String> vectorClock = GeneratedColumn<String>(
    'vector_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  @override
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncTimestampMeta = const VerificationMeta(
    'syncTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> syncTimestamp =
      GeneratedColumn<DateTime>(
        'sync_timestamp',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
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
    createdAt,
    vectorClock,
    originDeviceId,
    syncTimestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationEntry> instance, {
    bool isInserting = false,
  }) {
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
          data['package_name']!,
          _packageNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('is_ongoing')) {
      context.handle(
        _isOngoingMeta,
        isOngoing.isAcceptableOrUnknown(data['is_ongoing']!, _isOngoingMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('priority_score')) {
      context.handle(
        _priorityScoreMeta,
        priorityScore.isAcceptableOrUnknown(
          data['priority_score']!,
          _priorityScoreMeta,
        ),
      );
    }
    if (data.containsKey('classified_category')) {
      context.handle(
        _classifiedCategoryMeta,
        classifiedCategory.isAcceptableOrUnknown(
          data['classified_category']!,
          _classifiedCategoryMeta,
        ),
      );
    }
    if (data.containsKey('explanation')) {
      context.handle(
        _explanationMeta,
        explanation.isAcceptableOrUnknown(
          data['explanation']!,
          _explanationMeta,
        ),
      );
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    }
    if (data.containsKey('rule_version')) {
      context.handle(
        _ruleVersionMeta,
        ruleVersion.isAcceptableOrUnknown(
          data['rule_version']!,
          _ruleVersionMeta,
        ),
      );
    }
    if (data.containsKey('model_version')) {
      context.handle(
        _modelVersionMeta,
        modelVersion.isAcceptableOrUnknown(
          data['model_version']!,
          _modelVersionMeta,
        ),
      );
    }
    if (data.containsKey('engine_version')) {
      context.handle(
        _engineVersionMeta,
        engineVersion.isAcceptableOrUnknown(
          data['engine_version']!,
          _engineVersionMeta,
        ),
      );
    }
    if (data.containsKey('snoozed_until')) {
      context.handle(
        _snoozedUntilMeta,
        snoozedUntil.isAcceptableOrUnknown(
          data['snoozed_until']!,
          _snoozedUntilMeta,
        ),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    }
    if (data.containsKey('policy_score')) {
      context.handle(
        _policyScoreMeta,
        policyScore.isAcceptableOrUnknown(
          data['policy_score']!,
          _policyScoreMeta,
        ),
      );
    }
    if (data.containsKey('final_score')) {
      context.handle(
        _finalScoreMeta,
        finalScore.isAcceptableOrUnknown(data['final_score']!, _finalScoreMeta),
      );
    }
    if (data.containsKey('reviewed')) {
      context.handle(
        _reviewedMeta,
        reviewed.isAcceptableOrUnknown(data['reviewed']!, _reviewedMeta),
      );
    }
    if (data.containsKey('dismissed')) {
      context.handle(
        _dismissedMeta,
        dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('vector_clock')) {
      context.handle(
        _vectorClockMeta,
        vectorClock.isAcceptableOrUnknown(
          data['vector_clock']!,
          _vectorClockMeta,
        ),
      );
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_timestamp')) {
      context.handle(
        _syncTimestampMeta,
        syncTimestamp.isAcceptableOrUnknown(
          data['sync_timestamp']!,
          _syncTimestampMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      packageName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      isOngoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_ongoing'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      ),
      priorityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}priority_score'],
      ),
      classifiedCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classified_category'],
      ),
      explanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}explanation'],
      ),
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      ),
      ruleVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_version'],
      ),
      modelVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_version'],
      ),
      engineVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine_version'],
      ),
      extractedFeatures: $NotificationsTableTable.$converterextractedFeaturesn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}extracted_features'],
            ),
          ),
      state: $NotificationsTableTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      snoozedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}snoozed_until'],
      ),
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      ),
      policyScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}policy_score'],
      ),
      finalScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}final_score'],
      ),
      reviewed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reviewed'],
      )!,
      dismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dismissed'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      vectorClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vector_clock'],
      ),
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      ),
      syncTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sync_timestamp'],
      ),
    );
  }

  @override
  $NotificationsTableTable createAlias(String alias) {
    return $NotificationsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String>
  $converterextractedFeatures = const JsonConverter();
  static TypeConverter<Map<String, dynamic>?, String?>
  $converterextractedFeaturesn = NullAwareTypeConverter.wrap(
    $converterextractedFeatures,
  );
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
  final String? vectorClock;
  final String? originDeviceId;
  final DateTime? syncTimestamp;
  const NotificationEntry({
    required this.id,
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
    required this.createdAt,
    this.vectorClock,
    this.originDeviceId,
    this.syncTimestamp,
  });
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
      map['extracted_features'] = Variable<String>(
        $NotificationsTableTable.$converterextractedFeaturesn.toSql(
          extractedFeatures,
        ),
      );
    }
    {
      map['state'] = Variable<String>(
        $NotificationsTableTable.$converterstate.toSql(state),
      );
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
    if (!nullToAbsent || vectorClock != null) {
      map['vector_clock'] = Variable<String>(vectorClock);
    }
    if (!nullToAbsent || originDeviceId != null) {
      map['origin_device_id'] = Variable<String>(originDeviceId);
    }
    if (!nullToAbsent || syncTimestamp != null) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp);
    }
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
      vectorClock: vectorClock == null && nullToAbsent
          ? const Value.absent()
          : Value(vectorClock),
      originDeviceId: originDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(originDeviceId),
      syncTimestamp: syncTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(syncTimestamp),
    );
  }

  factory NotificationEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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
      classifiedCategory: serializer.fromJson<String?>(
        json['classifiedCategory'],
      ),
      explanation: serializer.fromJson<String?>(json['explanation']),
      latencyMs: serializer.fromJson<int?>(json['latencyMs']),
      ruleVersion: serializer.fromJson<String?>(json['ruleVersion']),
      modelVersion: serializer.fromJson<String?>(json['modelVersion']),
      engineVersion: serializer.fromJson<String?>(json['engineVersion']),
      extractedFeatures: serializer.fromJson<Map<String, dynamic>?>(
        json['extractedFeatures'],
      ),
      state: $NotificationsTableTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      snoozedUntil: serializer.fromJson<DateTime?>(json['snoozedUntil']),
      lastUpdated: serializer.fromJson<DateTime?>(json['lastUpdated']),
      policyScore: serializer.fromJson<double?>(json['policyScore']),
      finalScore: serializer.fromJson<double?>(json['finalScore']),
      reviewed: serializer.fromJson<bool>(json['reviewed']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      vectorClock: serializer.fromJson<String?>(json['vectorClock']),
      originDeviceId: serializer.fromJson<String?>(json['originDeviceId']),
      syncTimestamp: serializer.fromJson<DateTime?>(json['syncTimestamp']),
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
      'extractedFeatures': serializer.toJson<Map<String, dynamic>?>(
        extractedFeatures,
      ),
      'state': serializer.toJson<String>(
        $NotificationsTableTable.$converterstate.toJson(state),
      ),
      'snoozedUntil': serializer.toJson<DateTime?>(snoozedUntil),
      'lastUpdated': serializer.toJson<DateTime?>(lastUpdated),
      'policyScore': serializer.toJson<double?>(policyScore),
      'finalScore': serializer.toJson<double?>(finalScore),
      'reviewed': serializer.toJson<bool>(reviewed),
      'dismissed': serializer.toJson<bool>(dismissed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'vectorClock': serializer.toJson<String?>(vectorClock),
      'originDeviceId': serializer.toJson<String?>(originDeviceId),
      'syncTimestamp': serializer.toJson<DateTime?>(syncTimestamp),
    };
  }

  NotificationEntry copyWith({
    String? id,
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
    DateTime? createdAt,
    Value<String?> vectorClock = const Value.absent(),
    Value<String?> originDeviceId = const Value.absent(),
    Value<DateTime?> syncTimestamp = const Value.absent(),
  }) => NotificationEntry(
    id: id ?? this.id,
    packageName: packageName ?? this.packageName,
    title: title ?? this.title,
    content: content ?? this.content,
    timestamp: timestamp ?? this.timestamp,
    category: category.present ? category.value : this.category,
    isOngoing: isOngoing ?? this.isOngoing,
    priority: priority.present ? priority.value : this.priority,
    priorityScore: priorityScore.present
        ? priorityScore.value
        : this.priorityScore,
    classifiedCategory: classifiedCategory.present
        ? classifiedCategory.value
        : this.classifiedCategory,
    explanation: explanation.present ? explanation.value : this.explanation,
    latencyMs: latencyMs.present ? latencyMs.value : this.latencyMs,
    ruleVersion: ruleVersion.present ? ruleVersion.value : this.ruleVersion,
    modelVersion: modelVersion.present ? modelVersion.value : this.modelVersion,
    engineVersion: engineVersion.present
        ? engineVersion.value
        : this.engineVersion,
    extractedFeatures: extractedFeatures.present
        ? extractedFeatures.value
        : this.extractedFeatures,
    state: state ?? this.state,
    snoozedUntil: snoozedUntil.present ? snoozedUntil.value : this.snoozedUntil,
    lastUpdated: lastUpdated.present ? lastUpdated.value : this.lastUpdated,
    policyScore: policyScore.present ? policyScore.value : this.policyScore,
    finalScore: finalScore.present ? finalScore.value : this.finalScore,
    reviewed: reviewed ?? this.reviewed,
    dismissed: dismissed ?? this.dismissed,
    createdAt: createdAt ?? this.createdAt,
    vectorClock: vectorClock.present ? vectorClock.value : this.vectorClock,
    originDeviceId: originDeviceId.present
        ? originDeviceId.value
        : this.originDeviceId,
    syncTimestamp: syncTimestamp.present
        ? syncTimestamp.value
        : this.syncTimestamp,
  );
  NotificationEntry copyWithCompanion(NotificationsTableCompanion data) {
    return NotificationEntry(
      id: data.id.present ? data.id.value : this.id,
      packageName: data.packageName.present
          ? data.packageName.value
          : this.packageName,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      category: data.category.present ? data.category.value : this.category,
      isOngoing: data.isOngoing.present ? data.isOngoing.value : this.isOngoing,
      priority: data.priority.present ? data.priority.value : this.priority,
      priorityScore: data.priorityScore.present
          ? data.priorityScore.value
          : this.priorityScore,
      classifiedCategory: data.classifiedCategory.present
          ? data.classifiedCategory.value
          : this.classifiedCategory,
      explanation: data.explanation.present
          ? data.explanation.value
          : this.explanation,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      ruleVersion: data.ruleVersion.present
          ? data.ruleVersion.value
          : this.ruleVersion,
      modelVersion: data.modelVersion.present
          ? data.modelVersion.value
          : this.modelVersion,
      engineVersion: data.engineVersion.present
          ? data.engineVersion.value
          : this.engineVersion,
      extractedFeatures: data.extractedFeatures.present
          ? data.extractedFeatures.value
          : this.extractedFeatures,
      state: data.state.present ? data.state.value : this.state,
      snoozedUntil: data.snoozedUntil.present
          ? data.snoozedUntil.value
          : this.snoozedUntil,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
      policyScore: data.policyScore.present
          ? data.policyScore.value
          : this.policyScore,
      finalScore: data.finalScore.present
          ? data.finalScore.value
          : this.finalScore,
      reviewed: data.reviewed.present ? data.reviewed.value : this.reviewed,
      dismissed: data.dismissed.present ? data.dismissed.value : this.dismissed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      vectorClock: data.vectorClock.present
          ? data.vectorClock.value
          : this.vectorClock,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      syncTimestamp: data.syncTimestamp.present
          ? data.syncTimestamp.value
          : this.syncTimestamp,
    );
  }

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
          ..write('createdAt: $createdAt, ')
          ..write('vectorClock: $vectorClock, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('syncTimestamp: $syncTimestamp')
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
    createdAt,
    vectorClock,
    originDeviceId,
    syncTimestamp,
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
          other.createdAt == this.createdAt &&
          other.vectorClock == this.vectorClock &&
          other.originDeviceId == this.originDeviceId &&
          other.syncTimestamp == this.syncTimestamp);
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
  final Value<String?> vectorClock;
  final Value<String?> originDeviceId;
  final Value<DateTime?> syncTimestamp;
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
    this.vectorClock = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
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
    this.vectorClock = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
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
    Expression<String>? vectorClock,
    Expression<String>? originDeviceId,
    Expression<DateTime>? syncTimestamp,
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
      if (vectorClock != null) 'vector_clock': vectorClock,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (syncTimestamp != null) 'sync_timestamp': syncTimestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationsTableCompanion copyWith({
    Value<String>? id,
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
    Value<String?>? vectorClock,
    Value<String?>? originDeviceId,
    Value<DateTime?>? syncTimestamp,
    Value<int>? rowid,
  }) {
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
      vectorClock: vectorClock ?? this.vectorClock,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      syncTimestamp: syncTimestamp ?? this.syncTimestamp,
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
      map['extracted_features'] = Variable<String>(
        $NotificationsTableTable.$converterextractedFeaturesn.toSql(
          extractedFeatures.value,
        ),
      );
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $NotificationsTableTable.$converterstate.toSql(state.value),
      );
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
    if (vectorClock.present) {
      map['vector_clock'] = Variable<String>(vectorClock.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (syncTimestamp.present) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp.value);
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
          ..write('vectorClock: $vectorClock, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('syncTimestamp: $syncTimestamp, ')
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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<String> notificationId = GeneratedColumn<String>(
    'notification_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notifications_table (id)',
    ),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enqueueTimeMeta = const VerificationMeta(
    'enqueueTime',
  );
  @override
  late final GeneratedColumn<DateTime> enqueueTime = GeneratedColumn<DateTime>(
    'enqueue_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiryTimeMeta = const VerificationMeta(
    'expiryTime',
  );
  @override
  late final GeneratedColumn<DateTime> expiryTime = GeneratedColumn<DateTime>(
    'expiry_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ReviewState, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ReviewState>($ReviewQueueTableTable.$converterstatus);
  static const VerificationMeta _vectorClockMeta = const VerificationMeta(
    'vectorClock',
  );
  @override
  late final GeneratedColumn<String> vectorClock = GeneratedColumn<String>(
    'vector_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  @override
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncTimestampMeta = const VerificationMeta(
    'syncTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> syncTimestamp =
      GeneratedColumn<DateTime>(
        'sync_timestamp',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    notificationId,
    priority,
    enqueueTime,
    expiryTime,
    status,
    vectorClock,
    originDeviceId,
    syncTimestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_queue_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('enqueue_time')) {
      context.handle(
        _enqueueTimeMeta,
        enqueueTime.isAcceptableOrUnknown(
          data['enqueue_time']!,
          _enqueueTimeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_enqueueTimeMeta);
    }
    if (data.containsKey('expiry_time')) {
      context.handle(
        _expiryTimeMeta,
        expiryTime.isAcceptableOrUnknown(data['expiry_time']!, _expiryTimeMeta),
      );
    }
    if (data.containsKey('vector_clock')) {
      context.handle(
        _vectorClockMeta,
        vectorClock.isAcceptableOrUnknown(
          data['vector_clock']!,
          _vectorClockMeta,
        ),
      );
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_timestamp')) {
      context.handle(
        _syncTimestampMeta,
        syncTimestamp.isAcceptableOrUnknown(
          data['sync_timestamp']!,
          _syncTimestampMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewQueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notification_id'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      enqueueTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}enqueue_time'],
      )!,
      expiryTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expiry_time'],
      ),
      status: $ReviewQueueTableTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      vectorClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vector_clock'],
      ),
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      ),
      syncTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sync_timestamp'],
      ),
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
  final String? vectorClock;
  final String? originDeviceId;
  final DateTime? syncTimestamp;
  const ReviewQueueEntry({
    required this.id,
    required this.notificationId,
    required this.priority,
    required this.enqueueTime,
    this.expiryTime,
    required this.status,
    this.vectorClock,
    this.originDeviceId,
    this.syncTimestamp,
  });
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
        $ReviewQueueTableTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || vectorClock != null) {
      map['vector_clock'] = Variable<String>(vectorClock);
    }
    if (!nullToAbsent || originDeviceId != null) {
      map['origin_device_id'] = Variable<String>(originDeviceId);
    }
    if (!nullToAbsent || syncTimestamp != null) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp);
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
      vectorClock: vectorClock == null && nullToAbsent
          ? const Value.absent()
          : Value(vectorClock),
      originDeviceId: originDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(originDeviceId),
      syncTimestamp: syncTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(syncTimestamp),
    );
  }

  factory ReviewQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewQueueEntry(
      id: serializer.fromJson<int>(json['id']),
      notificationId: serializer.fromJson<String>(json['notificationId']),
      priority: serializer.fromJson<String>(json['priority']),
      enqueueTime: serializer.fromJson<DateTime>(json['enqueueTime']),
      expiryTime: serializer.fromJson<DateTime?>(json['expiryTime']),
      status: $ReviewQueueTableTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      vectorClock: serializer.fromJson<String?>(json['vectorClock']),
      originDeviceId: serializer.fromJson<String?>(json['originDeviceId']),
      syncTimestamp: serializer.fromJson<DateTime?>(json['syncTimestamp']),
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
        $ReviewQueueTableTable.$converterstatus.toJson(status),
      ),
      'vectorClock': serializer.toJson<String?>(vectorClock),
      'originDeviceId': serializer.toJson<String?>(originDeviceId),
      'syncTimestamp': serializer.toJson<DateTime?>(syncTimestamp),
    };
  }

  ReviewQueueEntry copyWith({
    int? id,
    String? notificationId,
    String? priority,
    DateTime? enqueueTime,
    Value<DateTime?> expiryTime = const Value.absent(),
    ReviewState? status,
    Value<String?> vectorClock = const Value.absent(),
    Value<String?> originDeviceId = const Value.absent(),
    Value<DateTime?> syncTimestamp = const Value.absent(),
  }) => ReviewQueueEntry(
    id: id ?? this.id,
    notificationId: notificationId ?? this.notificationId,
    priority: priority ?? this.priority,
    enqueueTime: enqueueTime ?? this.enqueueTime,
    expiryTime: expiryTime.present ? expiryTime.value : this.expiryTime,
    status: status ?? this.status,
    vectorClock: vectorClock.present ? vectorClock.value : this.vectorClock,
    originDeviceId: originDeviceId.present
        ? originDeviceId.value
        : this.originDeviceId,
    syncTimestamp: syncTimestamp.present
        ? syncTimestamp.value
        : this.syncTimestamp,
  );
  ReviewQueueEntry copyWithCompanion(ReviewQueueTableCompanion data) {
    return ReviewQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      priority: data.priority.present ? data.priority.value : this.priority,
      enqueueTime: data.enqueueTime.present
          ? data.enqueueTime.value
          : this.enqueueTime,
      expiryTime: data.expiryTime.present
          ? data.expiryTime.value
          : this.expiryTime,
      status: data.status.present ? data.status.value : this.status,
      vectorClock: data.vectorClock.present
          ? data.vectorClock.value
          : this.vectorClock,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      syncTimestamp: data.syncTimestamp.present
          ? data.syncTimestamp.value
          : this.syncTimestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewQueueEntry(')
          ..write('id: $id, ')
          ..write('notificationId: $notificationId, ')
          ..write('priority: $priority, ')
          ..write('enqueueTime: $enqueueTime, ')
          ..write('expiryTime: $expiryTime, ')
          ..write('status: $status, ')
          ..write('vectorClock: $vectorClock, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('syncTimestamp: $syncTimestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    notificationId,
    priority,
    enqueueTime,
    expiryTime,
    status,
    vectorClock,
    originDeviceId,
    syncTimestamp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewQueueEntry &&
          other.id == this.id &&
          other.notificationId == this.notificationId &&
          other.priority == this.priority &&
          other.enqueueTime == this.enqueueTime &&
          other.expiryTime == this.expiryTime &&
          other.status == this.status &&
          other.vectorClock == this.vectorClock &&
          other.originDeviceId == this.originDeviceId &&
          other.syncTimestamp == this.syncTimestamp);
}

class ReviewQueueTableCompanion extends UpdateCompanion<ReviewQueueEntry> {
  final Value<int> id;
  final Value<String> notificationId;
  final Value<String> priority;
  final Value<DateTime> enqueueTime;
  final Value<DateTime?> expiryTime;
  final Value<ReviewState> status;
  final Value<String?> vectorClock;
  final Value<String?> originDeviceId;
  final Value<DateTime?> syncTimestamp;
  const ReviewQueueTableCompanion({
    this.id = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.priority = const Value.absent(),
    this.enqueueTime = const Value.absent(),
    this.expiryTime = const Value.absent(),
    this.status = const Value.absent(),
    this.vectorClock = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
  });
  ReviewQueueTableCompanion.insert({
    this.id = const Value.absent(),
    required String notificationId,
    required String priority,
    required DateTime enqueueTime,
    this.expiryTime = const Value.absent(),
    required ReviewState status,
    this.vectorClock = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
  }) : notificationId = Value(notificationId),
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
    Expression<String>? vectorClock,
    Expression<String>? originDeviceId,
    Expression<DateTime>? syncTimestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notificationId != null) 'notification_id': notificationId,
      if (priority != null) 'priority': priority,
      if (enqueueTime != null) 'enqueue_time': enqueueTime,
      if (expiryTime != null) 'expiry_time': expiryTime,
      if (status != null) 'status': status,
      if (vectorClock != null) 'vector_clock': vectorClock,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (syncTimestamp != null) 'sync_timestamp': syncTimestamp,
    });
  }

  ReviewQueueTableCompanion copyWith({
    Value<int>? id,
    Value<String>? notificationId,
    Value<String>? priority,
    Value<DateTime>? enqueueTime,
    Value<DateTime?>? expiryTime,
    Value<ReviewState>? status,
    Value<String?>? vectorClock,
    Value<String?>? originDeviceId,
    Value<DateTime?>? syncTimestamp,
  }) {
    return ReviewQueueTableCompanion(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      priority: priority ?? this.priority,
      enqueueTime: enqueueTime ?? this.enqueueTime,
      expiryTime: expiryTime ?? this.expiryTime,
      status: status ?? this.status,
      vectorClock: vectorClock ?? this.vectorClock,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      syncTimestamp: syncTimestamp ?? this.syncTimestamp,
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
        $ReviewQueueTableTable.$converterstatus.toSql(status.value),
      );
    }
    if (vectorClock.present) {
      map['vector_clock'] = Variable<String>(vectorClock.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (syncTimestamp.present) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp.value);
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
          ..write('status: $status, ')
          ..write('vectorClock: $vectorClock, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('syncTimestamp: $syncTimestamp')
          ..write(')'))
        .toString();
  }
}

class $RlhfRulesTableTable extends RlhfRulesTable
    with TableInfo<$RlhfRulesTableTable, RlhfRuleEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RlhfRulesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conditionsJsonMeta = const VerificationMeta(
    'conditionsJson',
  );
  @override
  late final GeneratedColumn<String> conditionsJson = GeneratedColumn<String>(
    'conditions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  @override
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vectorClockMeta = const VerificationMeta(
    'vectorClock',
  );
  @override
  late final GeneratedColumn<String> vectorClock = GeneratedColumn<String>(
    'vector_clock',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncTimestampMeta = const VerificationMeta(
    'syncTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> syncTimestamp =
      GeneratedColumn<DateTime>(
        'sync_timestamp',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    category,
    priority,
    conditionsJson,
    isDeleted,
    originDeviceId,
    vectorClock,
    syncTimestamp,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rlhf_rules_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<RlhfRuleEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('conditions_json')) {
      context.handle(
        _conditionsJsonMeta,
        conditionsJson.isAcceptableOrUnknown(
          data['conditions_json']!,
          _conditionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conditionsJsonMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('vector_clock')) {
      context.handle(
        _vectorClockMeta,
        vectorClock.isAcceptableOrUnknown(
          data['vector_clock']!,
          _vectorClockMeta,
        ),
      );
    }
    if (data.containsKey('sync_timestamp')) {
      context.handle(
        _syncTimestampMeta,
        syncTimestamp.isAcceptableOrUnknown(
          data['sync_timestamp']!,
          _syncTimestampMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RlhfRuleEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RlhfRuleEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      conditionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conditions_json'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      ),
      vectorClock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vector_clock'],
      ),
      syncTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sync_timestamp'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RlhfRulesTableTable createAlias(String alias) {
    return $RlhfRulesTableTable(attachedDatabase, alias);
  }
}

class RlhfRuleEntry extends DataClass implements Insertable<RlhfRuleEntry> {
  final String id;
  final String category;
  final String priority;
  final String conditionsJson;
  final bool isDeleted;
  final String? originDeviceId;
  final String? vectorClock;
  final DateTime? syncTimestamp;
  final DateTime updatedAt;
  const RlhfRuleEntry({
    required this.id,
    required this.category,
    required this.priority,
    required this.conditionsJson,
    required this.isDeleted,
    this.originDeviceId,
    this.vectorClock,
    this.syncTimestamp,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category'] = Variable<String>(category);
    map['priority'] = Variable<String>(priority);
    map['conditions_json'] = Variable<String>(conditionsJson);
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || originDeviceId != null) {
      map['origin_device_id'] = Variable<String>(originDeviceId);
    }
    if (!nullToAbsent || vectorClock != null) {
      map['vector_clock'] = Variable<String>(vectorClock);
    }
    if (!nullToAbsent || syncTimestamp != null) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RlhfRulesTableCompanion toCompanion(bool nullToAbsent) {
    return RlhfRulesTableCompanion(
      id: Value(id),
      category: Value(category),
      priority: Value(priority),
      conditionsJson: Value(conditionsJson),
      isDeleted: Value(isDeleted),
      originDeviceId: originDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(originDeviceId),
      vectorClock: vectorClock == null && nullToAbsent
          ? const Value.absent()
          : Value(vectorClock),
      syncTimestamp: syncTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(syncTimestamp),
      updatedAt: Value(updatedAt),
    );
  }

  factory RlhfRuleEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RlhfRuleEntry(
      id: serializer.fromJson<String>(json['id']),
      category: serializer.fromJson<String>(json['category']),
      priority: serializer.fromJson<String>(json['priority']),
      conditionsJson: serializer.fromJson<String>(json['conditionsJson']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      originDeviceId: serializer.fromJson<String?>(json['originDeviceId']),
      vectorClock: serializer.fromJson<String?>(json['vectorClock']),
      syncTimestamp: serializer.fromJson<DateTime?>(json['syncTimestamp']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'category': serializer.toJson<String>(category),
      'priority': serializer.toJson<String>(priority),
      'conditionsJson': serializer.toJson<String>(conditionsJson),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'originDeviceId': serializer.toJson<String?>(originDeviceId),
      'vectorClock': serializer.toJson<String?>(vectorClock),
      'syncTimestamp': serializer.toJson<DateTime?>(syncTimestamp),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RlhfRuleEntry copyWith({
    String? id,
    String? category,
    String? priority,
    String? conditionsJson,
    bool? isDeleted,
    Value<String?> originDeviceId = const Value.absent(),
    Value<String?> vectorClock = const Value.absent(),
    Value<DateTime?> syncTimestamp = const Value.absent(),
    DateTime? updatedAt,
  }) => RlhfRuleEntry(
    id: id ?? this.id,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    conditionsJson: conditionsJson ?? this.conditionsJson,
    isDeleted: isDeleted ?? this.isDeleted,
    originDeviceId: originDeviceId.present
        ? originDeviceId.value
        : this.originDeviceId,
    vectorClock: vectorClock.present ? vectorClock.value : this.vectorClock,
    syncTimestamp: syncTimestamp.present
        ? syncTimestamp.value
        : this.syncTimestamp,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RlhfRuleEntry copyWithCompanion(RlhfRulesTableCompanion data) {
    return RlhfRuleEntry(
      id: data.id.present ? data.id.value : this.id,
      category: data.category.present ? data.category.value : this.category,
      priority: data.priority.present ? data.priority.value : this.priority,
      conditionsJson: data.conditionsJson.present
          ? data.conditionsJson.value
          : this.conditionsJson,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      vectorClock: data.vectorClock.present
          ? data.vectorClock.value
          : this.vectorClock,
      syncTimestamp: data.syncTimestamp.present
          ? data.syncTimestamp.value
          : this.syncTimestamp,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RlhfRuleEntry(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('priority: $priority, ')
          ..write('conditionsJson: $conditionsJson, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('vectorClock: $vectorClock, ')
          ..write('syncTimestamp: $syncTimestamp, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    category,
    priority,
    conditionsJson,
    isDeleted,
    originDeviceId,
    vectorClock,
    syncTimestamp,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RlhfRuleEntry &&
          other.id == this.id &&
          other.category == this.category &&
          other.priority == this.priority &&
          other.conditionsJson == this.conditionsJson &&
          other.isDeleted == this.isDeleted &&
          other.originDeviceId == this.originDeviceId &&
          other.vectorClock == this.vectorClock &&
          other.syncTimestamp == this.syncTimestamp &&
          other.updatedAt == this.updatedAt);
}

class RlhfRulesTableCompanion extends UpdateCompanion<RlhfRuleEntry> {
  final Value<String> id;
  final Value<String> category;
  final Value<String> priority;
  final Value<String> conditionsJson;
  final Value<bool> isDeleted;
  final Value<String?> originDeviceId;
  final Value<String?> vectorClock;
  final Value<DateTime?> syncTimestamp;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RlhfRulesTableCompanion({
    this.id = const Value.absent(),
    this.category = const Value.absent(),
    this.priority = const Value.absent(),
    this.conditionsJson = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.vectorClock = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RlhfRulesTableCompanion.insert({
    required String id,
    required String category,
    required String priority,
    required String conditionsJson,
    this.isDeleted = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.vectorClock = const Value.absent(),
    this.syncTimestamp = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       category = Value(category),
       priority = Value(priority),
       conditionsJson = Value(conditionsJson);
  static Insertable<RlhfRuleEntry> custom({
    Expression<String>? id,
    Expression<String>? category,
    Expression<String>? priority,
    Expression<String>? conditionsJson,
    Expression<bool>? isDeleted,
    Expression<String>? originDeviceId,
    Expression<String>? vectorClock,
    Expression<DateTime>? syncTimestamp,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (priority != null) 'priority': priority,
      if (conditionsJson != null) 'conditions_json': conditionsJson,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (vectorClock != null) 'vector_clock': vectorClock,
      if (syncTimestamp != null) 'sync_timestamp': syncTimestamp,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RlhfRulesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? category,
    Value<String>? priority,
    Value<String>? conditionsJson,
    Value<bool>? isDeleted,
    Value<String?>? originDeviceId,
    Value<String?>? vectorClock,
    Value<DateTime?>? syncTimestamp,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RlhfRulesTableCompanion(
      id: id ?? this.id,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      conditionsJson: conditionsJson ?? this.conditionsJson,
      isDeleted: isDeleted ?? this.isDeleted,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      vectorClock: vectorClock ?? this.vectorClock,
      syncTimestamp: syncTimestamp ?? this.syncTimestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (conditionsJson.present) {
      map['conditions_json'] = Variable<String>(conditionsJson.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (vectorClock.present) {
      map['vector_clock'] = Variable<String>(vectorClock.value);
    }
    if (syncTimestamp.present) {
      map['sync_timestamp'] = Variable<DateTime>(syncTimestamp.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RlhfRulesTableCompanion(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('priority: $priority, ')
          ..write('conditionsJson: $conditionsJson, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('vectorClock: $vectorClock, ')
          ..write('syncTimestamp: $syncTimestamp, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineSyncQueueTableTable extends OfflineSyncQueueTable
    with TableInfo<$OfflineSyncQueueTableTable, OfflineSyncQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineSyncQueueTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _payloadTypeMeta = const VerificationMeta(
    'payloadType',
  );
  @override
  late final GeneratedColumn<String> payloadType = GeneratedColumn<String>(
    'payload_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedPayloadJsonMeta =
      const VerificationMeta('encryptedPayloadJson');
  @override
  late final GeneratedColumn<String> encryptedPayloadJson =
      GeneratedColumn<String>(
        'encrypted_payload_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payloadType,
    entityId,
    encryptedPayloadJson,
    createdAt,
    isSynced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_sync_queue_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineSyncQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('payload_type')) {
      context.handle(
        _payloadTypeMeta,
        payloadType.isAcceptableOrUnknown(
          data['payload_type']!,
          _payloadTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('encrypted_payload_json')) {
      context.handle(
        _encryptedPayloadJsonMeta,
        encryptedPayloadJson.isAcceptableOrUnknown(
          data['encrypted_payload_json']!,
          _encryptedPayloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPayloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineSyncQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineSyncQueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      payloadType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      encryptedPayloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
    );
  }

  @override
  $OfflineSyncQueueTableTable createAlias(String alias) {
    return $OfflineSyncQueueTableTable(attachedDatabase, alias);
  }
}

class OfflineSyncQueueEntry extends DataClass
    implements Insertable<OfflineSyncQueueEntry> {
  final int id;
  final String payloadType;
  final String entityId;
  final String encryptedPayloadJson;
  final DateTime createdAt;
  final bool isSynced;
  const OfflineSyncQueueEntry({
    required this.id,
    required this.payloadType,
    required this.entityId,
    required this.encryptedPayloadJson,
    required this.createdAt,
    required this.isSynced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payload_type'] = Variable<String>(payloadType);
    map['entity_id'] = Variable<String>(entityId);
    map['encrypted_payload_json'] = Variable<String>(encryptedPayloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_synced'] = Variable<bool>(isSynced);
    return map;
  }

  OfflineSyncQueueTableCompanion toCompanion(bool nullToAbsent) {
    return OfflineSyncQueueTableCompanion(
      id: Value(id),
      payloadType: Value(payloadType),
      entityId: Value(entityId),
      encryptedPayloadJson: Value(encryptedPayloadJson),
      createdAt: Value(createdAt),
      isSynced: Value(isSynced),
    );
  }

  factory OfflineSyncQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineSyncQueueEntry(
      id: serializer.fromJson<int>(json['id']),
      payloadType: serializer.fromJson<String>(json['payloadType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      encryptedPayloadJson: serializer.fromJson<String>(
        json['encryptedPayloadJson'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'payloadType': serializer.toJson<String>(payloadType),
      'entityId': serializer.toJson<String>(entityId),
      'encryptedPayloadJson': serializer.toJson<String>(encryptedPayloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isSynced': serializer.toJson<bool>(isSynced),
    };
  }

  OfflineSyncQueueEntry copyWith({
    int? id,
    String? payloadType,
    String? entityId,
    String? encryptedPayloadJson,
    DateTime? createdAt,
    bool? isSynced,
  }) => OfflineSyncQueueEntry(
    id: id ?? this.id,
    payloadType: payloadType ?? this.payloadType,
    entityId: entityId ?? this.entityId,
    encryptedPayloadJson: encryptedPayloadJson ?? this.encryptedPayloadJson,
    createdAt: createdAt ?? this.createdAt,
    isSynced: isSynced ?? this.isSynced,
  );
  OfflineSyncQueueEntry copyWithCompanion(OfflineSyncQueueTableCompanion data) {
    return OfflineSyncQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      payloadType: data.payloadType.present
          ? data.payloadType.value
          : this.payloadType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      encryptedPayloadJson: data.encryptedPayloadJson.present
          ? data.encryptedPayloadJson.value
          : this.encryptedPayloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineSyncQueueEntry(')
          ..write('id: $id, ')
          ..write('payloadType: $payloadType, ')
          ..write('entityId: $entityId, ')
          ..write('encryptedPayloadJson: $encryptedPayloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payloadType,
    entityId,
    encryptedPayloadJson,
    createdAt,
    isSynced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineSyncQueueEntry &&
          other.id == this.id &&
          other.payloadType == this.payloadType &&
          other.entityId == this.entityId &&
          other.encryptedPayloadJson == this.encryptedPayloadJson &&
          other.createdAt == this.createdAt &&
          other.isSynced == this.isSynced);
}

class OfflineSyncQueueTableCompanion
    extends UpdateCompanion<OfflineSyncQueueEntry> {
  final Value<int> id;
  final Value<String> payloadType;
  final Value<String> entityId;
  final Value<String> encryptedPayloadJson;
  final Value<DateTime> createdAt;
  final Value<bool> isSynced;
  const OfflineSyncQueueTableCompanion({
    this.id = const Value.absent(),
    this.payloadType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.encryptedPayloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isSynced = const Value.absent(),
  });
  OfflineSyncQueueTableCompanion.insert({
    this.id = const Value.absent(),
    required String payloadType,
    required String entityId,
    required String encryptedPayloadJson,
    this.createdAt = const Value.absent(),
    this.isSynced = const Value.absent(),
  }) : payloadType = Value(payloadType),
       entityId = Value(entityId),
       encryptedPayloadJson = Value(encryptedPayloadJson);
  static Insertable<OfflineSyncQueueEntry> custom({
    Expression<int>? id,
    Expression<String>? payloadType,
    Expression<String>? entityId,
    Expression<String>? encryptedPayloadJson,
    Expression<DateTime>? createdAt,
    Expression<bool>? isSynced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payloadType != null) 'payload_type': payloadType,
      if (entityId != null) 'entity_id': entityId,
      if (encryptedPayloadJson != null)
        'encrypted_payload_json': encryptedPayloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (isSynced != null) 'is_synced': isSynced,
    });
  }

  OfflineSyncQueueTableCompanion copyWith({
    Value<int>? id,
    Value<String>? payloadType,
    Value<String>? entityId,
    Value<String>? encryptedPayloadJson,
    Value<DateTime>? createdAt,
    Value<bool>? isSynced,
  }) {
    return OfflineSyncQueueTableCompanion(
      id: id ?? this.id,
      payloadType: payloadType ?? this.payloadType,
      entityId: entityId ?? this.entityId,
      encryptedPayloadJson: encryptedPayloadJson ?? this.encryptedPayloadJson,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (payloadType.present) {
      map['payload_type'] = Variable<String>(payloadType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (encryptedPayloadJson.present) {
      map['encrypted_payload_json'] = Variable<String>(
        encryptedPayloadJson.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineSyncQueueTableCompanion(')
          ..write('id: $id, ')
          ..write('payloadType: $payloadType, ')
          ..write('entityId: $entityId, ')
          ..write('encryptedPayloadJson: $encryptedPayloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced')
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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionStartMeta = const VerificationMeta(
    'sessionStart',
  );
  @override
  late final GeneratedColumn<DateTime> sessionStart = GeneratedColumn<DateTime>(
    'session_start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionEndMeta = const VerificationMeta(
    'sessionEnd',
  );
  @override
  late final GeneratedColumn<DateTime> sessionEnd = GeneratedColumn<DateTime>(
    'session_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interruptionsMeta = const VerificationMeta(
    'interruptions',
  );
  @override
  late final GeneratedColumn<int> interruptions = GeneratedColumn<int>(
    'interruptions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completionMeta = const VerificationMeta(
    'completion',
  );
  @override
  late final GeneratedColumn<bool> completion = GeneratedColumn<bool>(
    'completion',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completion" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionStart,
    sessionEnd,
    interruptions,
    completion,
    duration,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSessionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_start')) {
      context.handle(
        _sessionStartMeta,
        sessionStart.isAcceptableOrUnknown(
          data['session_start']!,
          _sessionStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionStartMeta);
    }
    if (data.containsKey('session_end')) {
      context.handle(
        _sessionEndMeta,
        sessionEnd.isAcceptableOrUnknown(data['session_end']!, _sessionEndMeta),
      );
    }
    if (data.containsKey('interruptions')) {
      context.handle(
        _interruptionsMeta,
        interruptions.isAcceptableOrUnknown(
          data['interruptions']!,
          _interruptionsMeta,
        ),
      );
    }
    if (data.containsKey('completion')) {
      context.handle(
        _completionMeta,
        completion.isAcceptableOrUnknown(data['completion']!, _completionMeta),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
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
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}session_start'],
      )!,
      sessionEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}session_end'],
      ),
      interruptions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interruptions'],
      )!,
      completion: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completion'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      )!,
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
  const FocusSessionEntry({
    required this.id,
    required this.sessionStart,
    this.sessionEnd,
    required this.interruptions,
    required this.completion,
    required this.duration,
  });
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

  factory FocusSessionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  FocusSessionEntry copyWith({
    int? id,
    DateTime? sessionStart,
    Value<DateTime?> sessionEnd = const Value.absent(),
    int? interruptions,
    bool? completion,
    int? duration,
  }) => FocusSessionEntry(
    id: id ?? this.id,
    sessionStart: sessionStart ?? this.sessionStart,
    sessionEnd: sessionEnd.present ? sessionEnd.value : this.sessionEnd,
    interruptions: interruptions ?? this.interruptions,
    completion: completion ?? this.completion,
    duration: duration ?? this.duration,
  );
  FocusSessionEntry copyWithCompanion(FocusSessionsTableCompanion data) {
    return FocusSessionEntry(
      id: data.id.present ? data.id.value : this.id,
      sessionStart: data.sessionStart.present
          ? data.sessionStart.value
          : this.sessionStart,
      sessionEnd: data.sessionEnd.present
          ? data.sessionEnd.value
          : this.sessionEnd,
      interruptions: data.interruptions.present
          ? data.interruptions.value
          : this.interruptions,
      completion: data.completion.present
          ? data.completion.value
          : this.completion,
      duration: data.duration.present ? data.duration.value : this.duration,
    );
  }

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
    id,
    sessionStart,
    sessionEnd,
    interruptions,
    completion,
    duration,
  );
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
  }) : sessionStart = Value(sessionStart),
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

  FocusSessionsTableCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? sessionStart,
    Value<DateTime?>? sessionEnd,
    Value<int>? interruptions,
    Value<bool>? completion,
    Value<int>? duration,
  }) {
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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _notificationsReviewedMeta =
      const VerificationMeta('notificationsReviewed');
  @override
  late final GeneratedColumn<int> notificationsReviewed = GeneratedColumn<int>(
    'notifications_reviewed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _actionsCompletedMeta = const VerificationMeta(
    'actionsCompleted',
  );
  @override
  late final GeneratedColumn<int> actionsCompleted = GeneratedColumn<int>(
    'actions_completed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _calendarEventsCreatedMeta =
      const VerificationMeta('calendarEventsCreated');
  @override
  late final GeneratedColumn<int> calendarEventsCreated = GeneratedColumn<int>(
    'calendar_events_created',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remindersCreatedMeta = const VerificationMeta(
    'remindersCreated',
  );
  @override
  late final GeneratedColumn<int> remindersCreated = GeneratedColumn<int>(
    'reminders_created',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedCountMeta = const VerificationMeta(
    'archivedCount',
  );
  @override
  late final GeneratedColumn<int> archivedCount = GeneratedColumn<int>(
    'archived_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    notificationsReviewed,
    actionsCompleted,
    calendarEventsCreated,
    remindersCreated,
    archivedCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_brief_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyBriefEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('notifications_reviewed')) {
      context.handle(
        _notificationsReviewedMeta,
        notificationsReviewed.isAcceptableOrUnknown(
          data['notifications_reviewed']!,
          _notificationsReviewedMeta,
        ),
      );
    }
    if (data.containsKey('actions_completed')) {
      context.handle(
        _actionsCompletedMeta,
        actionsCompleted.isAcceptableOrUnknown(
          data['actions_completed']!,
          _actionsCompletedMeta,
        ),
      );
    }
    if (data.containsKey('calendar_events_created')) {
      context.handle(
        _calendarEventsCreatedMeta,
        calendarEventsCreated.isAcceptableOrUnknown(
          data['calendar_events_created']!,
          _calendarEventsCreatedMeta,
        ),
      );
    }
    if (data.containsKey('reminders_created')) {
      context.handle(
        _remindersCreatedMeta,
        remindersCreated.isAcceptableOrUnknown(
          data['reminders_created']!,
          _remindersCreatedMeta,
        ),
      );
    }
    if (data.containsKey('archived_count')) {
      context.handle(
        _archivedCountMeta,
        archivedCount.isAcceptableOrUnknown(
          data['archived_count']!,
          _archivedCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyBriefEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyBriefEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      notificationsReviewed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notifications_reviewed'],
      )!,
      actionsCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actions_completed'],
      )!,
      calendarEventsCreated: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calendar_events_created'],
      )!,
      remindersCreated: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminders_created'],
      )!,
      archivedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived_count'],
      )!,
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
  const DailyBriefEntry({
    required this.id,
    required this.date,
    required this.notificationsReviewed,
    required this.actionsCompleted,
    required this.calendarEventsCreated,
    required this.remindersCreated,
    required this.archivedCount,
  });
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

  factory DailyBriefEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyBriefEntry(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      notificationsReviewed: serializer.fromJson<int>(
        json['notificationsReviewed'],
      ),
      actionsCompleted: serializer.fromJson<int>(json['actionsCompleted']),
      calendarEventsCreated: serializer.fromJson<int>(
        json['calendarEventsCreated'],
      ),
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

  DailyBriefEntry copyWith({
    int? id,
    String? date,
    int? notificationsReviewed,
    int? actionsCompleted,
    int? calendarEventsCreated,
    int? remindersCreated,
    int? archivedCount,
  }) => DailyBriefEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    notificationsReviewed: notificationsReviewed ?? this.notificationsReviewed,
    actionsCompleted: actionsCompleted ?? this.actionsCompleted,
    calendarEventsCreated: calendarEventsCreated ?? this.calendarEventsCreated,
    remindersCreated: remindersCreated ?? this.remindersCreated,
    archivedCount: archivedCount ?? this.archivedCount,
  );
  DailyBriefEntry copyWithCompanion(DailyBriefTableCompanion data) {
    return DailyBriefEntry(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      notificationsReviewed: data.notificationsReviewed.present
          ? data.notificationsReviewed.value
          : this.notificationsReviewed,
      actionsCompleted: data.actionsCompleted.present
          ? data.actionsCompleted.value
          : this.actionsCompleted,
      calendarEventsCreated: data.calendarEventsCreated.present
          ? data.calendarEventsCreated.value
          : this.calendarEventsCreated,
      remindersCreated: data.remindersCreated.present
          ? data.remindersCreated.value
          : this.remindersCreated,
      archivedCount: data.archivedCount.present
          ? data.archivedCount.value
          : this.archivedCount,
    );
  }

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
  int get hashCode => Object.hash(
    id,
    date,
    notificationsReviewed,
    actionsCompleted,
    calendarEventsCreated,
    remindersCreated,
    archivedCount,
  );
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

  DailyBriefTableCompanion copyWith({
    Value<int>? id,
    Value<String>? date,
    Value<int>? notificationsReviewed,
    Value<int>? actionsCompleted,
    Value<int>? calendarEventsCreated,
    Value<int>? remindersCreated,
    Value<int>? archivedCount,
  }) {
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
      map['notifications_reviewed'] = Variable<int>(
        notificationsReviewed.value,
      );
    }
    if (actionsCompleted.present) {
      map['actions_completed'] = Variable<int>(actionsCompleted.value);
    }
    if (calendarEventsCreated.present) {
      map['calendar_events_created'] = Variable<int>(
        calendarEventsCreated.value,
      );
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

class $PrivacyLedgerTableTable extends PrivacyLedgerTable
    with TableInfo<$PrivacyLedgerTableTable, PrivacyLedgerEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrivacyLedgerTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _epsilonSpentMeta = const VerificationMeta(
    'epsilonSpent',
  );
  @override
  late final GeneratedColumn<double> epsilonSpent = GeneratedColumn<double>(
    'epsilon_spent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _deltaSpentMeta = const VerificationMeta(
    'deltaSpent',
  );
  @override
  late final GeneratedColumn<double> deltaSpent = GeneratedColumn<double>(
    'delta_spent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _queryCountMeta = const VerificationMeta(
    'queryCount',
  );
  @override
  late final GeneratedColumn<int> queryCount = GeneratedColumn<int>(
    'query_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    epsilonSpent,
    deltaSpent,
    queryCount,
    lastUpdated,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'privacy_ledger_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrivacyLedgerEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('epsilon_spent')) {
      context.handle(
        _epsilonSpentMeta,
        epsilonSpent.isAcceptableOrUnknown(
          data['epsilon_spent']!,
          _epsilonSpentMeta,
        ),
      );
    }
    if (data.containsKey('delta_spent')) {
      context.handle(
        _deltaSpentMeta,
        deltaSpent.isAcceptableOrUnknown(data['delta_spent']!, _deltaSpentMeta),
      );
    }
    if (data.containsKey('query_count')) {
      context.handle(
        _queryCountMeta,
        queryCount.isAcceptableOrUnknown(data['query_count']!, _queryCountMeta),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrivacyLedgerEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrivacyLedgerEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      epsilonSpent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}epsilon_spent'],
      )!,
      deltaSpent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}delta_spent'],
      )!,
      queryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}query_count'],
      )!,
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      )!,
    );
  }

  @override
  $PrivacyLedgerTableTable createAlias(String alias) {
    return $PrivacyLedgerTableTable(attachedDatabase, alias);
  }
}

class PrivacyLedgerEntry extends DataClass
    implements Insertable<PrivacyLedgerEntry> {
  final int id;
  final String date;
  final double epsilonSpent;
  final double deltaSpent;
  final int queryCount;
  final DateTime lastUpdated;
  const PrivacyLedgerEntry({
    required this.id,
    required this.date,
    required this.epsilonSpent,
    required this.deltaSpent,
    required this.queryCount,
    required this.lastUpdated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<String>(date);
    map['epsilon_spent'] = Variable<double>(epsilonSpent);
    map['delta_spent'] = Variable<double>(deltaSpent);
    map['query_count'] = Variable<int>(queryCount);
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    return map;
  }

  PrivacyLedgerTableCompanion toCompanion(bool nullToAbsent) {
    return PrivacyLedgerTableCompanion(
      id: Value(id),
      date: Value(date),
      epsilonSpent: Value(epsilonSpent),
      deltaSpent: Value(deltaSpent),
      queryCount: Value(queryCount),
      lastUpdated: Value(lastUpdated),
    );
  }

  factory PrivacyLedgerEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrivacyLedgerEntry(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      epsilonSpent: serializer.fromJson<double>(json['epsilonSpent']),
      deltaSpent: serializer.fromJson<double>(json['deltaSpent']),
      queryCount: serializer.fromJson<int>(json['queryCount']),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<String>(date),
      'epsilonSpent': serializer.toJson<double>(epsilonSpent),
      'deltaSpent': serializer.toJson<double>(deltaSpent),
      'queryCount': serializer.toJson<int>(queryCount),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
    };
  }

  PrivacyLedgerEntry copyWith({
    int? id,
    String? date,
    double? epsilonSpent,
    double? deltaSpent,
    int? queryCount,
    DateTime? lastUpdated,
  }) => PrivacyLedgerEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    epsilonSpent: epsilonSpent ?? this.epsilonSpent,
    deltaSpent: deltaSpent ?? this.deltaSpent,
    queryCount: queryCount ?? this.queryCount,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
  PrivacyLedgerEntry copyWithCompanion(PrivacyLedgerTableCompanion data) {
    return PrivacyLedgerEntry(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      epsilonSpent: data.epsilonSpent.present
          ? data.epsilonSpent.value
          : this.epsilonSpent,
      deltaSpent: data.deltaSpent.present
          ? data.deltaSpent.value
          : this.deltaSpent,
      queryCount: data.queryCount.present
          ? data.queryCount.value
          : this.queryCount,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyLedgerEntry(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('epsilonSpent: $epsilonSpent, ')
          ..write('deltaSpent: $deltaSpent, ')
          ..write('queryCount: $queryCount, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, date, epsilonSpent, deltaSpent, queryCount, lastUpdated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrivacyLedgerEntry &&
          other.id == this.id &&
          other.date == this.date &&
          other.epsilonSpent == this.epsilonSpent &&
          other.deltaSpent == this.deltaSpent &&
          other.queryCount == this.queryCount &&
          other.lastUpdated == this.lastUpdated);
}

class PrivacyLedgerTableCompanion extends UpdateCompanion<PrivacyLedgerEntry> {
  final Value<int> id;
  final Value<String> date;
  final Value<double> epsilonSpent;
  final Value<double> deltaSpent;
  final Value<int> queryCount;
  final Value<DateTime> lastUpdated;
  const PrivacyLedgerTableCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.epsilonSpent = const Value.absent(),
    this.deltaSpent = const Value.absent(),
    this.queryCount = const Value.absent(),
    this.lastUpdated = const Value.absent(),
  });
  PrivacyLedgerTableCompanion.insert({
    this.id = const Value.absent(),
    required String date,
    this.epsilonSpent = const Value.absent(),
    this.deltaSpent = const Value.absent(),
    this.queryCount = const Value.absent(),
    this.lastUpdated = const Value.absent(),
  }) : date = Value(date);
  static Insertable<PrivacyLedgerEntry> custom({
    Expression<int>? id,
    Expression<String>? date,
    Expression<double>? epsilonSpent,
    Expression<double>? deltaSpent,
    Expression<int>? queryCount,
    Expression<DateTime>? lastUpdated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (epsilonSpent != null) 'epsilon_spent': epsilonSpent,
      if (deltaSpent != null) 'delta_spent': deltaSpent,
      if (queryCount != null) 'query_count': queryCount,
      if (lastUpdated != null) 'last_updated': lastUpdated,
    });
  }

  PrivacyLedgerTableCompanion copyWith({
    Value<int>? id,
    Value<String>? date,
    Value<double>? epsilonSpent,
    Value<double>? deltaSpent,
    Value<int>? queryCount,
    Value<DateTime>? lastUpdated,
  }) {
    return PrivacyLedgerTableCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      epsilonSpent: epsilonSpent ?? this.epsilonSpent,
      deltaSpent: deltaSpent ?? this.deltaSpent,
      queryCount: queryCount ?? this.queryCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
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
    if (epsilonSpent.present) {
      map['epsilon_spent'] = Variable<double>(epsilonSpent.value);
    }
    if (deltaSpent.present) {
      map['delta_spent'] = Variable<double>(deltaSpent.value);
    }
    if (queryCount.present) {
      map['query_count'] = Variable<int>(queryCount.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyLedgerTableCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('epsilonSpent: $epsilonSpent, ')
          ..write('deltaSpent: $deltaSpent, ')
          ..write('queryCount: $queryCount, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }
}

abstract class _$AttentionDatabase extends GeneratedDatabase {
  _$AttentionDatabase(QueryExecutor e) : super(e);
  $AttentionDatabaseManager get managers => $AttentionDatabaseManager(this);
  late final $NotificationsTableTable notificationsTable =
      $NotificationsTableTable(this);
  late final $ReviewQueueTableTable reviewQueueTable = $ReviewQueueTableTable(
    this,
  );
  late final $RlhfRulesTableTable rlhfRulesTable = $RlhfRulesTableTable(this);
  late final $OfflineSyncQueueTableTable offlineSyncQueueTable =
      $OfflineSyncQueueTableTable(this);
  late final $FocusSessionsTableTable focusSessionsTable =
      $FocusSessionsTableTable(this);
  late final $DailyBriefTableTable dailyBriefTable = $DailyBriefTableTable(
    this,
  );
  late final $PrivacyLedgerTableTable privacyLedgerTable =
      $PrivacyLedgerTableTable(this);
  late final NotificationDao notificationDao = NotificationDao(
    this as AttentionDatabase,
  );
  late final ReviewQueueDao reviewQueueDao = ReviewQueueDao(
    this as AttentionDatabase,
  );
  late final RlhfRulesDao rlhfRulesDao = RlhfRulesDao(
    this as AttentionDatabase,
  );
  late final OfflineSyncQueueDao offlineSyncQueueDao = OfflineSyncQueueDao(
    this as AttentionDatabase,
  );
  late final FocusSessionDao focusSessionDao = FocusSessionDao(
    this as AttentionDatabase,
  );
  late final DailyBriefDao dailyBriefDao = DailyBriefDao(
    this as AttentionDatabase,
  );
  late final PrivacyLedgerDao privacyLedgerDao = PrivacyLedgerDao(
    this as AttentionDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    notificationsTable,
    reviewQueueTable,
    rlhfRulesTable,
    offlineSyncQueueTable,
    focusSessionsTable,
    dailyBriefTable,
    privacyLedgerTable,
  ];
}

typedef $$NotificationsTableTableCreateCompanionBuilder =
    NotificationsTableCompanion Function({
      required String id,
      required String packageName,
      required String title,
      required String content,
      required int timestamp,
      Value<String?> category,
      Value<bool> isOngoing,
      Value<String?> priority,
      Value<double?> priorityScore,
      Value<String?> classifiedCategory,
      Value<String?> explanation,
      Value<int?> latencyMs,
      Value<String?> ruleVersion,
      Value<String?> modelVersion,
      Value<String?> engineVersion,
      Value<Map<String, dynamic>?> extractedFeatures,
      required ReviewState state,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> lastUpdated,
      Value<double?> policyScore,
      Value<double?> finalScore,
      Value<bool> reviewed,
      Value<bool> dismissed,
      Value<DateTime> createdAt,
      Value<String?> vectorClock,
      Value<String?> originDeviceId,
      Value<DateTime?> syncTimestamp,
      Value<int> rowid,
    });
typedef $$NotificationsTableTableUpdateCompanionBuilder =
    NotificationsTableCompanion Function({
      Value<String> id,
      Value<String> packageName,
      Value<String> title,
      Value<String> content,
      Value<int> timestamp,
      Value<String?> category,
      Value<bool> isOngoing,
      Value<String?> priority,
      Value<double?> priorityScore,
      Value<String?> classifiedCategory,
      Value<String?> explanation,
      Value<int?> latencyMs,
      Value<String?> ruleVersion,
      Value<String?> modelVersion,
      Value<String?> engineVersion,
      Value<Map<String, dynamic>?> extractedFeatures,
      Value<ReviewState> state,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> lastUpdated,
      Value<double?> policyScore,
      Value<double?> finalScore,
      Value<bool> reviewed,
      Value<bool> dismissed,
      Value<DateTime> createdAt,
      Value<String?> vectorClock,
      Value<String?> originDeviceId,
      Value<DateTime?> syncTimestamp,
      Value<int> rowid,
    });

final class $$NotificationsTableTableReferences
    extends
        BaseReferences<
          _$AttentionDatabase,
          $NotificationsTableTable,
          NotificationEntry
        > {
  $$NotificationsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ReviewQueueTableTable, List<ReviewQueueEntry>>
  _reviewQueueTableRefsTable(_$AttentionDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewQueueTable,
        aliasName:
            'notifications_table__id__review_queue_table__notification_id',
      );

  $$ReviewQueueTableTableProcessedTableManager get reviewQueueTableRefs {
    final manager = $$ReviewQueueTableTableTableManager(
      $_db,
      $_db.reviewQueueTable,
    ).filter((f) => f.notificationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewQueueTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NotificationsTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOngoing => $composableBuilder(
    column: $table.isOngoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get priorityScore => $composableBuilder(
    column: $table.priorityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classifiedCategory => $composableBuilder(
    column: $table.classifiedCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleVersion => $composableBuilder(
    column: $table.ruleVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engineVersion => $composableBuilder(
    column: $table.engineVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, dynamic>?,
    Map<String, dynamic>,
    String
  >
  get extractedFeatures => $composableBuilder(
    column: $table.extractedFeatures,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ReviewState, ReviewState, String> get state =>
      $composableBuilder(
        column: $table.state,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get policyScore => $composableBuilder(
    column: $table.policyScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reviewed => $composableBuilder(
    column: $table.reviewed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> reviewQueueTableRefs(
    Expression<bool> Function($$ReviewQueueTableTableFilterComposer f) f,
  ) {
    final $$ReviewQueueTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewQueueTable,
      getReferencedColumn: (t) => t.notificationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewQueueTableTableFilterComposer(
            $db: $db,
            $table: $db.reviewQueueTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotificationsTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOngoing => $composableBuilder(
    column: $table.isOngoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get priorityScore => $composableBuilder(
    column: $table.priorityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classifiedCategory => $composableBuilder(
    column: $table.classifiedCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleVersion => $composableBuilder(
    column: $table.ruleVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engineVersion => $composableBuilder(
    column: $table.engineVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extractedFeatures => $composableBuilder(
    column: $table.extractedFeatures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get policyScore => $composableBuilder(
    column: $table.policyScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reviewed => $composableBuilder(
    column: $table.reviewed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationsTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $NotificationsTableTable> {
  $$NotificationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get isOngoing =>
      $composableBuilder(column: $table.isOngoing, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<double> get priorityScore => $composableBuilder(
    column: $table.priorityScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get classifiedCategory => $composableBuilder(
    column: $table.classifiedCategory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<String> get ruleVersion => $composableBuilder(
    column: $table.ruleVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get engineVersion => $composableBuilder(
    column: $table.engineVersion,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Map<String, dynamic>?, String>
  get extractedFeatures => $composableBuilder(
    column: $table.extractedFeatures,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ReviewState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );

  GeneratedColumn<double> get policyScore => $composableBuilder(
    column: $table.policyScore,
    builder: (column) => column,
  );

  GeneratedColumn<double> get finalScore => $composableBuilder(
    column: $table.finalScore,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reviewed =>
      $composableBuilder(column: $table.reviewed, builder: (column) => column);

  GeneratedColumn<bool> get dismissed =>
      $composableBuilder(column: $table.dismissed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => column,
  );

  Expression<T> reviewQueueTableRefs<T extends Object>(
    Expression<T> Function($$ReviewQueueTableTableAnnotationComposer a) f,
  ) {
    final $$ReviewQueueTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewQueueTable,
      getReferencedColumn: (t) => t.notificationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewQueueTableTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewQueueTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotificationsTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $NotificationsTableTable,
          NotificationEntry,
          $$NotificationsTableTableFilterComposer,
          $$NotificationsTableTableOrderingComposer,
          $$NotificationsTableTableAnnotationComposer,
          $$NotificationsTableTableCreateCompanionBuilder,
          $$NotificationsTableTableUpdateCompanionBuilder,
          (NotificationEntry, $$NotificationsTableTableReferences),
          NotificationEntry,
          PrefetchHooks Function({bool reviewQueueTableRefs})
        > {
  $$NotificationsTableTableTableManager(
    _$AttentionDatabase db,
    $NotificationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> packageName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<bool> isOngoing = const Value.absent(),
                Value<String?> priority = const Value.absent(),
                Value<double?> priorityScore = const Value.absent(),
                Value<String?> classifiedCategory = const Value.absent(),
                Value<String?> explanation = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                Value<String?> ruleVersion = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> engineVersion = const Value.absent(),
                Value<Map<String, dynamic>?> extractedFeatures =
                    const Value.absent(),
                Value<ReviewState> state = const Value.absent(),
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<double?> policyScore = const Value.absent(),
                Value<double?> finalScore = const Value.absent(),
                Value<bool> reviewed = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> vectorClock = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationsTableCompanion(
                id: id,
                packageName: packageName,
                title: title,
                content: content,
                timestamp: timestamp,
                category: category,
                isOngoing: isOngoing,
                priority: priority,
                priorityScore: priorityScore,
                classifiedCategory: classifiedCategory,
                explanation: explanation,
                latencyMs: latencyMs,
                ruleVersion: ruleVersion,
                modelVersion: modelVersion,
                engineVersion: engineVersion,
                extractedFeatures: extractedFeatures,
                state: state,
                snoozedUntil: snoozedUntil,
                lastUpdated: lastUpdated,
                policyScore: policyScore,
                finalScore: finalScore,
                reviewed: reviewed,
                dismissed: dismissed,
                createdAt: createdAt,
                vectorClock: vectorClock,
                originDeviceId: originDeviceId,
                syncTimestamp: syncTimestamp,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String packageName,
                required String title,
                required String content,
                required int timestamp,
                Value<String?> category = const Value.absent(),
                Value<bool> isOngoing = const Value.absent(),
                Value<String?> priority = const Value.absent(),
                Value<double?> priorityScore = const Value.absent(),
                Value<String?> classifiedCategory = const Value.absent(),
                Value<String?> explanation = const Value.absent(),
                Value<int?> latencyMs = const Value.absent(),
                Value<String?> ruleVersion = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> engineVersion = const Value.absent(),
                Value<Map<String, dynamic>?> extractedFeatures =
                    const Value.absent(),
                required ReviewState state,
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<double?> policyScore = const Value.absent(),
                Value<double?> finalScore = const Value.absent(),
                Value<bool> reviewed = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> vectorClock = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationsTableCompanion.insert(
                id: id,
                packageName: packageName,
                title: title,
                content: content,
                timestamp: timestamp,
                category: category,
                isOngoing: isOngoing,
                priority: priority,
                priorityScore: priorityScore,
                classifiedCategory: classifiedCategory,
                explanation: explanation,
                latencyMs: latencyMs,
                ruleVersion: ruleVersion,
                modelVersion: modelVersion,
                engineVersion: engineVersion,
                extractedFeatures: extractedFeatures,
                state: state,
                snoozedUntil: snoozedUntil,
                lastUpdated: lastUpdated,
                policyScore: policyScore,
                finalScore: finalScore,
                reviewed: reviewed,
                dismissed: dismissed,
                createdAt: createdAt,
                vectorClock: vectorClock,
                originDeviceId: originDeviceId,
                syncTimestamp: syncTimestamp,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotificationsTableTable, NotificationEntry>(
                    table,
                  ),
                  $$NotificationsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({reviewQueueTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (reviewQueueTableRefs) db.reviewQueueTable,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (reviewQueueTableRefs)
                    await $_getPrefetchedData<
                      NotificationEntry,
                      $NotificationsTableTable,
                      ReviewQueueEntry
                    >(
                      currentTable: table,
                      referencedTable: $$NotificationsTableTableReferences
                          ._reviewQueueTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$NotificationsTableTableReferences(
                            db,
                            table,
                            p0,
                          ).reviewQueueTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.notificationId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NotificationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $NotificationsTableTable,
      NotificationEntry,
      $$NotificationsTableTableFilterComposer,
      $$NotificationsTableTableOrderingComposer,
      $$NotificationsTableTableAnnotationComposer,
      $$NotificationsTableTableCreateCompanionBuilder,
      $$NotificationsTableTableUpdateCompanionBuilder,
      (NotificationEntry, $$NotificationsTableTableReferences),
      NotificationEntry,
      PrefetchHooks Function({bool reviewQueueTableRefs})
    >;
typedef $$ReviewQueueTableTableCreateCompanionBuilder =
    ReviewQueueTableCompanion Function({
      Value<int> id,
      required String notificationId,
      required String priority,
      required DateTime enqueueTime,
      Value<DateTime?> expiryTime,
      required ReviewState status,
      Value<String?> vectorClock,
      Value<String?> originDeviceId,
      Value<DateTime?> syncTimestamp,
    });
typedef $$ReviewQueueTableTableUpdateCompanionBuilder =
    ReviewQueueTableCompanion Function({
      Value<int> id,
      Value<String> notificationId,
      Value<String> priority,
      Value<DateTime> enqueueTime,
      Value<DateTime?> expiryTime,
      Value<ReviewState> status,
      Value<String?> vectorClock,
      Value<String?> originDeviceId,
      Value<DateTime?> syncTimestamp,
    });

final class $$ReviewQueueTableTableReferences
    extends
        BaseReferences<
          _$AttentionDatabase,
          $ReviewQueueTableTable,
          ReviewQueueEntry
        > {
  $$ReviewQueueTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NotificationsTableTable _notificationIdTable(
    _$AttentionDatabase db,
  ) => db.notificationsTable.createAlias(
    'review_queue_table__notification_id__notifications_table__id',
  );

  $$NotificationsTableTableProcessedTableManager get notificationId {
    final $_column = $_itemColumn<String>('notification_id')!;

    final manager = $$NotificationsTableTableTableManager(
      $_db,
      $_db.notificationsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_notificationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewQueueTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $ReviewQueueTableTable> {
  $$ReviewQueueTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get enqueueTime => $composableBuilder(
    column: $table.enqueueTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiryTime => $composableBuilder(
    column: $table.expiryTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ReviewState, ReviewState, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$NotificationsTableTableFilterComposer get notificationId {
    final $$NotificationsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.notificationId,
      referencedTable: $db.notificationsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotificationsTableTableFilterComposer(
            $db: $db,
            $table: $db.notificationsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewQueueTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $ReviewQueueTableTable> {
  $$ReviewQueueTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get enqueueTime => $composableBuilder(
    column: $table.enqueueTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiryTime => $composableBuilder(
    column: $table.expiryTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotificationsTableTableOrderingComposer get notificationId {
    final $$NotificationsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.notificationId,
      referencedTable: $db.notificationsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotificationsTableTableOrderingComposer(
            $db: $db,
            $table: $db.notificationsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewQueueTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $ReviewQueueTableTable> {
  $$ReviewQueueTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<DateTime> get enqueueTime => $composableBuilder(
    column: $table.enqueueTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiryTime => $composableBuilder(
    column: $table.expiryTime,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ReviewState, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => column,
  );

  $$NotificationsTableTableAnnotationComposer get notificationId {
    final $$NotificationsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.notificationId,
          referencedTable: $db.notificationsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$NotificationsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.notificationsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ReviewQueueTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $ReviewQueueTableTable,
          ReviewQueueEntry,
          $$ReviewQueueTableTableFilterComposer,
          $$ReviewQueueTableTableOrderingComposer,
          $$ReviewQueueTableTableAnnotationComposer,
          $$ReviewQueueTableTableCreateCompanionBuilder,
          $$ReviewQueueTableTableUpdateCompanionBuilder,
          (ReviewQueueEntry, $$ReviewQueueTableTableReferences),
          ReviewQueueEntry,
          PrefetchHooks Function({bool notificationId})
        > {
  $$ReviewQueueTableTableTableManager(
    _$AttentionDatabase db,
    $ReviewQueueTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewQueueTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewQueueTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewQueueTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> notificationId = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<DateTime> enqueueTime = const Value.absent(),
                Value<DateTime?> expiryTime = const Value.absent(),
                Value<ReviewState> status = const Value.absent(),
                Value<String?> vectorClock = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
              }) => ReviewQueueTableCompanion(
                id: id,
                notificationId: notificationId,
                priority: priority,
                enqueueTime: enqueueTime,
                expiryTime: expiryTime,
                status: status,
                vectorClock: vectorClock,
                originDeviceId: originDeviceId,
                syncTimestamp: syncTimestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String notificationId,
                required String priority,
                required DateTime enqueueTime,
                Value<DateTime?> expiryTime = const Value.absent(),
                required ReviewState status,
                Value<String?> vectorClock = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
              }) => ReviewQueueTableCompanion.insert(
                id: id,
                notificationId: notificationId,
                priority: priority,
                enqueueTime: enqueueTime,
                expiryTime: expiryTime,
                status: status,
                vectorClock: vectorClock,
                originDeviceId: originDeviceId,
                syncTimestamp: syncTimestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewQueueTableTable, ReviewQueueEntry>(table),
                  $$ReviewQueueTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({notificationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (notificationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.notificationId,
                                referencedTable:
                                    $$ReviewQueueTableTableReferences
                                        ._notificationIdTable(db),
                                referencedColumn:
                                    $$ReviewQueueTableTableReferences
                                        ._notificationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewQueueTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $ReviewQueueTableTable,
      ReviewQueueEntry,
      $$ReviewQueueTableTableFilterComposer,
      $$ReviewQueueTableTableOrderingComposer,
      $$ReviewQueueTableTableAnnotationComposer,
      $$ReviewQueueTableTableCreateCompanionBuilder,
      $$ReviewQueueTableTableUpdateCompanionBuilder,
      (ReviewQueueEntry, $$ReviewQueueTableTableReferences),
      ReviewQueueEntry,
      PrefetchHooks Function({bool notificationId})
    >;
typedef $$RlhfRulesTableTableCreateCompanionBuilder =
    RlhfRulesTableCompanion Function({
      required String id,
      required String category,
      required String priority,
      required String conditionsJson,
      Value<bool> isDeleted,
      Value<String?> originDeviceId,
      Value<String?> vectorClock,
      Value<DateTime?> syncTimestamp,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$RlhfRulesTableTableUpdateCompanionBuilder =
    RlhfRulesTableCompanion Function({
      Value<String> id,
      Value<String> category,
      Value<String> priority,
      Value<String> conditionsJson,
      Value<bool> isDeleted,
      Value<String?> originDeviceId,
      Value<String?> vectorClock,
      Value<DateTime?> syncTimestamp,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RlhfRulesTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $RlhfRulesTableTable> {
  $$RlhfRulesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conditionsJson => $composableBuilder(
    column: $table.conditionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RlhfRulesTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $RlhfRulesTableTable> {
  $$RlhfRulesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conditionsJson => $composableBuilder(
    column: $table.conditionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RlhfRulesTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $RlhfRulesTableTable> {
  $$RlhfRulesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get conditionsJson => $composableBuilder(
    column: $table.conditionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vectorClock => $composableBuilder(
    column: $table.vectorClock,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncTimestamp => $composableBuilder(
    column: $table.syncTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RlhfRulesTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $RlhfRulesTableTable,
          RlhfRuleEntry,
          $$RlhfRulesTableTableFilterComposer,
          $$RlhfRulesTableTableOrderingComposer,
          $$RlhfRulesTableTableAnnotationComposer,
          $$RlhfRulesTableTableCreateCompanionBuilder,
          $$RlhfRulesTableTableUpdateCompanionBuilder,
          (
            RlhfRuleEntry,
            BaseReferences<
              _$AttentionDatabase,
              $RlhfRulesTableTable,
              RlhfRuleEntry
            >,
          ),
          RlhfRuleEntry,
          PrefetchHooks Function()
        > {
  $$RlhfRulesTableTableTableManager(
    _$AttentionDatabase db,
    $RlhfRulesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RlhfRulesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RlhfRulesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RlhfRulesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String> conditionsJson = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<String?> vectorClock = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RlhfRulesTableCompanion(
                id: id,
                category: category,
                priority: priority,
                conditionsJson: conditionsJson,
                isDeleted: isDeleted,
                originDeviceId: originDeviceId,
                vectorClock: vectorClock,
                syncTimestamp: syncTimestamp,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String category,
                required String priority,
                required String conditionsJson,
                Value<bool> isDeleted = const Value.absent(),
                Value<String?> originDeviceId = const Value.absent(),
                Value<String?> vectorClock = const Value.absent(),
                Value<DateTime?> syncTimestamp = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RlhfRulesTableCompanion.insert(
                id: id,
                category: category,
                priority: priority,
                conditionsJson: conditionsJson,
                isDeleted: isDeleted,
                originDeviceId: originDeviceId,
                vectorClock: vectorClock,
                syncTimestamp: syncTimestamp,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RlhfRulesTableTable, RlhfRuleEntry>(table),
                  BaseReferences<
                    _$AttentionDatabase,
                    $RlhfRulesTableTable,
                    RlhfRuleEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RlhfRulesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $RlhfRulesTableTable,
      RlhfRuleEntry,
      $$RlhfRulesTableTableFilterComposer,
      $$RlhfRulesTableTableOrderingComposer,
      $$RlhfRulesTableTableAnnotationComposer,
      $$RlhfRulesTableTableCreateCompanionBuilder,
      $$RlhfRulesTableTableUpdateCompanionBuilder,
      (
        RlhfRuleEntry,
        BaseReferences<
          _$AttentionDatabase,
          $RlhfRulesTableTable,
          RlhfRuleEntry
        >,
      ),
      RlhfRuleEntry,
      PrefetchHooks Function()
    >;
typedef $$OfflineSyncQueueTableTableCreateCompanionBuilder =
    OfflineSyncQueueTableCompanion Function({
      Value<int> id,
      required String payloadType,
      required String entityId,
      required String encryptedPayloadJson,
      Value<DateTime> createdAt,
      Value<bool> isSynced,
    });
typedef $$OfflineSyncQueueTableTableUpdateCompanionBuilder =
    OfflineSyncQueueTableCompanion Function({
      Value<int> id,
      Value<String> payloadType,
      Value<String> entityId,
      Value<String> encryptedPayloadJson,
      Value<DateTime> createdAt,
      Value<bool> isSynced,
    });

class $$OfflineSyncQueueTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $OfflineSyncQueueTableTable> {
  $$OfflineSyncQueueTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPayloadJson => $composableBuilder(
    column: $table.encryptedPayloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineSyncQueueTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $OfflineSyncQueueTableTable> {
  $$OfflineSyncQueueTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPayloadJson => $composableBuilder(
    column: $table.encryptedPayloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineSyncQueueTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $OfflineSyncQueueTableTable> {
  $$OfflineSyncQueueTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get encryptedPayloadJson => $composableBuilder(
    column: $table.encryptedPayloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);
}

class $$OfflineSyncQueueTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $OfflineSyncQueueTableTable,
          OfflineSyncQueueEntry,
          $$OfflineSyncQueueTableTableFilterComposer,
          $$OfflineSyncQueueTableTableOrderingComposer,
          $$OfflineSyncQueueTableTableAnnotationComposer,
          $$OfflineSyncQueueTableTableCreateCompanionBuilder,
          $$OfflineSyncQueueTableTableUpdateCompanionBuilder,
          (
            OfflineSyncQueueEntry,
            BaseReferences<
              _$AttentionDatabase,
              $OfflineSyncQueueTableTable,
              OfflineSyncQueueEntry
            >,
          ),
          OfflineSyncQueueEntry,
          PrefetchHooks Function()
        > {
  $$OfflineSyncQueueTableTableTableManager(
    _$AttentionDatabase db,
    $OfflineSyncQueueTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineSyncQueueTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflineSyncQueueTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineSyncQueueTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> payloadType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> encryptedPayloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
              }) => OfflineSyncQueueTableCompanion(
                id: id,
                payloadType: payloadType,
                entityId: entityId,
                encryptedPayloadJson: encryptedPayloadJson,
                createdAt: createdAt,
                isSynced: isSynced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String payloadType,
                required String entityId,
                required String encryptedPayloadJson,
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
              }) => OfflineSyncQueueTableCompanion.insert(
                id: id,
                payloadType: payloadType,
                entityId: entityId,
                encryptedPayloadJson: encryptedPayloadJson,
                createdAt: createdAt,
                isSynced: isSynced,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OfflineSyncQueueTableTable,
                    OfflineSyncQueueEntry
                  >(table),
                  BaseReferences<
                    _$AttentionDatabase,
                    $OfflineSyncQueueTableTable,
                    OfflineSyncQueueEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineSyncQueueTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $OfflineSyncQueueTableTable,
      OfflineSyncQueueEntry,
      $$OfflineSyncQueueTableTableFilterComposer,
      $$OfflineSyncQueueTableTableOrderingComposer,
      $$OfflineSyncQueueTableTableAnnotationComposer,
      $$OfflineSyncQueueTableTableCreateCompanionBuilder,
      $$OfflineSyncQueueTableTableUpdateCompanionBuilder,
      (
        OfflineSyncQueueEntry,
        BaseReferences<
          _$AttentionDatabase,
          $OfflineSyncQueueTableTable,
          OfflineSyncQueueEntry
        >,
      ),
      OfflineSyncQueueEntry,
      PrefetchHooks Function()
    >;
typedef $$FocusSessionsTableTableCreateCompanionBuilder =
    FocusSessionsTableCompanion Function({
      Value<int> id,
      required DateTime sessionStart,
      Value<DateTime?> sessionEnd,
      Value<int> interruptions,
      Value<bool> completion,
      required int duration,
    });
typedef $$FocusSessionsTableTableUpdateCompanionBuilder =
    FocusSessionsTableCompanion Function({
      Value<int> id,
      Value<DateTime> sessionStart,
      Value<DateTime?> sessionEnd,
      Value<int> interruptions,
      Value<bool> completion,
      Value<int> duration,
    });

class $$FocusSessionsTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $FocusSessionsTableTable> {
  $$FocusSessionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sessionStart => $composableBuilder(
    column: $table.sessionStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sessionEnd => $composableBuilder(
    column: $table.sessionEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interruptions => $composableBuilder(
    column: $table.interruptions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusSessionsTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $FocusSessionsTableTable> {
  $$FocusSessionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sessionStart => $composableBuilder(
    column: $table.sessionStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sessionEnd => $composableBuilder(
    column: $table.sessionEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interruptions => $composableBuilder(
    column: $table.interruptions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusSessionsTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $FocusSessionsTableTable> {
  $$FocusSessionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get sessionStart => $composableBuilder(
    column: $table.sessionStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sessionEnd => $composableBuilder(
    column: $table.sessionEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interruptions => $composableBuilder(
    column: $table.interruptions,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completion => $composableBuilder(
    column: $table.completion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);
}

class $$FocusSessionsTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $FocusSessionsTableTable,
          FocusSessionEntry,
          $$FocusSessionsTableTableFilterComposer,
          $$FocusSessionsTableTableOrderingComposer,
          $$FocusSessionsTableTableAnnotationComposer,
          $$FocusSessionsTableTableCreateCompanionBuilder,
          $$FocusSessionsTableTableUpdateCompanionBuilder,
          (
            FocusSessionEntry,
            BaseReferences<
              _$AttentionDatabase,
              $FocusSessionsTableTable,
              FocusSessionEntry
            >,
          ),
          FocusSessionEntry,
          PrefetchHooks Function()
        > {
  $$FocusSessionsTableTableTableManager(
    _$AttentionDatabase db,
    $FocusSessionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> sessionStart = const Value.absent(),
                Value<DateTime?> sessionEnd = const Value.absent(),
                Value<int> interruptions = const Value.absent(),
                Value<bool> completion = const Value.absent(),
                Value<int> duration = const Value.absent(),
              }) => FocusSessionsTableCompanion(
                id: id,
                sessionStart: sessionStart,
                sessionEnd: sessionEnd,
                interruptions: interruptions,
                completion: completion,
                duration: duration,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime sessionStart,
                Value<DateTime?> sessionEnd = const Value.absent(),
                Value<int> interruptions = const Value.absent(),
                Value<bool> completion = const Value.absent(),
                required int duration,
              }) => FocusSessionsTableCompanion.insert(
                id: id,
                sessionStart: sessionStart,
                sessionEnd: sessionEnd,
                interruptions: interruptions,
                completion: completion,
                duration: duration,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FocusSessionsTableTable, FocusSessionEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AttentionDatabase,
                    $FocusSessionsTableTable,
                    FocusSessionEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusSessionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $FocusSessionsTableTable,
      FocusSessionEntry,
      $$FocusSessionsTableTableFilterComposer,
      $$FocusSessionsTableTableOrderingComposer,
      $$FocusSessionsTableTableAnnotationComposer,
      $$FocusSessionsTableTableCreateCompanionBuilder,
      $$FocusSessionsTableTableUpdateCompanionBuilder,
      (
        FocusSessionEntry,
        BaseReferences<
          _$AttentionDatabase,
          $FocusSessionsTableTable,
          FocusSessionEntry
        >,
      ),
      FocusSessionEntry,
      PrefetchHooks Function()
    >;
typedef $$DailyBriefTableTableCreateCompanionBuilder =
    DailyBriefTableCompanion Function({
      Value<int> id,
      required String date,
      Value<int> notificationsReviewed,
      Value<int> actionsCompleted,
      Value<int> calendarEventsCreated,
      Value<int> remindersCreated,
      Value<int> archivedCount,
    });
typedef $$DailyBriefTableTableUpdateCompanionBuilder =
    DailyBriefTableCompanion Function({
      Value<int> id,
      Value<String> date,
      Value<int> notificationsReviewed,
      Value<int> actionsCompleted,
      Value<int> calendarEventsCreated,
      Value<int> remindersCreated,
      Value<int> archivedCount,
    });

class $$DailyBriefTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $DailyBriefTableTable> {
  $$DailyBriefTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notificationsReviewed => $composableBuilder(
    column: $table.notificationsReviewed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actionsCompleted => $composableBuilder(
    column: $table.actionsCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calendarEventsCreated => $composableBuilder(
    column: $table.calendarEventsCreated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindersCreated => $composableBuilder(
    column: $table.remindersCreated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archivedCount => $composableBuilder(
    column: $table.archivedCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyBriefTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $DailyBriefTableTable> {
  $$DailyBriefTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificationsReviewed => $composableBuilder(
    column: $table.notificationsReviewed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actionsCompleted => $composableBuilder(
    column: $table.actionsCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calendarEventsCreated => $composableBuilder(
    column: $table.calendarEventsCreated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindersCreated => $composableBuilder(
    column: $table.remindersCreated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archivedCount => $composableBuilder(
    column: $table.archivedCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyBriefTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $DailyBriefTableTable> {
  $$DailyBriefTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get notificationsReviewed => $composableBuilder(
    column: $table.notificationsReviewed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actionsCompleted => $composableBuilder(
    column: $table.actionsCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get calendarEventsCreated => $composableBuilder(
    column: $table.calendarEventsCreated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remindersCreated => $composableBuilder(
    column: $table.remindersCreated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get archivedCount => $composableBuilder(
    column: $table.archivedCount,
    builder: (column) => column,
  );
}

class $$DailyBriefTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $DailyBriefTableTable,
          DailyBriefEntry,
          $$DailyBriefTableTableFilterComposer,
          $$DailyBriefTableTableOrderingComposer,
          $$DailyBriefTableTableAnnotationComposer,
          $$DailyBriefTableTableCreateCompanionBuilder,
          $$DailyBriefTableTableUpdateCompanionBuilder,
          (
            DailyBriefEntry,
            BaseReferences<
              _$AttentionDatabase,
              $DailyBriefTableTable,
              DailyBriefEntry
            >,
          ),
          DailyBriefEntry,
          PrefetchHooks Function()
        > {
  $$DailyBriefTableTableTableManager(
    _$AttentionDatabase db,
    $DailyBriefTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyBriefTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyBriefTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyBriefTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> notificationsReviewed = const Value.absent(),
                Value<int> actionsCompleted = const Value.absent(),
                Value<int> calendarEventsCreated = const Value.absent(),
                Value<int> remindersCreated = const Value.absent(),
                Value<int> archivedCount = const Value.absent(),
              }) => DailyBriefTableCompanion(
                id: id,
                date: date,
                notificationsReviewed: notificationsReviewed,
                actionsCompleted: actionsCompleted,
                calendarEventsCreated: calendarEventsCreated,
                remindersCreated: remindersCreated,
                archivedCount: archivedCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String date,
                Value<int> notificationsReviewed = const Value.absent(),
                Value<int> actionsCompleted = const Value.absent(),
                Value<int> calendarEventsCreated = const Value.absent(),
                Value<int> remindersCreated = const Value.absent(),
                Value<int> archivedCount = const Value.absent(),
              }) => DailyBriefTableCompanion.insert(
                id: id,
                date: date,
                notificationsReviewed: notificationsReviewed,
                actionsCompleted: actionsCompleted,
                calendarEventsCreated: calendarEventsCreated,
                remindersCreated: remindersCreated,
                archivedCount: archivedCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyBriefTableTable, DailyBriefEntry>(table),
                  BaseReferences<
                    _$AttentionDatabase,
                    $DailyBriefTableTable,
                    DailyBriefEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyBriefTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $DailyBriefTableTable,
      DailyBriefEntry,
      $$DailyBriefTableTableFilterComposer,
      $$DailyBriefTableTableOrderingComposer,
      $$DailyBriefTableTableAnnotationComposer,
      $$DailyBriefTableTableCreateCompanionBuilder,
      $$DailyBriefTableTableUpdateCompanionBuilder,
      (
        DailyBriefEntry,
        BaseReferences<
          _$AttentionDatabase,
          $DailyBriefTableTable,
          DailyBriefEntry
        >,
      ),
      DailyBriefEntry,
      PrefetchHooks Function()
    >;
typedef $$PrivacyLedgerTableTableCreateCompanionBuilder =
    PrivacyLedgerTableCompanion Function({
      Value<int> id,
      required String date,
      Value<double> epsilonSpent,
      Value<double> deltaSpent,
      Value<int> queryCount,
      Value<DateTime> lastUpdated,
    });
typedef $$PrivacyLedgerTableTableUpdateCompanionBuilder =
    PrivacyLedgerTableCompanion Function({
      Value<int> id,
      Value<String> date,
      Value<double> epsilonSpent,
      Value<double> deltaSpent,
      Value<int> queryCount,
      Value<DateTime> lastUpdated,
    });

class $$PrivacyLedgerTableTableFilterComposer
    extends Composer<_$AttentionDatabase, $PrivacyLedgerTableTable> {
  $$PrivacyLedgerTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get epsilonSpent => $composableBuilder(
    column: $table.epsilonSpent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get deltaSpent => $composableBuilder(
    column: $table.deltaSpent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queryCount => $composableBuilder(
    column: $table.queryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PrivacyLedgerTableTableOrderingComposer
    extends Composer<_$AttentionDatabase, $PrivacyLedgerTableTable> {
  $$PrivacyLedgerTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get epsilonSpent => $composableBuilder(
    column: $table.epsilonSpent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get deltaSpent => $composableBuilder(
    column: $table.deltaSpent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queryCount => $composableBuilder(
    column: $table.queryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrivacyLedgerTableTableAnnotationComposer
    extends Composer<_$AttentionDatabase, $PrivacyLedgerTableTable> {
  $$PrivacyLedgerTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get epsilonSpent => $composableBuilder(
    column: $table.epsilonSpent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get deltaSpent => $composableBuilder(
    column: $table.deltaSpent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queryCount => $composableBuilder(
    column: $table.queryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );
}

class $$PrivacyLedgerTableTableTableManager
    extends
        RootTableManager<
          _$AttentionDatabase,
          $PrivacyLedgerTableTable,
          PrivacyLedgerEntry,
          $$PrivacyLedgerTableTableFilterComposer,
          $$PrivacyLedgerTableTableOrderingComposer,
          $$PrivacyLedgerTableTableAnnotationComposer,
          $$PrivacyLedgerTableTableCreateCompanionBuilder,
          $$PrivacyLedgerTableTableUpdateCompanionBuilder,
          (
            PrivacyLedgerEntry,
            BaseReferences<
              _$AttentionDatabase,
              $PrivacyLedgerTableTable,
              PrivacyLedgerEntry
            >,
          ),
          PrivacyLedgerEntry,
          PrefetchHooks Function()
        > {
  $$PrivacyLedgerTableTableTableManager(
    _$AttentionDatabase db,
    $PrivacyLedgerTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrivacyLedgerTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrivacyLedgerTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrivacyLedgerTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<double> epsilonSpent = const Value.absent(),
                Value<double> deltaSpent = const Value.absent(),
                Value<int> queryCount = const Value.absent(),
                Value<DateTime> lastUpdated = const Value.absent(),
              }) => PrivacyLedgerTableCompanion(
                id: id,
                date: date,
                epsilonSpent: epsilonSpent,
                deltaSpent: deltaSpent,
                queryCount: queryCount,
                lastUpdated: lastUpdated,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String date,
                Value<double> epsilonSpent = const Value.absent(),
                Value<double> deltaSpent = const Value.absent(),
                Value<int> queryCount = const Value.absent(),
                Value<DateTime> lastUpdated = const Value.absent(),
              }) => PrivacyLedgerTableCompanion.insert(
                id: id,
                date: date,
                epsilonSpent: epsilonSpent,
                deltaSpent: deltaSpent,
                queryCount: queryCount,
                lastUpdated: lastUpdated,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PrivacyLedgerTableTable, PrivacyLedgerEntry>(
                    table,
                  ),
                  BaseReferences<
                    _$AttentionDatabase,
                    $PrivacyLedgerTableTable,
                    PrivacyLedgerEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrivacyLedgerTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AttentionDatabase,
      $PrivacyLedgerTableTable,
      PrivacyLedgerEntry,
      $$PrivacyLedgerTableTableFilterComposer,
      $$PrivacyLedgerTableTableOrderingComposer,
      $$PrivacyLedgerTableTableAnnotationComposer,
      $$PrivacyLedgerTableTableCreateCompanionBuilder,
      $$PrivacyLedgerTableTableUpdateCompanionBuilder,
      (
        PrivacyLedgerEntry,
        BaseReferences<
          _$AttentionDatabase,
          $PrivacyLedgerTableTable,
          PrivacyLedgerEntry
        >,
      ),
      PrivacyLedgerEntry,
      PrefetchHooks Function()
    >;

class $AttentionDatabaseManager {
  final _$AttentionDatabase _db;
  $AttentionDatabaseManager(this._db);
  $$NotificationsTableTableTableManager get notificationsTable =>
      $$NotificationsTableTableTableManager(_db, _db.notificationsTable);
  $$ReviewQueueTableTableTableManager get reviewQueueTable =>
      $$ReviewQueueTableTableTableManager(_db, _db.reviewQueueTable);
  $$RlhfRulesTableTableTableManager get rlhfRulesTable =>
      $$RlhfRulesTableTableTableManager(_db, _db.rlhfRulesTable);
  $$OfflineSyncQueueTableTableTableManager get offlineSyncQueueTable =>
      $$OfflineSyncQueueTableTableTableManager(_db, _db.offlineSyncQueueTable);
  $$FocusSessionsTableTableTableManager get focusSessionsTable =>
      $$FocusSessionsTableTableTableManager(_db, _db.focusSessionsTable);
  $$DailyBriefTableTableTableManager get dailyBriefTable =>
      $$DailyBriefTableTableTableManager(_db, _db.dailyBriefTable);
  $$PrivacyLedgerTableTableTableManager get privacyLedgerTable =>
      $$PrivacyLedgerTableTableTableManager(_db, _db.privacyLedgerTable);
}
