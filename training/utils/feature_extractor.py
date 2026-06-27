"""Deterministic notification feature extraction matching the Dart FeatureExtractor."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

# Regular Expressions
_wordRegex = re.compile(r"[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)?")
_upperRegex = re.compile(r'[A-Z]')
_letterRegex = re.compile(r'[A-Za-z]')
_digitRegex = re.compile(r'\d')
_emojiRegex = re.compile(r'[\U0001f300-\U0001faff\u2600-\u27bf]')
_punctuationRegex = re.compile(r'[!-/:-@[-`{-~]')
_currencySymbolRegex = re.compile(r'[₹$€£¥₽₩₦₱]')
_amountRegex = re.compile(
    r'(?:₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|usd|eur|gbp|aed)',
    re.IGNORECASE,
)
_otpRegex = re.compile(r'\b\d{4,8}\b')
_dateRegex = re.compile(
    r'\b(?:\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{1,2}\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*|(?:today|tomorrow|tonight))\b',
    re.IGNORECASE,
)
_timeRegex = re.compile(
    r'\b(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:am|pm)?\b',
    re.IGNORECASE,
)
_emailRegex = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')
_phoneRegex = re.compile(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
    re.IGNORECASE,
)
_urlRegex = re.compile(
    r'\b(?:https?:\/\/|www\.)[^\s]+|\b[A-Za-z0-9.-]+\.(?:com|org|net|in|io|dev|app|co)\b',
    re.IGNORECASE,
)
_percentageRegex = re.compile(
    r'\b\d+(?:\.\d+)?\s*%|\b\d+\s*percent\b',
    re.IGNORECASE,
)
_orderIdRegex = re.compile(
    r'\b(?:order|ord)[\s#:.-]*[A-Z0-9-]{4,}\b',
    re.IGNORECASE,
)
_transactionIdRegex = re.compile(
    r'\b(?:txn|txnid|transaction|utr|upi)[\s#:.-]*[A-Z0-9-]{4,}\b',
    re.IGNORECASE,
)
_referenceNumberRegex = re.compile(
    r'\b(?:ref|reference)[\s#:.-]*(?:no\.?|number)?[\s#:.-]*[A-Z0-9-]{4,}\b',
    re.IGNORECASE,
)
_trackingNumberRegex = re.compile(
    r'\b(?:tracking|awb|shipment)[\s#:.-]*[A-Z0-9-]{4,}\b',
    re.IGNORECASE,
)
_couponRegex = re.compile(
    r'\b(?:coupon|promo code|voucher|code)\s*[:#-]?\s*[A-Z0-9]{4,}\b',
    re.IGNORECASE,
)
_meetingLinkRegex = re.compile(
    r'\b(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|webex\.com)\b',
    re.IGNORECASE,
)
_relativeDeadlineRegex = re.compile(
    r'\bin\s+(\d{1,4})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
    re.IGNORECASE,
)

# Constants
_moneyWords = {
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
}
_otpWords = {
    'otp',
    'verification',
    'verify',
    'code',
    'pin',
    'password',
    '2fa',
}
_locationWords = {
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
}
_discountWords = {
    'discount',
    'sale',
    'offer',
    'deal',
    'cashback',
    'save',
    'off',
}
_deadlineWords = {
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
}
_securityWords = {
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
}
_paymentWords = {
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
}
_deliveryWords = {
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
}
_workWords = {
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
}
_socialWords = {
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
}
_systemWords = {
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
}
_actionWords = {
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
}
_recurringWords = {
    'daily',
    'weekly',
    'monthly',
    'renewal',
    'subscription',
    'reminder',
    'recurring',
    'autopay',
}
_merchantWords = {
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
}
_personWords = {
    'mom',
    'dad',
    'sir',
    'maam',
    "ma'am",
    'friend',
    'manager',
    'doctor',
    'teacher',
    'professor',
}
_cityWords = {
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
}
_trainWords = {'train', 'pnr', 'irctc', 'platform'}
_flightWords = {
    'flight',
    'boarding',
    'gate',
    'pnr',
    'terminal',
}

_categoryIds = {
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
}

_currencyIds = {
    '': 0,
    'INR': 1,
    'USD': 2,
    'EUR': 3,
    'GBP': 4,
    'JPY': 5,
    'AED': 6,
}


def normalize(text: str) -> str:
    return " ".join(text.strip().split())


def contains_keyword(lower_text: str, words: set[str]) -> bool:
    for word in words:
        if ' ' in word:
            if word in lower_text:
                return True
        else:
            pattern = rf"\b{re.escape(word)}\b"
            if re.search(pattern, lower_text):
                return True
    return False


def contains_any_phrase(lower_text: str, phrases: list[str]) -> bool:
    return any(phrase in lower_text for phrase in phrases)


def stable_bucket(value: str, buckets: int = 1024) -> int:
    normalized = value.strip().lower()
    if not normalized:
        return 0
    code_units = []
    for c in normalized:
        b = c.encode('utf-16le')
        for i in range(0, len(b), 2):
            code_units.append(int.from_bytes(b[i:i+2], byteorder='little'))
    
    hash_val = 0x811c9dc5
    for unit in code_units:
        hash_val ^= unit
        hash_val = (hash_val * 0x01000193) & 0xffffffff
    return (hash_val % buckets) + 1


def extract_otp(text: str) -> str | None:
    if not contains_keyword(text.lower(), _otpWords):
        return None
    for match in _otpRegex.finditer(text):
        value = match.group(0)
        if value is None:
            continue
        try:
            number = int(value)
        except ValueError:
            continue
        if 2020 <= number <= 2030:
            continue
        return value
    return None


def extract_amount(text: str) -> float | None:
    match = _amountRegex.search(text)
    if not match:
        return None
    raw = match.group(1) or match.group(2)
    if not raw:
        return None
    try:
        return float(raw.replace(',', ''))
    except ValueError:
        return None


def extract_currency(text: str) -> str:
    lower = text.lower()
    if '₹' in lower or 'rs' in lower or 'inr' in lower:
        return 'INR'
    if '$' in lower or 'usd' in lower:
        return 'USD'
    if '€' in lower or 'eur' in lower:
        return 'EUR'
    if '£' in lower or 'gbp' in lower:
        return 'GBP'
    if '¥' in lower or 'jpy' in lower:
        return 'JPY'
    if 'aed' in lower:
        return 'AED'
    return ''


def is_duplicate_candidate(lower: str) -> bool:
    words = [m.group(0) for m in _wordRegex.finditer(lower)]
    words = [w for w in words if len(w) > 2]
    if len(words) < 3:
        return False
    unique_count = len(set(words))
    if unique_count / len(words) <= 0.6:
        return True
    return contains_any_phrase(lower, ['reminder', 'still running', 'syncing'])


def merchant_after_amount(text: str) -> bool:
    return bool(re.search(r'\b(?:at|from|to)\s+[A-Z][A-Za-z0-9&.\-]{2,}', text))


def looks_like_person_title(title: str) -> bool:
    words = [word for word in title.split() if word]
    if len(words) > 3 or len(words) == 0:
        return False
    return all(re.match(r'^[A-Z][a-z]+$', word) for word in words)


def deadline_minutes_remaining(lower: str) -> int:
    match = _relativeDeadlineRegex.search(lower)
    if not match:
        if 'today' in lower or 'tonight' in lower:
            return 0
        if 'tomorrow' in lower:
            return 1440
        return -1
    try:
        amount = int(match.group(1))
    except ValueError:
        amount = 0
    unit = match.group(2) or ''
    if unit.startswith('min'):
        return amount
    if unit.startswith('hour') or unit.startswith('hr'):
        return amount * 60
    return amount * 1440


def get_category_id(category: str, lower: str) -> int:
    normalized = category.strip().lower()
    if normalized in _categoryIds:
        return _categoryIds[normalized]
    if normalized:
        return stable_bucket(normalized, buckets=128)
    if contains_keyword(lower, _paymentWords):
        return _categoryIds['status']
    if contains_keyword(lower, _socialWords):
        return _categoryIds['social']
    if contains_keyword(lower, _deliveryWords):
        return _categoryIds['transport']
    if contains_keyword(lower, _discountWords):
        return _categoryIds['promo']
    return 0


def get_intent_id(lower: str) -> int:
    if contains_keyword(lower, _actionWords):
        return 1
    if _meetingLinkRegex.search(lower) or 'join' in lower:
        return 2
    if contains_keyword(lower, _paymentWords):
        return 3
    if contains_keyword(lower, _deliveryWords):
        return 4
    if contains_keyword(lower, _securityWords):
        return 5
    if contains_keyword(lower, _discountWords):
        return 6
    if contains_keyword(lower, _workWords):
        return 7
    return 0


def get_notification_type_id(package_name: str, category: str, lower: str) -> int:
    package = package_name.lower()
    normalized_category = category.lower()
    if normalized_category == 'msg' or 'whatsapp' in package:
        return 1
    if normalized_category == 'email' or 'gmail' in package:
        return 2
    if contains_keyword(lower, _paymentWords):
        return 3
    if contains_keyword(lower, _deliveryWords):
        return 4
    if contains_keyword(lower, _discountWords):
        return 5
    if contains_keyword(lower, _systemWords):
        return 6
    if contains_keyword(lower, _workWords):
        return 7
    return 0


def get_semantic_category_id(lower: str, android_category_id: int, intent_id: int) -> int:
    if contains_keyword(lower, _paymentWords):
        return 1
    if contains_keyword(lower, _securityWords):
        return 2
    if contains_keyword(lower, _deliveryWords):
        return 3
    if contains_keyword(lower, _workWords):
        return 4
    if contains_keyword(lower, _socialWords):
        return 5
    if contains_keyword(lower, _discountWords):
        return 6
    if android_category_id > 0:
        return android_category_id + 100
    return intent_id


def as_int(value: Any) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return int(value)
    if value is None:
        return 0
    try:
        return int(float(str(value)))
    except ValueError:
        return 0


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if value is None:
        return False
    normalized = str(value).lower().strip()
    return normalized in ('true', '1', 'yes')


def extract_features(record: dict[str, Any]) -> list[float]:
    # Extract fields from record
    title = record.get("title") or ""
    body = record.get("body") or ""
    package_name = record.get("package_name") or ""
    
    # We also have timestamp, android info
    android = record.get("android") or {}
    importance = as_int(android.get("importance"))
    conversation = as_bool(android.get("conversation"))
    visibility = as_int(android.get("visibility"))
    ongoing = as_bool(android.get("ongoing") or android.get("isOngoing"))
    foreground_service = as_bool(android.get("foreground_service") or android.get("foregroundService"))
    android_category = str(android.get("category") or android.get("notificationCategory") or "")
    channel_id = str(android.get("channel_id") or android.get("channelId") or "")
    channel_name = str(android.get("channel_name") or android.get("channelName") or "")
    contains_attachment = as_bool(android.get("containsAttachment") or android.get("contains_attachment"))

    # Get timestamp (standard format in the JSONL dataset is ISO 8601 string)
    timestamp_str = android.get("timestamp") or record.get("timestamp")
    if timestamp_str:
        try:
            # e.g., 2026-06-24T02:22:00+00:00
            # Remove colon in offset if it's there
            if len(timestamp_str) > 19 and timestamp_str[-3] == ':':
                timestamp_str = timestamp_str[:-3] + timestamp_str[-2:]
            dt = datetime.fromisoformat(timestamp_str)
        except Exception:
            dt = datetime.now(timezone.utc)
    else:
        dt = datetime.now(timezone.utc)

    # Convert dt to UTC
    dt_utc = dt.astimezone(timezone.utc)
    
    # Normalize texts
    title_norm = normalize(title)
    body_norm = normalize(body)
    combined = normalize(f"{title_norm} {body_norm}")
    lower = combined.lower()

    text_unit_count = max(len(combined), 1)
    letters = len(_letterRegex.findall(combined))
    uppercase = len(_upperRegex.findall(combined))
    digits = len(_digitRegex.findall(combined))
    
    otp = extract_otp(combined)
    amount = extract_amount(combined) or 0.0
    currency = extract_currency(combined)
    
    contains_deadline = contains_keyword(lower, _deadlineWords)
    is_promotion = (
        contains_keyword(lower, _discountWords) or
        bool(_percentageRegex.search(combined)) or
        bool(_couponRegex.search(combined))
    )
    contains_order = (
        bool(_orderIdRegex.search(combined)) or
        contains_any_phrase(lower, ['order placed', 'order confirmed'])
    )
    contains_transaction = (
        bool(_transactionIdRegex.search(combined)) or
        contains_keyword(lower, _paymentWords)
    )
    
    android_category_id = get_category_id(android_category, lower)
    intent_id = get_intent_id(lower)
    notification_type_id = get_notification_type_id(package_name, android_category, lower)
    category_id = get_semantic_category_id(lower, android_category_id, intent_id)

    # 1-indexed weekday for Dart (Monday = 1, Sunday = 7)
    # python weekday() is Monday=0, so add 1
    weekday = dt_utc.weekday() + 1

    values = [
        float(len(title_norm)),
        float(len(body_norm)),
        float(len(_wordRegex.findall(combined))),
        0.0 if letters == 0 else float(uppercase / letters),
        float(digits / text_unit_count),
        float(len(_emojiRegex.findall(combined))),
        float(len(_punctuationRegex.findall(combined))),
        1.0 if '?' in combined else 0.0,
        1.0 if '!' in combined else 0.0,
        1.0 if _currencySymbolRegex.search(combined) else 0.0,
        1.0 if (_amountRegex.search(combined) or contains_keyword(lower, _moneyWords)) else 0.0,
        1.0 if otp is not None else 0.0,
        1.0 if _dateRegex.search(combined) else 0.0,
        1.0 if _timeRegex.search(combined) else 0.0,
        1.0 if contains_keyword(lower, _locationWords) else 0.0,
        1.0 if _emailRegex.search(combined) else 0.0,
        1.0 if _phoneRegex.search(combined) else 0.0,
        1.0 if _urlRegex.search(combined) else 0.0,
        1.0 if (contains_attachment or contains_any_phrase(lower, ['attachment', 'attached', 'file', 'photo', 'image', 'pdf', 'document'])) else 0.0,
        1.0 if _percentageRegex.search(combined) else 0.0,
        1.0 if is_promotion else 0.0,
        1.0 if contains_order else 0.0,
        1.0 if contains_transaction else 0.0,
        1.0 if _referenceNumberRegex.search(combined) else 0.0,
        1.0 if _trackingNumberRegex.search(combined) else 0.0,
        1.0 if _couponRegex.search(combined) else 0.0,
        1.0 if _meetingLinkRegex.search(combined) else 0.0,
        1.0 if contains_deadline else 0.0,
        1.0 if contains_keyword(lower, _securityWords) else 0.0,
        1.0 if contains_keyword(lower, _paymentWords) else 0.0,
        1.0 if contains_keyword(lower, _deliveryWords) else 0.0,
        1.0 if contains_keyword(lower, _workWords) else 0.0,
        1.0 if contains_keyword(lower, _socialWords) else 0.0,
        1.0 if contains_keyword(lower, _systemWords) else 0.0,
        float(importance),
        1.0 if conversation else 0.0,
        float(visibility),
        1.0 if ongoing else 0.0,
        1.0 if foreground_service else 0.0,
        float(android_category_id),
        float(stable_bucket(channel_id)),
        float(stable_bucket(channel_name)),
        float(dt_utc.hour),
        float(weekday),
        1.0 if contains_keyword(lower, _actionWords) else 0.0,
        1.0 if contains_keyword(lower, _recurringWords) else 0.0,
        1.0 if is_promotion else 0.0,
        1.0 if is_duplicate_candidate(lower) else 0.0,
        1.0 if contains_deadline else 0.0,
        float(deadline_minutes_remaining(lower)),
        float(amount),
        float(_currencyIds.get(currency, 0)),
        float(len(otp) if otp else 0),
        1.0 if (contains_keyword(lower, _merchantWords) or merchant_after_amount(combined)) else 0.0,
        1.0 if (contains_keyword(lower, _personWords) or looks_like_person_title(title)) else 0.0,
        1.0 if contains_keyword(lower, _cityWords) else 0.0,
        1.0 if contains_keyword(lower, _trainWords) else 0.0,
        1.0 if contains_keyword(lower, _flightWords) else 0.0,
        1.0 if contains_order else 0.0,
        1.0 if contains_transaction else 0.0,
        float(intent_id),
        float(notification_type_id),
        float(category_id),
    ]
    return values
