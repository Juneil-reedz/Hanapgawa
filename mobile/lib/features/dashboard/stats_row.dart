import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme.dart';

class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.bookings});
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: StatCard(label: 'Total', value: bookings.length.toString())),
        const SizedBox(width: 8),
        Expanded(
            child: StatCard(
                label: 'Pending',
                value: bookings
                    .where((b) => b.status == 'pending')
                    .length
                    .toString())),
        const SizedBox(width: 8),
        Expanded(
            child: StatCard(
                label: 'Done',
                value: bookings
                    .where((b) => b.status == 'completed')
                    .length
                    .toString())),
      ]);
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: appPrimary)),
            Text(label, style: const TextStyle(color: appMuted)),
          ]),
        ),
      );
}
