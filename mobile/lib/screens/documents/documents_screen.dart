import 'package:flutter/material.dart';

class DocumentsScreen extends StatelessWidget {
  final String profileId;
  const DocumentsScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 48),
            SizedBox(height: 16),
            Text('Coming Soon', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
