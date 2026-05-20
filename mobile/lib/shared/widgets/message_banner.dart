import 'package:flutter/material.dart';

class MessageBanner extends StatelessWidget {
  const MessageBanner(
      {super.key, required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? const Color(0xFFFCE8ED) : const Color(0xFFEAF8EF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ]),
      );
}
