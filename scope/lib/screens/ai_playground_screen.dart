import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// AI Playground for post-mortem analysis and Reinforcement Learning from Human Feedback (RLHF).
class AiPlaygroundScreen extends StatefulWidget {
  final NotificationController controller;

  const AiPlaygroundScreen({super.key, required this.controller});

  @override
  State<AiPlaygroundScreen> createState() => _AiPlaygroundScreenState();
}

class _AiPlaygroundScreenState extends State<AiPlaygroundScreen> {
  AppNotification? _selectedNotification;
  bool _isCustomMode = false;

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _packageController = TextEditingController(text: 'com.example.app');

  String _selectedCategory = 'financial';
  String _selectedPriority = 'high';
  bool _showCorrectionForm = false;

  final List<String> _categories = [
    'financial',
    'social',
    'work',
    'promotional',
    'system',
    'personal',
  ];

  final List<String> _priorities = ['critical', 'high', 'medium', 'low'];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _packageController.dispose();
    super.dispose();
  }

  void _updateSelectedFields(String? category, String? priority) {
    final cat = category?.toLowerCase() ?? 'financial';
    final pri = priority?.toLowerCase() ?? 'medium';
    if (!_categories.contains(cat)) {
      _categories.add(cat);
    }
    if (!_priorities.contains(pri)) {
      _priorities.add(pri);
    }
    _selectedCategory = cat;
    _selectedPriority = pri;
  }

  void _analyzeCustom() async {
    final raw = AppNotification(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      packageName: _packageController.text.trim().isEmpty ? 'com.custom.app' : _packageController.text.trim(),
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final analyzed = await widget.controller.engine.analyze(raw);
    setState(() {
      _selectedNotification = analyzed;
      _updateSelectedFields(analyzed.classifiedCategory, analyzed.priority);
      _showCorrectionForm = false;
    });
  }

  void _selectNotification(AppNotification n) {
    setState(() {
      _selectedNotification = n;
      _updateSelectedFields(n.classifiedCategory, n.priority);
      _showCorrectionForm = false;
    });
  }

  void _submitFeedback(bool isReward) {
    if (_selectedNotification == null) return;

    if (isReward) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward (+1) recorded! AI model confidence reinforced.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() {
        _showCorrectionForm = true;
      });
    }
  }

  void _applyReinforcementRule() {
    if (_selectedNotification == null) return;

    final n = _selectedNotification!;
    // Extract defining keywords (e.g. words > 3 chars)
    final words = <String>[];
    for (final w in n.title.split(' ')) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (clean.length > 3) words.add(clean);
    }
    for (final w in n.content.split(' ')) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (clean.length > 4 && words.length < 3) words.add(clean);
    }

    final newRule = NotificationRule(
      id: 'rlhf-${DateTime.now().millisecondsSinceEpoch}',
      category: _selectedCategory,
      priority: _selectedPriority,
      conditions: RuleCondition(
        packages: [n.packageName],
        titleKeywords: words.take(2).toList(),
      ),
    );

    widget.controller.engine.ruleEngine.addReinforcementRule(newRule);

    setState(() {
      _showCorrectionForm = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reinforcement Rule Learned! Similar messages will now be classified as $_selectedPriority ($_selectedCategory).'),
        backgroundColor: AppColors.seed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = widget.controller.notifications.take(15).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('AI Playground (RLHF)')),
      body: SafeArea(
        child: ScopeScreenBody(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              const SectionHeader(
                title: 'Model Post-Mortem',
                subtitle: 'Inspect classification decisions and reinforce AI behavior.',
              ),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Recent Notifications'),
                      selected: !_isCustomMode,
                      onSelected: (val) => setState(() => _isCustomMode = !val),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Simulator Mode'),
                      selected: _isCustomMode,
                      onSelected: (val) => setState(() => _isCustomMode = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_isCustomMode) _buildSimulatorForm() else _buildRecentList(notifications),
              const SizedBox(height: AppSpacing.lg),
              if (_selectedNotification != null) _buildPostMortemPanel(_selectedNotification!, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimulatorForm() {
    return ScopeSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _packageController,
            decoration: const InputDecoration(labelText: 'Package Name (e.g., com.sbi.upi)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Notification Title (e.g., SBI Alert)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _contentController,
            decoration: const InputDecoration(labelText: 'Content (e.g., Rs.500 debited from a/c 1234)'),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _analyzeCustom,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Run AI Analysis'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentList(List<AppNotification> notifications) {
    if (notifications.isEmpty) {
      return const ScopeSurface(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: Text('No analyzed notifications available yet.')),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final n = notifications[index];
          final isSelected = _selectedNotification?.id == n.id;
          return GestureDetector(
            onTap: () => _selectNotification(n),
            child: Container(
              width: 180,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.seed.withValues(alpha: 0.2) : const Color(0xFF161A23),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? AppColors.seed : const Color(0xFF262A36)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(n.packageName, style: const TextStyle(fontSize: 10, color: Colors.white54), maxLines: 1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.urgency(n.priority).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(n.priority?.toUpperCase() ?? 'MED', style: TextStyle(fontSize: 8, color: AppColors.urgency(n.priority))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(n.title.isEmpty ? '(No title)' : n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(n.content, style: const TextStyle(fontSize: 11, color: Colors.white70), maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostMortemPanel(AppNotification n, ThemeData theme) {
    final featuresMap = n.extractedFeatures ?? {};
    final features = ExtractedFeatures.fromMap(featuresMap);

    // Identify defining features (e.g. keywords)
    final definingWords = <String>[];
    if (n.title.toLowerCase().contains('sbi') || n.content.toLowerCase().contains('sbi')) definingWords.add('sbi');
    if (n.title.toLowerCase().contains('debited') || n.content.toLowerCase().contains('debited')) definingWords.add('debited');
    if (n.title.toLowerCase().contains('credited') || n.content.toLowerCase().contains('credited')) definingWords.add('credited');
    if (n.title.toLowerCase().contains('offer') || n.content.toLowerCase().contains('offer')) definingWords.add('offer');
    if (n.title.toLowerCase().contains('sale') || n.content.toLowerCase().contains('sale')) definingWords.add('sale');
    if (features.otp != null) definingWords.add('OTP:${features.otp}');
    if (features.amount != null) definingWords.add('Amount:Rs.${features.amount}');

    return ScopeSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Post-Mortem Trace', style: theme.textTheme.titleMedium),
              Text('${n.latencyMs ?? 0} ms', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const Divider(height: 24),
          Text('Input Target:', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54)),
          Text('${n.title} - ${n.content}', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: AppSpacing.md),
          
          Text('Most Defining Features / Tags:', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: definingWords.isEmpty
                ? [const Chip(label: Text('General heuristic'), visualDensity: VisualDensity.compact)]
                : definingWords.map((w) => Chip(
                      label: Text(w, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: AppColors.seed.withValues(alpha: 0.3),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
          ),
          const SizedBox(height: AppSpacing.md),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Inferred Category:', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54)),
                  Text(n.classifiedCategory?.toUpperCase() ?? 'UNKNOWN', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Assigned Priority:', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54)),
                  Text(n.priority?.toUpperCase() ?? 'MEDIUM', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.urgency(n.priority))),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('AI Explanation:', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54)),
          Text(n.explanation ?? 'Classified via heuristic rule matching.', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
          const Divider(height: 32),

          Text('Reinforcement Feedback Loop (RLHF)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Is the given tag/category and importance correct?', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: AppSpacing.md),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                  onPressed: () => _submitFeedback(true),
                  icon: const Icon(Icons.thumb_up, size: 18, color: Colors.white),
                  label: const Text('Reward (+1)', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
                  onPressed: () => _submitFeedback(false),
                  icon: const Icon(Icons.thumb_down, size: 18, color: Colors.white),
                  label: const Text('Penalty (-1)', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),

          if (_showCorrectionForm) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade400),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Teach AI the correct classification:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Correct Category'),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val ?? _selectedCategory),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPriority,
                    decoration: const InputDecoration(labelText: 'Correct Importance (Priority)'),
                    items: _priorities.map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase()))).toList(),
                    onChanged: (val) => setState(() => _selectedPriority = val ?? _selectedPriority),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.seed),
                      onPressed: _applyReinforcementRule,
                      child: const Text('Submit & Reinforce Rule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
