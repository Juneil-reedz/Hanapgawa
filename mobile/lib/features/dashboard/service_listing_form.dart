import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_card.dart';

class ServiceListingForm extends StatelessWidget {
  const ServiceListingForm({
    super.key,
    required this.title,
    required this.description,
    required this.category,
    required this.priceMin,
    required this.priceMax,
    required this.municipality,
    required this.onMunicipality,
    required this.onSave,
    required this.allowDirectBooking,
    required this.onAllowDirectBooking,
  });
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController category;
  final TextEditingController priceMin;
  final TextEditingController priceMax;
  final String municipality;
  final ValueChanged<String> onMunicipality;
  final VoidCallback onSave;
  final bool allowDirectBooking;
  final ValueChanged<bool> onAllowDirectBooking;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Service Listing',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title')),
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
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: priceMin,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min price'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: priceMax,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Max price'))),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: allowDirectBooking
                    ? appPrimary.withAlpha(12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: allowDirectBooking
                      ? appPrimary.withAlpha(60)
                      : Colors.grey.shade300,
                ),
              ),
              child: SwitchListTile(
                value: allowDirectBooking,
                onChanged: onAllowDirectBooking,
                activeColor: appPrimary,
                title: const Text(
                  'Allow clients to book me directly',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  allowDirectBooking
                      ? 'Clients will see a "Book Now" button on this listing.'
                      : 'Clients can message you or wait for your response.',
                  style: TextStyle(
                      fontSize: 12,
                      color: allowDirectBooking ? appPrimary : Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
                onPressed: onSave,
                child: const Text('Publish Service Listing')),
          ],
        ),
      );
}
