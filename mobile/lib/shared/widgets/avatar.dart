import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.label,
    this.name,
    this.imageData,
    this.size = 44,
    this.radius,
    this.color = appPrimary,
  });
  final String? label;
  final String? name;
  final String? imageData;
  final double size;
  final double? radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size / 2;
    final displayLabel = label ?? _initials;

    ImageProvider? img;
    if (imageData != null && imageData!.isNotEmpty) {
      try {
        img = MemoryImage(base64Decode(imageData!));
      } catch (_) {}
    }

    return CircleAvatar(
      radius: r,
      backgroundColor: color,
      backgroundImage: img,
      child: img == null
          ? Text(
              displayLabel,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: r / 1.75,
              ),
            )
          : null,
    );
  }

  String get _initials {
    final n = name ?? '';
    if (n.isEmpty) return '?';
    final parts = n.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return n[0].toUpperCase();
  }
}
