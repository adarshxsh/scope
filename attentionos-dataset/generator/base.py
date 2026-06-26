from __future__ import annotations

import json
import random
import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Iterable
from urllib import request
from urllib.error import URLError

from faker import Faker
from jinja2 import Template

from policy.scoring import score_notification
from validator.duplicate import text_fingerprint
from validator.schema import validate_record


@dataclass(frozen=True)
class AppProfile:
    app_name: str
    package_name: str
    category: str
    subcategories: tuple[str, ...]
    channels: tuple[str, ...]
    base_importance: int


@dataclass(frozen=True)
class Scenario:
    category: str
    subcategory: str
    notification_type: str
    intent: str
    title_templates: tuple[str, ...]
    body_templates: tuple[str, ...]
    requires_action: bool = False
    action_type: str | None = None
    contains_money: bool = False
    contains_otp: bool = False
    contains_link: bool = False
    contains_email: bool = False
    contains_phone: bool = False
    contains_attachment: bool = False
    contains_location: bool = False
    contains_date: bool = False
    contains_time: bool = False
    is_recurring: bool = False
    deadline_hours: tuple[int, int] | None = None
    android_category: str = "status"
    importance_delta: int = 0
    weight: int = 10


POPULAR_APPS: tuple[AppProfile, ...] = (
    AppProfile("Google Pay", "com.google.android.apps.nbu.paisa.user", "UPI", ("UPI", "Finance"), ("Payments", "Offers", "Security"), 4),
    AppProfile("PhonePe", "com.phonepe.app", "UPI", ("UPI", "Cashback"), ("Transactions", "Requests", "Rewards"), 4),
    AppProfile("Paytm", "net.one97.paytm", "UPI", ("UPI", "Recharge"), ("Payments", "Bills", "Offers"), 4),
    AppProfile("HDFC Bank", "com.snapwork.hdfc", "Banking", ("Cards", "Banking"), ("Transactions", "Security", "Service"), 4),
    AppProfile("SBI YONO", "com.sbi.lotusintouch", "Banking", ("Banking", "Loans"), ("Account", "Cards", "Alerts"), 4),
    AppProfile("ICICI Bank", "com.csam.icici.bank.imobile", "Banking", ("Banking", "Cards"), ("Transactions", "Security", "Offers"), 4),
    AppProfile("Groww", "com.nextbillion.groww", "Finance", ("Investing", "Mutual Funds", "Loans"), ("Investments", "Orders", "Alerts"), 3),
    AppProfile("Zerodha Kite", "com.zerodha.kite3", "Finance", ("Investing", "Mutual Funds"), ("Orders", "Positions", "Alerts"), 4),
    AppProfile("Amazon", "in.amazon.mShop.android.shopping", "Shopping", ("E-commerce", "Delivery"), ("Orders", "Deals", "Delivery"), 3),
    AppProfile("Flipkart", "com.flipkart.android", "Shopping", ("E-commerce", "Flash Sales"), ("Orders", "Offers", "Delivery"), 3),
    AppProfile("Myntra", "com.myntra.android", "Shopping", ("E-commerce", "Coupons"), ("Orders", "Sale", "Delivery"), 3),
    AppProfile("Swiggy", "in.swiggy.android", "Food Delivery", ("Food Delivery", "Coupons"), ("Orders", "Delivery", "Offers"), 3),
    AppProfile("Zomato", "com.application.zomato", "Food Delivery", ("Food Delivery", "Coupons"), ("Orders", "Dining", "Offers"), 3),
    AppProfile("Uber", "com.ubercab", "Ride Booking", ("Ride Booking",), ("Trips", "Promotions", "Receipts"), 4),
    AppProfile("Ola", "com.olacabs.customer", "Ride Booking", ("Ride Booking",), ("Trips", "Payments", "Offers"), 4),
    AppProfile("IRCTC Rail Connect", "cris.org.in.prs.ima", "Railways", ("Railways",), ("Journey", "Booking", "Alerts"), 4),
    AppProfile("IndiGo", "in.goindigo.android", "Flights", ("Flights",), ("Trips", "Check-in", "Alerts"), 4),
    AppProfile("MakeMyTrip", "com.makemytrip", "Hotels", ("Hotels", "Flights", "Railways"), ("Bookings", "Trips", "Offers"), 4),
    AppProfile("Gmail", "com.google.android.gm", "Email", ("Email", "Work"), ("Primary", "Updates", "Promotions"), 3),
    AppProfile("Outlook", "com.microsoft.office.outlook", "Email", ("Email", "Calendar"), ("Mail", "Calendar", "Focused"), 3),
    AppProfile("WhatsApp", "com.whatsapp", "Messaging", ("Messaging",), ("Messages", "Calls", "Groups"), 4),
    AppProfile("Telegram", "org.telegram.messenger", "Messaging", ("Messaging",), ("Messages", "Channels", "Calls"), 4),
    AppProfile("Instagram", "com.instagram.android", "Social Media", ("Social Media",), ("Activity", "Direct", "Live"), 2),
    AppProfile("LinkedIn", "com.linkedin.android", "Social Media", ("Social Media", "Work"), ("Messages", "Jobs", "Network"), 3),
    AppProfile("Slack", "com.Slack", "Developer Tools", ("Slack", "Work"), ("Mentions", "DMs", "Channels"), 4),
    AppProfile("Microsoft Teams", "com.microsoft.teams", "Developer Tools", ("Teams", "Meetings"), ("Chats", "Meetings", "Calls"), 4),
    AppProfile("GitHub", "com.github.android", "Developer Tools", ("GitHub",), ("Pull requests", "Issues", "Actions"), 4),
    AppProfile("GitLab", "com.gitlab.gitlab", "Developer Tools", ("GitLab",), ("Merge requests", "Pipelines", "Issues"), 4),
    AppProfile("Jira", "com.atlassian.android.jira.core", "Developer Tools", ("Jira", "Tasks"), ("Assigned", "Mentions", "Updates"), 3),
    AppProfile("Google Calendar", "com.google.android.calendar", "Calendar", ("Meetings", "Tasks"), ("Events", "Tasks", "Reminders"), 4),
    AppProfile("Google Drive", "com.google.android.apps.docs", "Cloud Storage", ("Cloud Storage",), ("Shared", "Uploads", "Comments"), 3),
    AppProfile("YouTube", "com.google.android.youtube", "Entertainment", ("Streaming",), ("Subscriptions", "Live", "Recommendations"), 2),
    AppProfile("Spotify", "com.spotify.music", "Entertainment", ("Music",), ("Playback", "Recommendations", "Downloads"), 2),
    AppProfile("Netflix", "com.netflix.mediaclient", "Entertainment", ("Streaming",), ("New arrivals", "Downloads", "Account"), 2),
    AppProfile("Airtel Thanks", "com.myairtelapp", "Utilities", ("Broadband", "Recharge"), ("Bills", "Recharge", "Service"), 3),
    AppProfile("MyJio", "com.jio.myjio", "Utilities", ("Broadband", "Recharge"), ("Bills", "Recharge", "Service"), 3),
    AppProfile("DigiLocker", "com.digilocker.android", "Government", ("DigiLocker", "Aadhaar"), ("Documents", "Verification", "Alerts"), 4),
    AppProfile("Passport Seva", "com.passportindia", "Government", ("Passport",), ("Appointments", "Status", "Alerts"), 4),
    AppProfile("Income Tax", "com.incometaxindiaefiling", "Tax", ("Tax", "Government"), ("Filing", "Refunds", "Notices"), 4),
    AppProfile("Google Classroom", "com.google.android.apps.classroom", "Education", ("Assignments", "Exams", "University"), ("Classwork", "Comments", "Reminders"), 4),
    AppProfile("Moodle", "com.moodle.moodlemobile", "Education", ("Assignments", "Exams", "University"), ("Courses", "Assignments", "Messages"), 4),
    AppProfile("Coursera", "org.coursera.android", "Education", ("Education", "Assignments"), ("Courses", "Deadlines", "Messages"), 3),
    AppProfile("Apollo 24|7", "com.apollo.patientapp", "Healthcare", ("Appointments", "Medicine Reminder"), ("Appointments", "Medicines", "Reports"), 4),
    AppProfile("1mg", "com.aranoah.healthkart.plus", "Healthcare", ("Medicine Reminder", "Lab Reports"), ("Medicines", "Labs", "Orders"), 4),
    AppProfile("Policybazaar", "com.policybazaar", "Insurance", ("Insurance", "Renewals"), ("Policies", "Claims", "Renewals"), 3),
    AppProfile("Google Tasks", "com.google.android.apps.tasks", "Tasks", ("Tasks", "Productivity"), ("Tasks", "Reminders", "Lists"), 3),
    AppProfile("Todoist", "com.todoist", "Tasks", ("Tasks", "Productivity"), ("Tasks", "Projects", "Reminders"), 3),
    AppProfile("Google Play", "com.android.vending", "Android System", ("Updates",), ("App updates", "Security", "Downloads"), 3),
    AppProfile("Android System", "android", "Android System", ("Battery", "Downloads", "Updates"), ("System", "Battery", "Connectivity"), 4),
    AppProfile("Google Weather", "com.google.android.googlequicksearchbox", "Weather", ("Weather", "Emergency Alerts"), ("Weather", "Alerts", "Forecast"), 3),
    AppProfile("Cell Broadcast", "com.android.cellbroadcastreceiver", "Emergency Alerts", ("Emergency Alerts",), ("Emergency alerts", "Safety", "Warnings"), 5),
)


SCENARIOS: tuple[Scenario, ...] = (
    Scenario("UPI", "UPI", "payment_received", "inform", ("Payment received", "Money added"), ("₹{{amount}} received from {{person}}. UPI ref {{ref}}.", "{{person}} paid you ₹{{amount}} via UPI. Balance updated."), contains_money=True, weight=30),
    Scenario("UPI", "UPI", "upi_request", "approve", ("UPI collect request", "Payment request"), ("{{merchant}} requested ₹{{amount}}. Approve before {{time}}.", "Review ₹{{amount}} request from {{person}} in your UPI app."), requires_action=True, action_type="approve_payment", contains_money=True, contains_time=True, deadline_hours=(1, 6), importance_delta=1, weight=24),
    Scenario("Banking", "Cards", "debit_alert", "inform", ("Card used", "Debit alert"), ("₹{{amount}} spent on card ending {{last4}} at {{merchant}}.", "A debit of ₹{{amount}} was made from A/c {{last4}} at {{merchant}}."), contains_money=True, weight=32),
    Scenario("Banking", "Banking", "fraud_alert", "verify", ("Suspicious transaction", "Security check needed"), ("Unusual ₹{{amount}} transaction detected. Confirm if this was you.", "We blocked a risky card attempt at {{merchant}}. Review now."), requires_action=True, action_type="verify_transaction", contains_money=True, importance_delta=1, android_category="alarm", weight=16),
    Scenario("Finance", "Investing", "market_alert", "review", ("Price alert", "Investment update"), ("{{merchant}} crossed your alert price. Review your watchlist.", "{{repo}} is down {{percent}}% today. Check portfolio impact."), contains_money=False, weight=16),
    Scenario("Finance", "Mutual Funds", "sip_reminder", "pay", ("SIP due tomorrow", "Mutual fund reminder"), ("SIP of ₹{{amount}} for {{merchant}} is scheduled on {{date}}.", "Keep balance ready for ₹{{amount}} SIP debit on {{date}}."), requires_action=True, action_type="maintain_balance", contains_money=True, contains_date=True, deadline_hours=(12, 72), weight=16),
    Scenario("Finance", "Loans", "loan_due", "pay", ("EMI due soon", "Loan payment reminder"), ("EMI of ₹{{amount}} is due on {{date}}. Pay on time to avoid charges.", "Loan account {{last4}} has payment due by {{date}}."), requires_action=True, action_type="pay_emi", contains_money=True, contains_date=True, deadline_hours=(12, 120), weight=14),
    Scenario("OTP", "Authentication", "otp", "verify", ("Verification code", "OTP for login"), ("Use {{otp}} to verify your sign-in. Valid for {{minutes}} minutes.", "{{otp}} is your code for {{app_context}}. Do not share it."), requires_action=True, action_type="enter_otp", contains_otp=True, contains_time=True, deadline_hours=(0, 1), android_category="msg", importance_delta=1, weight=34),
    Scenario("Security", "Password Reset", "password_reset", "reset", ("Password reset request", "Reset code sent"), ("A reset was requested for {{email}}. Use code {{otp}} if this was you.", "Password change started from {{city}}. Secure your account if unexpected."), requires_action=True, action_type="secure_account", contains_otp=True, contains_email=True, contains_location=True, importance_delta=1, weight=18),
    Scenario("Security", "Authentication", "login_detected", "review", ("New login detected", "Account sign-in"), ("New sign-in from {{device}} near {{city}} at {{time}}.", "{{app_context}} was accessed on {{device}}. Review if this wasn't you."), requires_action=True, action_type="review_login", contains_location=True, contains_time=True, importance_delta=1, weight=22),
    Scenario("Shopping", "E-commerce", "order_placed", "track", ("Order placed", "Order confirmed"), ("Order #{{order_id}} for ₹{{amount}} is confirmed. Delivery by {{date}}.", "{{merchant}} order placed. Track package #{{order_id}} from your orders."), contains_money=True, contains_date=True, weight=24),
    Scenario("Delivery", "Delivery", "out_for_delivery", "track", ("Out for delivery", "Arriving today"), ("Your package #{{order_id}} is out for delivery with {{person}}.", "{{merchant}} order arrives today. Keep your phone reachable."), contains_phone=True, deadline_hours=(1, 10), importance_delta=1, weight=28),
    Scenario("Food Delivery", "Food Delivery", "food_status", "track", ("Order update", "Food arriving soon"), ("{{restaurant}} is preparing your order. ETA {{minutes}} min.", "{{person}} is on the way with your food. Arriving by {{time}}."), contains_time=True, deadline_hours=(0, 2), weight=28),
    Scenario("Promotions", "Coupons", "coupon", "browse", ("Coupon unlocked", "Offer for you"), ("Save ₹{{amount}} on {{merchant}} orders today. Code {{code}}.", "{{code}} gives extra {{percent}}% off until {{time}} tonight."), contains_money=True, contains_time=True, weight=24),
    Scenario("Promotions", "Flash Sales", "flash_sale", "browse", ("Flash sale live", "Deal ends soon"), ("{{merchant}} sale is live for {{hours}} hours. Top picks are moving fast.", "Limited-time prices on {{category_item}}. Ends at {{time}}."), contains_time=True, deadline_hours=(1, 8), weight=18),
    Scenario("Calendar", "Meetings", "meeting_reminder", "join", ("Meeting in {{minutes}} min", "Upcoming meeting"), ("{{meeting}} starts at {{time}} with {{person}}.", "Join {{meeting}} at {{time}}. Location: {{place}}."), requires_action=True, action_type="join_meeting", contains_time=True, contains_location=True, deadline_hours=(0, 2), importance_delta=1, weight=26),
    Scenario("Education", "Assignments", "assignment_due", "submit", ("Assignment due", "Submission reminder"), ("{{course}} assignment is due by {{time}} on {{date}}.", "Upload {{course}} work before {{time}} to avoid late marks."), requires_action=True, action_type="submit_assignment", contains_date=True, contains_time=True, deadline_hours=(2, 48), weight=22),
    Scenario("Healthcare", "Medicine Reminder", "medicine_reminder", "take", ("Medicine reminder", "Time for medicine"), ("Take {{medicine}} after food at {{time}}.", "{{medicine}} dose is scheduled now. Mark as taken when done."), requires_action=True, action_type="take_medicine", contains_time=True, is_recurring=True, deadline_hours=(0, 2), weight=18),
    Scenario("Healthcare", "Appointments", "appointment", "attend", ("Appointment reminder", "Doctor visit today"), ("Appointment with Dr. {{doctor}} at {{time}}, {{place}}.", "Your {{specialty}} consultation is scheduled for {{date}} at {{time}}."), requires_action=True, action_type="attend_appointment", contains_date=True, contains_time=True, contains_location=True, deadline_hours=(2, 48), weight=20),
    Scenario("Government", "Passport", "appointment", "attend", ("Passport appointment", "Document check"), ("Visit {{place}} on {{date}} at {{time}} with original documents.", "Passport file {{ref}} is scheduled for verification on {{date}}."), requires_action=True, action_type="attend_appointment", contains_date=True, contains_time=True, contains_location=True, weight=14),
    Scenario("Government", "DigiLocker", "document_issued", "review", ("Document issued", "DigiLocker update"), ("{{file_name}} is now available in your DigiLocker account.", "Aadhaar-linked document {{ref}} was added. Open to verify details."), requires_action=False, contains_attachment=True, weight=12),
    Scenario("Insurance", "Insurance", "policy_renewal", "pay", ("Policy renewal due", "Insurance reminder"), ("Renew policy {{ref}} by {{date}} to keep cover active.", "Premium of ₹{{amount}} is due on {{date}} for your policy."), requires_action=True, action_type="renew_policy", contains_money=True, contains_date=True, deadline_hours=(24, 168), weight=14),
    Scenario("Tax", "Tax", "tax_notice", "review", ("Tax filing update", "Action on tax return"), ("Review notice {{ref}} before {{date}} to continue processing.", "Refund for AY {{year}} needs bank validation. Update details by {{date}}."), requires_action=True, action_type="review_document", contains_date=True, deadline_hours=(24, 168), importance_delta=1, weight=14),
    Scenario("Messaging", "Messaging", "new_message", "respond", ("{{person}}", "New message"), ("{{message}}", "{{person}}: {{message}}"), requires_action=False, android_category="msg", weight=40),
    Scenario("Social Media", "Social Media", "social_activity", "browse", ("New activity", "{{person}} reacted"), ("{{person}} commented on your post.", "{{count}} people viewed your update today."), weight=18),
    Scenario("Email", "Email", "email", "review", ("{{sender}}", "{{subject}}"), ("{{subject}} — {{email_snippet}}", "{{sender}} sent an email with {{attachment_text}}."), contains_email=True, contains_attachment=True, weight=34),
    Scenario("Developer Tools", "GitHub", "pull_request", "review", ("PR needs review", "Pull request update"), ("{{person}} requested your review on {{repo}}#{{number}}.", "Checks failed on {{repo}}#{{number}} after latest push."), requires_action=True, action_type="review_code", contains_link=True, importance_delta=1, weight=20),
    Scenario("Developer Tools", "Slack", "mention", "respond", ("Mention in {{channel}}", "{{person}} mentioned you"), ("{{person}}: {{message}}", "New mention in {{channel}} about {{project}}."), requires_action=True, action_type="reply", android_category="msg", weight=22),
    Scenario("Developer Tools", "Jira", "task_assigned", "review", ("Issue assigned", "Jira update"), ("{{person}} assigned {{ticket}} to you. Due {{date}}.", "{{ticket}} moved to Review in {{project}}."), requires_action=True, action_type="review_task", contains_date=True, deadline_hours=(24, 120), weight=16),
    Scenario("Tasks", "Tasks", "task_due", "complete", ("Task due", "Reminder"), ("{{project}} task is due at {{time}} today.", "Complete {{ticket}} before {{time}} to stay on schedule."), requires_action=True, action_type="complete_task", contains_time=True, deadline_hours=(1, 24), weight=18),
    Scenario("Utilities", "Electricity", "bill_due", "pay", ("Bill due soon", "Payment reminder"), ("₹{{amount}} electricity bill is due on {{date}}.", "Pay broadband bill of ₹{{amount}} before {{date}} to avoid late fee."), requires_action=True, action_type="pay_bill", contains_money=True, contains_date=True, deadline_hours=(24, 120), weight=20),
    Scenario("Utilities", "Recharge", "recharge_success", "inform", ("Recharge successful", "Plan activated"), ("₹{{amount}} recharge is active. Valid until {{date}}.", "Your data pack was renewed successfully for mobile ending {{last4}}."), contains_money=True, contains_date=True, weight=14),
    Scenario("Flights", "Flights", "flight_update", "prepare", ("Flight update", "Check-in open"), ("Flight {{ref}} from {{city}} is delayed. New departure {{time}}.", "Web check-in is open for {{city}} trip on {{date}}."), requires_action=True, action_type="check_in", contains_date=True, contains_time=True, contains_location=True, deadline_hours=(2, 48), weight=14),
    Scenario("Railways", "Railways", "train_update", "prepare", ("Train running late", "Journey update"), ("Train {{ref}} is running {{minutes}} min late near {{city}}.", "Platform details for PNR {{ref}} will be updated before {{time}}."), contains_time=True, contains_location=True, weight=14),
    Scenario("Hotels", "Hotels", "hotel_booking", "review", ("Hotel booking confirmed", "Check-in reminder"), ("{{place}} stay is confirmed for {{date}}. Check-in starts at {{time}}.", "Carry ID proof for booking {{ref}} at {{place}}."), requires_action=True, action_type="carry_documents", contains_date=True, contains_time=True, contains_location=True, weight=10),
    Scenario("Ride Booking", "Ride Booking", "ride_status", "track", ("Driver arriving", "Ride update"), ("{{person}} is arriving in {{minutes}} min at {{place}}.", "Your ride to {{city}} is confirmed. OTP {{otp}} for pickup."), requires_action=True, action_type="board_ride", contains_otp=True, contains_time=True, contains_location=True, deadline_hours=(0, 1), weight=18),
    Scenario("Entertainment", "Streaming", "recommendation", "browse", ("New for you", "Continue watching"), ("{{show}} is now streaming. Pick up from where you left off.", "New episode of {{show}} is available to watch."), weight=18),
    Scenario("Cloud Storage", "Cloud Storage", "shared_file", "review", ("File shared", "New shared document"), ("{{person}} shared {{file_name}} with you.", "{{file_name}} finished uploading to your drive."), contains_attachment=True, weight=16),
    Scenario("Healthcare", "Lab Reports", "lab_report", "review", ("Lab report ready", "Health report available"), ("{{file_name}} is ready. Open report to review your results.", "Your lab report for booking {{ref}} is available now."), requires_action=True, action_type="review_report", contains_attachment=True, weight=14),
    Scenario("Android System", "Battery", "battery_low", "charge", ("Battery low", "Power warning"), ("{{percent}}% battery remaining. Connect your charger soon.", "Battery Saver is on. Some background activity is limited."), requires_action=True, action_type="charge_device", android_category="sys", importance_delta=1, weight=14),
    Scenario("Android System", "Updates", "app_update", "install", ("Updates available", "Download complete"), ("{{count}} app updates are ready to install from Google Play.", "{{file_name}} download completed. Tap to open."), requires_action=False, contains_attachment=True, weight=14),
    Scenario("Android System", "Downloads", "download_complete", "open", ("Download complete", "File downloaded"), ("{{file_name}} has finished downloading.", "Download complete. Tap to open {{file_name}}."), contains_attachment=True, weight=12),
    Scenario("Android System", "Storage", "storage_full", "clean", ("Storage almost full", "Free up space"), ("Only {{percent}}% storage is available. Remove unused files or apps.", "Device storage is low. Some apps may stop syncing."), requires_action=True, action_type="free_storage", weight=10),
    Scenario("Weather", "Weather", "weather_alert", "prepare", ("Weather alert", "Rain expected"), ("Heavy rain likely near {{city}} around {{time}}. Plan travel carefully.", "{{city}} may see thunderstorms this evening. Stay updated."), requires_action=True, action_type="prepare", contains_location=True, contains_time=True, importance_delta=1, weight=12),
    Scenario("Emergency Alerts", "Emergency Alerts", "emergency_alert", "act", ("Emergency alert", "Safety warning"), ("Authorities issued an alert for {{city}}. Follow local safety instructions.", "Severe conditions reported near {{place}}. Move to a safer area if needed."), requires_action=True, action_type="safety_action", contains_location=True, android_category="alarm", importance_delta=2, weight=6),
)


class NotificationDatasetGenerator:
    def __init__(self, seed: int = 42, use_ollama: bool = False, ollama_model: str = "gemma3:9b") -> None:
        self.seed = seed
        self.random = random.Random(seed)
        self.fake = Faker("en_IN")
        Faker.seed(seed)
        self.use_ollama = use_ollama
        self.ollama_model = ollama_model
        self.base_time = datetime(2026, 6, 26, 9, 0, 0, tzinfo=timezone.utc)
        self._weighted_scenarios = [scenario for scenario in SCENARIOS for _ in range(scenario.weight)]
        self._seen_text: set[str] = set()

    def generate(self, count: int) -> Iterable[dict[str, Any]]:
        produced = 0
        attempts = 0
        while produced < count:
            attempts += 1
            if attempts > count * 8:
                raise RuntimeError("Could not produce enough unique notifications")
            record = self._make_record(index=produced)
            fp = text_fingerprint(record["title"], record["body"])
            if fp in self._seen_text:
                continue
            self._seen_text.add(fp)
            errors = validate_record(record)
            if errors:
                raise ValueError(f"invalid record {record.get('id')}: {errors}")
            produced += 1
            yield record

    def _make_record(self, index: int) -> dict[str, Any]:
        scenario = self.random.choice(self._weighted_scenarios)
        app = self._choose_app(scenario)
        now = self.base_time
        timestamp = now - timedelta(minutes=self.random.randint(0, 60 * 24 * 90))
        ctx = self._context(app, scenario, timestamp)

        title, body = self._render_notification(scenario, ctx)
        deadline = None
        if scenario.deadline_hours:
            start, end = scenario.deadline_hours
            deadline = (timestamp + timedelta(hours=self.random.randint(start, max(start, end)))).isoformat()

        importance = max(1, min(5, app.base_importance + scenario.importance_delta + self.random.choice((-1, 0, 0, 0, 1))))
        channel_name = self.random.choice(app.channels)
        record: dict[str, Any] = {
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"attentionos:{self.seed}:{index}:{title}:{body}")),
            "app_name": app.app_name,
            "package_name": app.package_name,
            "category": scenario.category,
            "subcategory": scenario.subcategory,
            "notification_type": scenario.notification_type,
            "title": title,
            "body": body,
            "language": "en",
            "contains_money": scenario.contains_money,
            "contains_otp": scenario.contains_otp,
            "contains_link": scenario.contains_link,
            "contains_email": scenario.contains_email,
            "contains_phone": scenario.contains_phone,
            "contains_attachment": scenario.contains_attachment,
            "contains_location": scenario.contains_location,
            "contains_date": scenario.contains_date,
            "contains_time": scenario.contains_time,
            "deadline": deadline,
            "requires_action": scenario.requires_action,
            "action_type": scenario.action_type,
            "intent": scenario.intent,
            "is_recurring": scenario.is_recurring,
            "urgency": "",
            "entities": self._entities(ctx, scenario),
            "android": {
                "package_name": app.package_name,
                "channel_id": self._slug(channel_name),
                "channel_name": channel_name,
                "category": scenario.android_category,
                "importance": importance,
                "group": self._group_key(app, scenario),
                "conversation": scenario.android_category == "msg",
                "timestamp": timestamp.isoformat(),
                "visibility": self.random.choice(("public", "private", "private", "secret")),
                "ongoing": scenario.notification_type in {"food_status", "out_for_delivery"} and self.random.random() < 0.35,
                "foreground_service": app.category == "Android System" and self.random.random() < 0.2,
                "priority": importance - 3,
                "notification_id": self.random.randint(1000, 999999),
                "tag": self.random.choice((None, self._slug(scenario.notification_type), f"{self._slug(app.app_name)}-{self.random.randint(1, 9)}")),
            },
        }

        record.update(score_notification(record, now=now))
        record["labels"] = {
            "category_class": scenario.category,
            "intent": scenario.intent,
            "urgency": record["urgency"],
            "requires_action": record["requires_action"],
            "is_promotion": scenario.notification_type in {"promotion", "coupon", "cashback", "flash_sale", "recommendation"},
            "is_duplicate_candidate": False,
            "is_recurring": record["is_recurring"],
            "look_again": record["look_again"],
        }
        return record

    def _choose_app(self, scenario: Scenario) -> AppProfile:
        category_matches = [app for app in POPULAR_APPS if app.category == scenario.category]
        subcategory_matches = [
            app for app in POPULAR_APPS
            if scenario.subcategory in app.subcategories or scenario.category in app.subcategories
        ]
        return self.random.choice(category_matches or subcategory_matches or list(POPULAR_APPS))

    def _render_notification(self, scenario: Scenario, ctx: dict[str, Any]) -> tuple[str, str]:
        if self.use_ollama and self.random.random() < 0.2:
            generated = self._ollama_notification(scenario, ctx)
            if generated:
                return generated
        title = Template(self.random.choice(scenario.title_templates)).render(**ctx)
        body = Template(self.random.choice(scenario.body_templates)).render(**ctx)
        return self._clip(title, 50), self._clip(body, 140)

    def _ollama_notification(self, scenario: Scenario, ctx: dict[str, Any]) -> tuple[str, str] | None:
        prompt = (
            "Return only JSON with exactly title and body. "
            "Make a realistic Android notification. "
            f"App: {ctx['app_context']}. Type: {scenario.notification_type}. "
            f"Intent: {scenario.intent}. Keep title <= 50 chars and body <= 140 chars. "
            "No real personal data."
        )
        payload = json.dumps({"model": self.ollama_model, "prompt": prompt, "stream": False}).encode("utf-8")
        try:
            req = request.Request("http://localhost:11434/api/generate", data=payload, headers={"Content-Type": "application/json"})
            with request.urlopen(req, timeout=20) as response:
                raw = json.loads(response.read().decode("utf-8")).get("response", "{}")
        except (URLError, TimeoutError, json.JSONDecodeError):
            return None
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", raw, flags=re.S)
            if not match:
                return None
            parsed = json.loads(match.group(0))
        title = str(parsed.get("title", "")).strip()
        body = str(parsed.get("body", "")).strip()
        if not title or not body:
            return None
        return self._clip(title, 50), self._clip(body, 140)

    def _context(self, app: AppProfile, scenario: Scenario, timestamp: datetime) -> dict[str, Any]:
        city = self.random.choice(("Bengaluru", "Mumbai", "Delhi", "Pune", "Hyderabad", "Chennai", "Kolkata", "Ahmedabad", "Jaipur", "Kochi"))
        merchant = self.random.choice(("FreshMart", "UrbanCart", "Metro Cafe", "BlueKart", "QuickStore", "NovaPay", "Green Basket", "City Pharmacy"))
        person = self.fake.first_name()
        amount = self.random.choice((99, 149, 199, 249, 499, 799, 1250, 1850, 2499, 4299, 7999, 15499))
        return {
            "amount": amount,
            "app_context": app.app_name,
            "attachment_text": self.random.choice(("an attachment", "a PDF", "a spreadsheet", "2 files")),
            "category_item": self.random.choice(("phones", "sneakers", "kitchen tools", "headphones", "backpacks", "skin care")),
            "channel": self.random.choice(app.channels),
            "city": city,
            "code": f"SAVE{self.random.randint(10, 90)}",
            "count": self.random.randint(2, 18),
            "course": self.random.choice(("Data Structures", "Economics", "Physics Lab", "Design Studio", "Business Analytics")),
            "date": (timestamp + timedelta(days=self.random.randint(1, 14))).strftime("%d %b"),
            "device": self.random.choice(("Pixel 8", "Galaxy M34", "Chrome on Windows", "OnePlus Nord", "iPhone 15")),
            "doctor": self.fake.last_name(),
            "email": f"{self.fake.user_name()}@example.com",
            "email_snippet": self.random.choice(("please check the latest draft", "sharing the revised schedule", "can you confirm this today", "the invoice is attached")),
            "file_name": self.random.choice(("Project brief.pdf", "invoice-june.pdf", "trip-plan.xlsx", "report-summary.docx", "photo-backup.zip")),
            "hours": self.random.randint(2, 12),
            "last4": str(self.random.randint(1000, 9999)),
            "meeting": self.random.choice(("Sprint planning", "Design review", "Interview round", "Client sync", "Budget review")),
            "medicine": self.random.choice(("Metformin 500 mg", "Vitamin D3", "Amoxicillin", "Cetirizine", "BP tablet")),
            "merchant": merchant,
            "message": self.random.choice(("Can you check this?", "I'll join in 5 minutes", "The build is ready", "Please review before lunch", "Sending the details now")),
            "minutes": self.random.choice((5, 10, 15, 20, 30, 45)),
            "number": self.random.randint(12, 999),
            "order_id": f"OD{self.random.randint(100000, 999999)}",
            "otp": str(self.random.randint(100000, 999999)),
            "percent": self.random.choice((10, 15, 20, 25, 30, 40)),
            "percent_symbol": "%",
            "person": person,
            "place": self.random.choice((f"{city} Central", f"{city} Clinic", "Gate 3", "Online", "Service Centre")),
            "project": self.random.choice(("AttentionOS", "Mobile App", "Billing API", "Design System", "Launch Plan")),
            "ref": str(self.random.randint(10000000, 99999999)),
            "repo": self.random.choice(("attentionos/app", "scope/mobile", "infra/alerts", "ml/priority-engine")),
            "restaurant": self.random.choice(("Curry Leaf", "Noodle Bay", "Tandoor Box", "Cafe Eight", "Dosa Street")),
            "sender": self.random.choice(("Riya", "Arjun", "Nisha", "Karan", "Meera", "Operations Team")),
            "show": self.random.choice(("Midnight Case", "City Lights", "The Final Over", "Startup Stories", "Weekend Kitchen")),
            "specialty": self.random.choice(("cardiology", "dental", "general physician", "dermatology", "orthopedic")),
            "subject": self.random.choice(("Invoice approval", "Schedule update", "Documents required", "Interview feedback", "Action needed")),
            "ticket": f"ATT-{self.random.randint(100, 9999)}",
            "time": (timestamp + timedelta(minutes=self.random.randint(5, 480))).strftime("%I:%M %p").lstrip("0"),
            "year": self.random.choice(("2024-25", "2025-26", "2026-27")),
            "channel_name": self.random.choice(app.channels),
        }

    def _entities(self, ctx: dict[str, Any], scenario: Scenario) -> dict[str, Any]:
        entities: dict[str, Any] = {
            "app": ctx["app_context"],
            "reference_id": ctx["ref"],
        }
        if scenario.contains_money:
            entities["amount"] = ctx["amount"]
            entities["currency"] = "INR"
            entities["merchant"] = ctx["merchant"]
        if scenario.contains_otp:
            entities["otp_length"] = len(ctx["otp"])
        if scenario.contains_location:
            entities["city"] = ctx["city"]
            entities["place"] = ctx["place"]
        if scenario.contains_date:
            entities["date_text"] = ctx["date"]
        if scenario.contains_time:
            entities["time_text"] = ctx["time"]
        if scenario.contains_email:
            entities["email_domain"] = "example.com"
        return entities

    @staticmethod
    def _clip(value: str, limit: int) -> str:
        value = " ".join(value.split())
        if len(value) <= limit:
            return value
        return value[: limit - 1].rstrip(" .,;:-") + "…"

    @staticmethod
    def _slug(value: str) -> str:
        return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")

    def _group_key(self, app: AppProfile, scenario: Scenario) -> str:
        return f"{app.package_name}.{self._slug(scenario.subcategory)}"
