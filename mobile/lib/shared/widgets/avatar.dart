import 'package:flutter/material.dart';

import '../../core/theme.dart';

class Avatar extends StatelessWidget {
  const Avatar(
      {super.key,
      required this.label,
      this.size = 44,
      this.color = appPrimary});
  final String label;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: color,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size / 3.5,
          ),
        ),
      );
}
