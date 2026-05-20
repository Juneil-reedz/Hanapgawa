import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../shared/widgets/app_card.dart';

class ProviderProfileForm extends StatelessWidget {
  const ProviderProfileForm({
    super.key,
    required this.displayName,
    required this.category,
    required this.services,
    required this.municipality,
    required this.onMunicipality,
    required this.onSave,
  });
  final TextEditingController displayName;
  final TextEditingController category;
  final TextEditingController services;
  final String municipality;
  final ValueChanged<String> onMunicipality;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Provider Profile',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
                controller: displayName,
                decoration: const InputDecoration(labelText: 'Display name')),
            const SizedBox(height: 10),
            TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Category')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: municipality,
              decoration: const InputDecoration(labelText: 'Municipality'),
              items: municipalities
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (value) => onMunicipality(value ?? municipality),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: services,
                decoration: const InputDecoration(
                    labelText: 'Services (comma-separated)')),
            const SizedBox(height: 14),
            FilledButton(
                onPressed: onSave, child: const Text('Save Worker Profile')),
          ],
        ),
      );
}
