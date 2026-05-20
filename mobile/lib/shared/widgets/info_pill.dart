import 'package:flutter/material.dart';

import '../../core/theme.dart';

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: appPrimary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: appMuted)),
        ],
      );
}
