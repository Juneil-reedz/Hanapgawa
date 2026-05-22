import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/theme.dart';

class RateFeedbackSheet extends StatefulWidget {
  const RateFeedbackSheet({super.key, required this.api});
  final MarketplaceApi api;

  @override
  State<RateFeedbackSheet> createState() => _RateFeedbackSheetState();
}

class _RateFeedbackSheetState extends State<RateFeedbackSheet> {
  var _rating = 0;
  final _commentCtrl = TextEditingController();
  var _submitting = false;
  var _submitted = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.api.submitFeedback(_rating, _commentCtrl.text.trim());
      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: _submitted ? _buildThanks() : _buildForm(),
      ),
    );
  }

  Widget _buildThanks() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, color: appPrimary, size: 56),
        const SizedBox(height: 16),
        const Text('Thank you!',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: appPrimary)),
        const SizedBox(height: 8),
        const Text(
          'Your feedback helps us improve HanapGawa.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: appPrimary),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final labels = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Text('Rate HanapGawa',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: appPrimary)),
        const SizedBox(height: 4),
        const Text(
          'Your feedback is anonymous and helps us improve the app.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 20),
        // Star rating
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            return GestureDetector(
              onTap: () => setState(() => _rating = star),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 42,
                  color: star <= _rating ? const Color(0xFFFFC107) : Colors.grey.shade400,
                ),
              ),
            );
          }),
        ),
        if (_rating > 0) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              labels[_rating - 1],
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: appPrimary,
                  fontSize: 14),
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _commentCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'Tell us more (optional)…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: appPrimary,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit Feedback',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
