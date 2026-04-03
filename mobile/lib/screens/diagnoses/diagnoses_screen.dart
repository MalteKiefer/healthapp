import 'package:flutter/material.dart';

class DiagnosesScreen extends StatelessWidget {
  final String profileId;
  const DiagnosesScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnoses'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_hospital_outlined,
                    size: 40, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Text('Coming Soon', style: tt.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Diagnosis tracking will be available in a future update.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
