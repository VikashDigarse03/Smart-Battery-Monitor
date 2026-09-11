import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Reports screen — placeholder for Excel/PDF report generation.
class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assessment_outlined,
                size: 72,
                color: AppTheme.textMuted,
              ),
              const SizedBox(height: 20),
              Text(
                'Reports',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Excel and PDF report generation will be implemented in Phase 4.',
                style: TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.table_chart),
                label: const Text('Export Excel'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
