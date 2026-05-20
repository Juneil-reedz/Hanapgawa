import 'package:flutter/material.dart';

import '../../core/theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(status.replaceAll('_', ' ')),
        visualDensity: VisualDensity.compact,
        backgroundColor: appSurface,
        side: const BorderSide(color: Color(0xFFE6DADF)),
      );
}
