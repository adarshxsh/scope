import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:scope/widgets/empty_state.dart';
import 'package:scope/widgets/notification_insight_card.dart';

/// Search across captured notifications.
class SearchScreen extends StatefulWidget {
  final NotificationController controller;

  const SearchScreen({super.key, required this.controller});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = widget.controller.search(_query);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            SearchBar(
              controller: _queryController,
              hintText: 'Search notifications...',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _query.trim().isEmpty
                  ? const EmptyState(
                      icon: Icons.search_outlined,
                      title: 'Search your notifications',
                      message: 'Find anything by title, content, or app name.',
                    )
                  : results.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off_outlined,
                          title: "You're all caught up.",
                          message: 'No results for "$_query".',
                        )
                      : ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final notification = results[index];
                            return NotificationInsightCard(
                              notification: notification,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NotificationDetailScreen(
                                      notification: notification,
                                      controller: widget.controller,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
