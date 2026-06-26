import 'package:flutter/material.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/testing/test_notification_generator.dart';

class DiagnosticScreen extends StatefulWidget {
  final GhostAnalysisEngine? engine;

  const DiagnosticScreen({super.key, this.engine});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final GhostAnalysisEngine _engine;
  final _generator = TestNotificationGenerator();

  // Input Controllers
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _packageController = TextEditingController();
  bool _isOngoing = false;
  String _selectedTemplate = 'Custom';

  // Analysis Outputs
  AppNotification? _analyzedNotification;
  bool _isAnalyzing = false;
  bool _isEngineReady = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? GhostAnalysisEngine();
    _initEngine();
  }

  Future<void> _initEngine() async {
    await _engine.initialize();
    if (mounted) {
      setState(() => _isEngineReady = true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _packageController.dispose();
    super.dispose();
  }

  void _applyTemplate(String templateName) {
    if (templateName == 'Custom') {
      _titleController.clear();
      _contentController.clear();
      _packageController.clear();
      setState(() {
        _isOngoing = false;
        _selectedTemplate = templateName;
      });
      return;
    }

    final notif = _generator.generateByType(templateName);
    if (notif != null) {
      setState(() {
        _titleController.text = notif.title;
        _contentController.text = notif.content;
        _packageController.text = notif.packageName;
        _isOngoing = notif.isOngoing;
        _selectedTemplate = templateName;
      });
    }
  }

  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);

    final raw = AppNotification(
      id: 'diagnostic_${DateTime.now().millisecondsSinceEpoch}',
      packageName: _packageController.text.trim(),
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isOngoing: _isOngoing,
    );

    final result = await _engine.analyze(raw);

    if (mounted) {
      setState(() {
        _analyzedNotification = result;
        _isAnalyzing = false;
      });
    }
  }

  Color _getPriorityColor(String? priority) {
    switch (priority) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade800;
      case 'medium':
        return Colors.blue.shade700;
      case 'low':
        return Colors.grey.shade600;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghost AI Diagnostics'),
        actions: [
          if (!_isEngineReady)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInputFormCard(),
            const SizedBox(height: 16),
            _buildActionSection(),
            const SizedBox(height: 20),
            if (_analyzedNotification != null) ...[
              _buildResultsDashboard(),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputFormCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_input_component, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Input Notification Spec',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Template Selector
            DropdownButtonFormField<String>(
              value: _selectedTemplate,
              decoration: const InputDecoration(
                labelText: 'Quick Test Templates',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: 'Custom', child: Text('Custom Entry (Blank)')),
                const DropdownMenuItem(value: 'message', child: Text('WhatsApp Msg (Mom)')),
                const DropdownMenuItem(value: 'finance', child: Text('HDFC Bank Debit Alert')),
                const DropdownMenuItem(value: 'scholarship', child: Text('Scholarship Deadline')),
                const DropdownMenuItem(value: 'chat', child: Text('Slack Mention')),
                const DropdownMenuItem(value: 'email', child: Text('GSOC Accepted Email')),
                const DropdownMenuItem(value: 'promo', child: Text('Amazon Sale Offer')),
                const DropdownMenuItem(value: 'health', child: Text('Apollo Medical Appointment')),
                const DropdownMenuItem(value: 'system', child: Text('Android OS Patch')),
                const DropdownMenuItem(value: 'social', child: Text('Instagram Like Alert')),
              ],
              onChanged: (val) {
                if (val != null) {
                  _applyTemplate(val);
                }
              },
            ),
            const SizedBox(height: 16),
            // Package Name
            TextField(
              controller: _packageController,
              decoration: const InputDecoration(
                labelText: 'Package Name',
                hintText: 'e.g., com.whatsapp',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Title
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g., Mom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Content
            TextField(
              controller: _contentController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Content Body',
                hintText: 'e.g., Please pick up groceries...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Ongoing
            SwitchListTile(
              title: const Text('Ongoing (Persistent) Notification'),
              subtitle: const Text('System downloads, call logs, active music players'),
              value: _isOngoing,
              onChanged: (val) {
                setState(() => _isOngoing = val);
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSection() {
    return ElevatedButton.icon(
      onPressed: _isEngineReady && !_isAnalyzing ? _runAnalysis : null,
      icon: _isAnalyzing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.analytics),
      label: Text(_isAnalyzing ? 'RUNNING PIPELINE...' : 'ANALYZE NOTIFICATION'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildResultsDashboard() {
    final notif = _analyzedNotification!;
    final priorityColor = _getPriorityColor(notif.priority);

    // Safely parse feature variables to prevent Dart compilation/ternary ambiguity
    final features = notif.extractedFeatures ?? {};
    final otp = features['otp'] as String?;
    final amount = features['amount'];
    final amountStr = amount != null ? 'Rs. $amount' : null;
    final hasDeadline = features['hasDeadline'] == true ? 'YES' : null;

    final urls = features['urls'] as List?;
    final urlsStr = urls != null && urls.isNotEmpty ? urls.toString() : null;

    final emails = features['emails'] as List?;
    final emailsStr = emails != null && emails.isNotEmpty ? emails.toString() : null;

    final phoneNumbers = features['phoneNumbers'] as List?;
    final phoneNumbersStr = phoneNumbers != null && phoneNumbers.isNotEmpty ? phoneNumbers.toString() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title banner
        Text(
          'Analysis Pipeline Results',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),

        // Summary Card
        Card(
          color: priorityColor.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: priorityColor, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: priorityColor,
                  radius: 28,
                  child: const Icon(Icons.psychology, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            (notif.priority ?? 'UNKNOWN').toUpperCase(),
                            style: TextStyle(
                              color: priorityColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: priorityColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Category: ${notif.classifiedCategory ?? "None"}',
                              style: TextStyle(
                                color: priorityColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confidence Score: ${(notif.priorityScore != null ? (notif.priorityScore! * 100).toStringAsFixed(0) : "0")}% · Latency: ${notif.latencyMs ?? 0} ms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade800,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 1. Natural Language Explanation Card
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.comment_bank, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Pipeline Explanation Trace',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                Text(
                  notif.explanation ?? 'No explanation trace was generated.',
                  style: const TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Intermediate Feature Extraction Card
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.filter_list_alt, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Extracted Text Features',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                _buildFeatureRow('OTP Code', otp),
                _buildFeatureRow('Transaction Amount', amountStr),
                _buildFeatureRow('Has Deadline Warning', hasDeadline),
                _buildFeatureRow('Hyperlinks (URLs)', urlsStr),
                _buildFeatureRow('Emails', emailsStr),
                _buildFeatureRow('Phone Numbers', phoneNumbersStr),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Versions and Metadata
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildVersionItem('Engine', notif.engineVersion ?? 'None'),
                _buildVersionItem('Rules', notif.ruleVersion ?? 'None'),
                _buildVersionItem('Model', notif.modelVersion ?? 'None'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Expanded(
            child: Text(
              value ?? 'None',
              style: TextStyle(
                color: value != null ? Colors.blue.shade900 : Colors.grey,
                fontWeight: value != null ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
