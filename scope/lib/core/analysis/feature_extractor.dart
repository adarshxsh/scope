import 'dart:math' as math;

import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

/// Android metadata used by the deterministic feature extractor.
///
/// All fields are optional because Android notifications are often partial.
/// Missing values are encoded as zero in the final feature vector.
class AndroidNotificationMetadata {
  final int importance;
  final bool conversation;
  final int visibility;
  final bool ongoing;
  final bool foregroundService;
  final String notificationCategory;
  final String channelId;
  final String channelName;
  final bool containsAttachment;

  const AndroidNotificationMetadata({
    this.importance = 0,
    this.conversation = false,
    this.visibility = 0,
    this.ongoing = false,
    this.foregroundService = false,
    this.notificationCategory = '',
    this.channelId = '',
    this.channelName = '',
    this.containsAttachment = false,
  });

  factory AndroidNotificationMetadata.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AndroidNotificationMetadata();
    return AndroidNotificationMetadata(
      importance: _asInt(map['importance']),
      conversation: _asBool(map['conversation']),
      visibility: _asInt(map['visibility']),
      ongoing: _asBool(map['ongoing'] ?? map['isOngoing']),
      foregroundService: _asBool(map['foregroundService']),
      notificationCategory:
          (map['notificationCategory'] ?? map['category'] ?? '').toString(),
      channelId: (map['channelId'] ?? '').toString(),
      channelName: (map['channelName'] ?? '').toString(),
      containsAttachment: _asBool(map['containsAttachment']),
    );
  }
}

/// Platform-neutral notification input for deterministic feature extraction.
class NotificationFeatureInput {
  final String appName;
  final String packageName;
  final String title;
  final String body;
  final int timestampMillis;
  final AndroidNotificationMetadata android;

  const NotificationFeatureInput({
    required this.appName,
    required this.packageName,
    required this.title,
    required this.body,
    required this.timestampMillis,
    this.android = const AndroidNotificationMetadata(),
  });

  factory NotificationFeatureInput.fromAppNotification(
    AppNotification notification, {
    String appName = '',
    AndroidNotificationMetadata? android,
  }) {
    return NotificationFeatureInput(
      appName: appName,
      packageName: notification.packageName,
      title: notification.title,
      body: notification.content,
      timestampMillis: notification.timestamp,
      android:
          android ??
          AndroidNotificationMetadata(
            ongoing: notification.isOngoing,
            notificationCategory: notification.category ?? '',
          ),
    );
  }
}

/// Fixed-width numerical feature vector ready for TensorFlow Lite inference.
class FeatureVector {
  static List<String> featureNames = [
    'title_length',
    'body_length',
    'word_count',
    'uppercase_ratio',
    'digit_ratio',
    'emoji_count',
    'punctuation_count',
    'contains_question',
    'contains_exclamation',
    'contains_currency_symbol',
    'contains_money',
    'contains_otp',
    'contains_date',
    'contains_time',
    'contains_location',
    'contains_email',
    'contains_phone',
    'contains_link',
    'contains_attachment',
    'contains_percentage',
    'contains_discount',
    'contains_order_id',
    'contains_transaction_id',
    'contains_reference_number',
    'contains_tracking_number',
    'contains_coupon',
    'contains_meeting_link',
    'contains_deadline',
    'contains_security_keywords',
    'contains_payment_keywords',
    'contains_delivery_keywords',
    'contains_work_keywords',
    'contains_social_keywords',
    'contains_system_keywords',
    'importance',
    'conversation',
    'visibility',
    'ongoing',
    'foreground_service',
    'notification_category',
    'channel_id',
    'channel_name',
    'timestamp_hour',
    'day_of_week',
    'requires_action',
    'is_recurring',
    'is_promotion',
    'is_duplicate_candidate',
    'deadline_exists',
    'deadline_minutes_remaining',
    'amount',
    'currency',
    'otp_length',
    'merchant_present',
    'person_present',
    'city_present',
    'train_present',
    'flight_present',
    'order_present',
    'transaction_present',
    'intent_id',
    'notification_type_id',
    'category_id',
  ];

  static int get size => featureNames.length;

  final List<double> values;
  final List<String> _names;

  FeatureVector(Iterable<double> values, {List<String>? names})
      : values = List.unmodifiable(values),
        _names = List.unmodifiable(names ?? featureNames) {
    if (this.values.length != _names.length) {
      throw ArgumentError.value(
        this.values.length,
        'values.length',
        'FeatureVector must contain exactly ${_names.length} values.',
      );
    }
    if (this.values.any((value) => value.isNaN || value.isInfinite)) {
      throw ArgumentError('FeatureVector cannot contain NaN or infinity.');
    }
  }

  List<double> toList() => List<double>.from(values, growable: false);

  Map<String, double> toNamedMap() => {
        for (var i = 0; i < _names.length; i++) _names[i]: values[i],
      };

  double? getValue(String name) {
    final index = _names.indexOf(name);
    if (index == -1) return null;
    return values[index];
  }

  double operator [](String name) {
    final val = getValue(name);
    if (val == null) {
      throw ArgumentError('Feature "$name" not found in FeatureVector.');
    }
    return val;
  }
}

/// Deterministic notification feature extraction for TFLite inference.
///
/// This class intentionally uses only regular expressions, keyword dictionaries,
/// fixed mappings, and stable hashing. It never calls an AI model.
class FeatureExtractor {
  static final RegExp _wordRegex = RegExp(r"[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)?");
  static final RegExp _upperRegex = RegExp(r'[A-Z]');
  static final RegExp _letterRegex = RegExp(r'[A-Za-z]');
  static final RegExp _digitRegex = RegExp(r'\d');
  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );
  static final RegExp _punctuationRegex = RegExp(r'[!-/:-@[-`{-~]');
  static final RegExp _currencySymbolRegex = RegExp(r'[₹$€£¥₽₩₦₱]');
  static final RegExp _amountRegex = RegExp(
    r'(?:₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|usd|eur|gbp|aed)',
    caseSensitive: false,
  );
  static final RegExp _otpRegex = RegExp(r'\b\d{4,8}\b');
  static final RegExp _dateRegex = RegExp(
    r'\b(?:\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{1,2}\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*|(?:today|tomorrow|tonight))\b',
    caseSensitive: false,
  );
  static final RegExp _timeRegex = RegExp(
    r'\b(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:am|pm)?\b',
    caseSensitive: false,
  );
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );
  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
    caseSensitive: false,
  );
  static final RegExp _urlRegex = RegExp(
    r'\b(?:https?:\/\/|www\.)[^\s]+|\b[A-Za-z0-9.-]+\.(?:com|org|net|in|io|dev|app|co)\b',
    caseSensitive: false,
  );
  static final RegExp _percentageRegex = RegExp(
    r'\b\d+(?:\.\d+)?\s*%|\b\d+\s*percent\b',
    caseSensitive: false,
  );
  static final RegExp _orderIdRegex = RegExp(
    r'\b(?:order|ord)[\s#:.-]*[A-Z0-9-]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _transactionIdRegex = RegExp(
    r'\b(?:txn|txnid|transaction|utr|upi)[\s#:.-]*[A-Z0-9-]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _referenceNumberRegex = RegExp(
    r'\b(?:ref|reference)[\s#:.-]*(?:no\.?|number)?[\s#:.-]*[A-Z0-9-]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _trackingNumberRegex = RegExp(
    r'\b(?:tracking|awb|shipment)[\s#:.-]*[A-Z0-9-]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _couponRegex = RegExp(
    r'\b(?:coupon|promo code|voucher|code)\s*[:#-]?\s*[A-Z0-9]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _meetingLinkRegex = RegExp(
    r'\b(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|webex\.com)\b',
    caseSensitive: false,
  );
  static final RegExp _relativeDeadlineRegex = RegExp(
    r'\bin\s+(\d{1,4})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
    caseSensitive: false,
  );

  static const Set<String> _moneyWords = {
    'paid',
    'payment',
    'debited',
    'credited',
    'spent',
    'refund',
    'balance',
    'invoice',
    'bill',
    'salary',
    'cashback',
    'bank',
    'upi',
    'wallet',
  };
  static const Set<String> _otpWords = {
    'otp',
    'verification',
    'verify',
    'code',
    'pin',
    'password',
    '2fa',
  };
  static const Set<String> _locationWords = {
    'location',
    'address',
    'near',
    'arrived',
    'reached',
    'venue',
    'gate',
    'mumbai',
    'delhi',
    'bengaluru',
    'bangalore',
    'chennai',
    'hyderabad',
    'pune',
    'kolkata',
    'ahmedabad',
    'jaipur',
    'lucknow',
    'goa',
  };
  static const Set<String> _discountWords = {
    'discount',
    'sale',
    'offer',
    'deal',
    'cashback',
    'save',
    'off',
  };
  static const Set<String> _deadlineWords = {
    'deadline',
    'due',
    'expires',
    'expire',
    'closing',
    'closes',
    'last',
    'today',
    'tomorrow',
    'tonight',
    'urgent',
    'left',
    'reminder',
  };
  static const Set<String> _securityWords = {
    'security',
    'login',
    'password',
    'otp',
    'verification',
    'verify',
    'device',
    'blocked',
    'suspicious',
    'alert',
  };
  static const Set<String> _paymentWords = {
    'payment',
    'paid',
    'debited',
    'credited',
    'upi',
    'card',
    'bank',
    'wallet',
    'invoice',
    'bill',
    'refund',
    'transaction',
  };
  static const Set<String> _deliveryWords = {
    'delivery',
    'delivered',
    'shipment',
    'shipped',
    'courier',
    'tracking',
    'arriving',
    'out for delivery',
    'pickup',
    'order',
  };
  static const Set<String> _workWords = {
    'meeting',
    'calendar',
    'deadline',
    'task',
    'project',
    'standup',
    'interview',
    'review',
    'document',
    'shared',
  };
  static const Set<String> _socialWords = {
    'liked',
    'commented',
    'followed',
    'mentioned',
    'message',
    'dm',
    'friend',
    'story',
    'tagged',
    'reply',
  };
  static const Set<String> _systemWords = {
    'download',
    'upload',
    'sync',
    'backup',
    'update',
    'battery',
    'storage',
    'foreground',
    'running',
    'connected',
  };
  static const Set<String> _actionWords = {
    'approve',
    'confirm',
    'verify',
    'pay',
    'reply',
    'respond',
    'complete',
    'submit',
    'review',
    'sign',
    'join',
    'call',
  };
  static const Set<String> _recurringWords = {
    'daily',
    'weekly',
    'monthly',
    'renewal',
    'subscription',
    'reminder',
    'recurring',
    'autopay',
  };
  static const Set<String> _merchantWords = {
    'amazon',
    'flipkart',
    'swiggy',
    'zomato',
    'uber',
    'ola',
    'paytm',
    'phonepe',
    'google pay',
    'hdfc',
    'icici',
    'sbi',
    'axis',
  };
  static const Set<String> _personWords = {
    'mom',
    'dad',
    'sir',
    'maam',
    'ma\'am',
    'friend',
    'manager',
    'doctor',
    'teacher',
    'professor',
  };
  static const Set<String> _cityWords = {
    'mumbai',
    'delhi',
    'bengaluru',
    'bangalore',
    'chennai',
    'hyderabad',
    'pune',
    'kolkata',
    'ahmedabad',
    'jaipur',
    'lucknow',
    'goa',
  };
  static const Set<String> _trainWords = {'train', 'pnr', 'irctc', 'platform'};
  static const Set<String> _flightWords = {
    'flight',
    'boarding',
    'gate',
    'pnr',
    'terminal',
  };

  static const Map<String, int> _categoryIds = {
    '': 0,
    'alarm': 1,
    'call': 2,
    'email': 3,
    'err': 4,
    'event': 5,
    'msg': 6,
    'navigation': 7,
    'promo': 8,
    'progress': 9,
    'recommendation': 10,
    'reminder': 11,
    'service': 12,
    'social': 13,
    'status': 14,
    'sys': 15,
    'transport': 16,
  };

  static const Map<String, int> _currencyIds = {
    '': 0,
    'INR': 1,
    'USD': 2,
    'EUR': 3,
    'GBP': 4,
    'JPY': 5,
    'AED': 6,
  };

  /// Normalize raw text for clean feature extraction.
  static String normalize(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Compatibility API: extracts structured entities used by the policy layer.
  static ExtractedFeatures extract({
    required String title,
    required String content,
  }) {
    final combined = normalize('$title $content');

    return ExtractedFeatures(
      otp: _extractOtp(combined),
      amount: _extractAmount(combined),
      hasDeadline: _containsKeyword(combined.toLowerCase(), _deadlineWords),
      urls: _extractUrls(combined),
      emails: _extractEmails(combined),
      phoneNumbers: _extractPhoneNumbers(combined),
    );
  }

  /// Extracts a fixed-width numerical feature vector from an app notification.
  static List<double> extractFromAppNotification(
    AppNotification notification, {
    String appName = '',
    AndroidNotificationMetadata? android,
    List<String>? targetFeatureNames,
  }) {
    return extractVector(
      NotificationFeatureInput.fromAppNotification(
        notification,
        appName: appName,
        android: android,
      ),
      targetFeatureNames: targetFeatureNames,
    ).toList();
  }

  /// Extracts a fixed-width numerical feature vector from normalized input.
  static FeatureVector extractVector(
    NotificationFeatureInput notification, {
    List<String>? targetFeatureNames,
  }) {
    final title = normalize(notification.title);
    final body = normalize(notification.body);
    final combined = normalize('$title $body');
    final lower = combined.toLowerCase();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      notification.timestampMillis,
      isUtc: true,
    );

    final textUnitCount = math.max(combined.runes.length, 1);
    final letters = _letterRegex.allMatches(combined).length;
    final uppercase = _upperRegex.allMatches(combined).length;
    final digits = _digitRegex.allMatches(combined).length;
    final otp = _extractOtp(combined);
    final amount = _extractAmount(combined) ?? 0.0;
    final currency = _extractCurrency(combined);
    final containsDeadline = _containsKeyword(lower, _deadlineWords);
    final isPromotion =
        _containsKeyword(lower, _discountWords) ||
        _percentageRegex.hasMatch(lower) ||
        _couponRegex.hasMatch(combined);
    final containsOrder =
        _orderIdRegex.hasMatch(combined) ||
        _containsAnyPhrase(lower, const ['order placed', 'order confirmed']);
    final containsTransaction =
        _transactionIdRegex.hasMatch(combined) ||
        _containsKeyword(lower, _paymentWords);
    final notificationCategoryId = _categoryId(
      notification.android.notificationCategory,
      lower,
    );
    final intentId = _intentId(lower);
    final notificationTypeId = _notificationTypeId(
      notification.packageName,
      notification.android.notificationCategory,
      lower,
    );
    final categoryId = _semanticCategoryId(
      lower,
      notificationCategoryId,
      intentId,
    );

    final featureMap = <String, double>{
      'title_length': title.runes.length.toDouble(),
      'body_length': body.runes.length.toDouble(),
      'word_count': _wordRegex.allMatches(combined).length.toDouble(),
      'uppercase_ratio': letters == 0 ? 0.0 : uppercase / letters,
      'digit_ratio': digits / textUnitCount,
      'emoji_count': _emojiRegex.allMatches(combined).length.toDouble(),
      'punctuation_count': _punctuationRegex.allMatches(combined).length.toDouble(),
      'contains_question': _bool(combined.contains('?')),
      'contains_exclamation': _bool(combined.contains('!')),
      'contains_currency_symbol': _bool(_currencySymbolRegex.hasMatch(combined)),
      'contains_money': _bool(
        _amountRegex.hasMatch(combined) || _containsKeyword(lower, _moneyWords),
      ),
      'contains_otp': _bool(otp != null),
      'contains_date': _bool(_dateRegex.hasMatch(combined)),
      'contains_time': _bool(_timeRegex.hasMatch(combined)),
      'contains_location': _bool(_containsKeyword(lower, _locationWords)),
      'contains_email': _bool(_emailRegex.hasMatch(combined)),
      'contains_phone': _bool(_phoneRegex.hasMatch(combined)),
      'contains_link': _bool(_urlRegex.hasMatch(combined)),
      'contains_attachment': _bool(
        notification.android.containsAttachment || _containsAttachment(lower),
      ),
      'contains_percentage': _bool(_percentageRegex.hasMatch(combined)),
      'contains_discount': _bool(isPromotion),
      'is_promotion': _bool(isPromotion),
      'contains_order_id': _bool(containsOrder),
      'contains_transaction_id': _bool(containsTransaction),
      'contains_reference_number': _bool(_referenceNumberRegex.hasMatch(combined)),
      'contains_tracking_number': _bool(_trackingNumberRegex.hasMatch(combined)),
      'contains_coupon': _bool(_couponRegex.hasMatch(combined)),
      'contains_meeting_link': _bool(_meetingLinkRegex.hasMatch(combined)),
      'contains_deadline': _bool(containsDeadline),
      'contains_security_keywords': _bool(_containsKeyword(lower, _securityWords)),
      'contains_payment_keywords': _bool(_containsKeyword(lower, _paymentWords)),
      'contains_delivery_keywords': _bool(_containsKeyword(lower, _deliveryWords)),
      'contains_work_keywords': _bool(_containsKeyword(lower, _workWords)),
      'contains_social_keywords': _bool(_containsKeyword(lower, _socialWords)),
      'contains_system_keywords': _bool(_containsKeyword(lower, _systemWords)),
      'importance': notification.android.importance.toDouble(),
      'conversation': _bool(notification.android.conversation),
      'visibility': notification.android.visibility.toDouble(),
      'ongoing': _bool(notification.android.ongoing),
      'foreground_service': _bool(notification.android.foregroundService),
      'notification_category': notificationCategoryId.toDouble(),
      'channel_id': _stableBucket(notification.android.channelId).toDouble(),
      'channel_name': _stableBucket(notification.android.channelName).toDouble(),
      'timestamp_hour': timestamp.hour.toDouble(),
      'day_of_week': timestamp.weekday.toDouble(),
      'requires_action': _bool(_containsKeyword(lower, _actionWords)),
      'is_recurring': _bool(_containsKeyword(lower, _recurringWords)),
      'is_duplicate_candidate': _bool(_isDuplicateCandidate(lower)),
      'deadline_exists': _bool(containsDeadline),
      'deadline_minutes_remaining': _deadlineMinutesRemaining(lower).toDouble(),
      'amount': amount,
      'currency': (_currencyIds[currency] ?? 0).toDouble(),
      'otp_length': (otp?.length ?? 0).toDouble(),
      'merchant_present': _bool(
        _containsKeyword(lower, _merchantWords) ||
            _merchantAfterAmount(combined),
      ),
      'person_present': _bool(
        _containsKeyword(lower, _personWords) || _looksLikePersonTitle(title),
      ),
      'city_present': _bool(_containsKeyword(lower, _cityWords)),
      'train_present': _bool(_containsKeyword(lower, _trainWords)),
      'flight_present': _bool(_containsKeyword(lower, _flightWords)),
      'order_present': _bool(containsOrder),
      'transaction_present': _bool(containsTransaction),
      'intent_id': intentId.toDouble(),
      'notification_type_id': notificationTypeId.toDouble(),
      'category_id': categoryId.toDouble(),
    };

    final namesToUse = targetFeatureNames ?? FeatureVector.featureNames;
    final values = namesToUse.map((name) => featureMap[name] ?? 0.0).toList();

    return FeatureVector(values, names: namesToUse);
  }

  static String? _extractOtp(String text) {
    if (!_containsKeyword(text.toLowerCase(), _otpWords)) return null;
    for (final match in _otpRegex.allMatches(text)) {
      final value = match.group(0);
      if (value == null) continue;
      final number = int.tryParse(value);
      if (number != null && number >= 2020 && number <= 2030) continue;
      return value;
    }
    return null;
  }

  static double? _extractAmount(String text) {
    final match = _amountRegex.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1) ?? match.group(2);
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', ''));
  }

  static String _extractCurrency(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('₹') || lower.contains('rs') || lower.contains('inr')) {
      return 'INR';
    }
    if (lower.contains(r'$') || lower.contains('usd')) return 'USD';
    if (lower.contains('€') || lower.contains('eur')) return 'EUR';
    if (lower.contains('£') || lower.contains('gbp')) return 'GBP';
    if (lower.contains('¥') || lower.contains('jpy')) return 'JPY';
    if (lower.contains('aed')) return 'AED';
    return '';
  }

  static List<String> _extractUrls(String text) {
    return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static List<String> _extractEmails(String text) {
    return _emailRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static List<String> _extractPhoneNumbers(String text) {
    return _phoneRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static bool _containsAttachment(String lower) {
    return _containsAnyPhrase(lower, const [
      'attachment',
      'attached',
      'file',
      'photo',
      'image',
      'pdf',
      'document',
    ]);
  }

  static bool _merchantAfterAmount(String text) {
    return RegExp(
      r'\b(?:at|from|to)\s+[A-Z][A-Za-z0-9&.\-]{2,}',
    ).hasMatch(text);
  }

  static bool _looksLikePersonTitle(String title) {
    final words = title.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    if (words.length > 3 || words.isEmpty) return false;
    return words.every((word) => RegExp(r'^[A-Z][a-z]+$').hasMatch(word));
  }

  static int _deadlineMinutesRemaining(String lower) {
    final match = _relativeDeadlineRegex.firstMatch(lower);
    if (match == null) {
      if (lower.contains('today') || lower.contains('tonight')) return 0;
      if (lower.contains('tomorrow')) return 1440;
      return -1;
    }
    final amount = int.tryParse(match.group(1) ?? '') ?? 0;
    final unit = match.group(2) ?? '';
    if (unit.startsWith('min')) return amount;
    if (unit.startsWith('hour') || unit.startsWith('hr')) return amount * 60;
    return amount * 1440;
  }

  static int _categoryId(String category, String lower) {
    final normalized = category.trim().toLowerCase();
    if (_categoryIds.containsKey(normalized)) return _categoryIds[normalized]!;
    if (normalized.isNotEmpty) return _stableBucket(normalized, buckets: 128);
    if (_containsKeyword(lower, _paymentWords)) return _categoryIds['status']!;
    if (_containsKeyword(lower, _socialWords)) return _categoryIds['social']!;
    if (_containsKeyword(lower, _deliveryWords)) {
      return _categoryIds['transport']!;
    }
    if (_containsKeyword(lower, _discountWords)) return _categoryIds['promo']!;
    return 0;
  }

  static int _intentId(String lower) {
    if (_containsKeyword(lower, _actionWords)) return 1;
    if (_meetingLinkRegex.hasMatch(lower) || lower.contains('join')) return 2;
    if (_containsKeyword(lower, _paymentWords)) return 3;
    if (_containsKeyword(lower, _deliveryWords)) return 4;
    if (_containsKeyword(lower, _securityWords)) return 5;
    if (_containsKeyword(lower, _discountWords)) return 6;
    if (_containsKeyword(lower, _workWords)) return 7;
    return 0;
  }

  static int _notificationTypeId(
    String packageName,
    String category,
    String lower,
  ) {
    final package = packageName.toLowerCase();
    final normalizedCategory = category.toLowerCase();
    if (normalizedCategory == 'msg' || package.contains('whatsapp')) return 1;
    if (normalizedCategory == 'email' || package.contains('gmail')) return 2;
    if (_containsKeyword(lower, _paymentWords)) return 3;
    if (_containsKeyword(lower, _deliveryWords)) return 4;
    if (_containsKeyword(lower, _discountWords)) return 5;
    if (_containsKeyword(lower, _systemWords)) return 6;
    if (_containsKeyword(lower, _workWords)) return 7;
    return 0;
  }

  static int _semanticCategoryId(
    String lower,
    int androidCategoryId,
    int intentId,
  ) {
    if (_containsKeyword(lower, _paymentWords)) return 1;
    if (_containsKeyword(lower, _securityWords)) return 2;
    if (_containsKeyword(lower, _deliveryWords)) return 3;
    if (_containsKeyword(lower, _workWords)) return 4;
    if (_containsKeyword(lower, _socialWords)) return 5;
    if (_containsKeyword(lower, _discountWords)) return 6;
    if (androidCategoryId > 0) return androidCategoryId + 100;
    return intentId;
  }

  static bool _isDuplicateCandidate(String lower) {
    final words = _wordRegex
        .allMatches(lower)
        .map((match) => match.group(0)!)
        .where((word) => word.length > 2)
        .toList();
    if (words.length < 3) return false;
    final uniqueCount = words.toSet().length;
    return uniqueCount / words.length <= 0.6 ||
        _containsAnyPhrase(lower, const [
          'reminder',
          'still running',
          'syncing',
        ]);
  }

  static bool _containsKeyword(String lowerText, Set<String> words) {
    for (final word in words) {
      if (word.contains(' ')) {
        if (lowerText.contains(word)) return true;
      } else if (RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(lowerText)) {
        return true;
      }
    }
    return false;
  }

  static bool _containsAnyPhrase(String lowerText, List<String> phrases) {
    return phrases.any(lowerText.contains);
  }

  static int _stableBucket(String value, {int buckets = 1024}) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return (hash % buckets) + 1;
  }

  static double _bool(bool value) => value ? 1.0 : 0.0;
}
