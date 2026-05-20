import 'package:flutter/material.dart';

import '../../core/theme.dart';

class FeedHeader extends StatelessWidget {
  const FeedHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.color,
  });
  final String name;
  final String subtitle;
  final String badge;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.alphaBlend(Colors.white24, color)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                name.length >= 2
                    ? name.substring(0, 2).toUpperCase()
                    : name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 12, color: appMuted),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(subtitle,
                        style: const TextStyle(color: appMuted, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 126),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withAlpha(72)),
              ),
              child: Text(
                badge.replaceAll('_', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      );
}
