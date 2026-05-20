import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';

class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.api,
    required this.booking,
    required this.reviewedName,
    this.onDone,
  });
  final MarketplaceApi api;
  final Booking booking;
  final String reviewedName;
  final VoidCallback? onDone;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  var _rating = 0;
  final _comment = TextEditingController();
  var _submitting = false;

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a star rating.')));
      return;
    }
    setState(() => _submitting = true);

    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('submit_review', {
        'bookingId': widget.booking.id,
        'rating': _rating,
        'comment': _comment.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onDone?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Review queued — will submit when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    try {
      await widget.api.submitReview(
        bookingId: widget.booking.id,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onDone?.call();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted. Thank you!')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(error))));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Avatar + name
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [appPrimary, appSecondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
              ),
              child: Center(
                child: Text(
                  widget.reviewedName.isNotEmpty
                      ? widget.reviewedName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  'Rate ${widget.reviewedName}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Text('Your review helps build trust in the community.',
                    style: TextStyle(fontSize: 12, color: appMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          // Star picker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final filled = index < _rating;
              return GestureDetector(
                onTap: () => setState(() => _rating = index + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: filled ? Colors.orange : Colors.grey.shade300,
                    size: 46,
                  ),
                ),
              );
            }),
          ),
          if (_rating > 0) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                _labels[_rating],
                style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Share your experience...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.star_rounded, size: 18),
            label: const Text('Submit Review'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}
