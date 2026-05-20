import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/theme.dart';

const _kReasons = [
  'Spam or scam',
  'Harassment or bullying',
  'Fake account or impersonation',
  'Inappropriate content',
  'Violence or dangerous activity',
  'Other',
];

Future<void> showReportSheet(
  BuildContext context, {
  required MarketplaceApi api,
  required String reportedUserId,
  String? contentType,
  String? contentId,
  String contentLabel = 'this content',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      api: api,
      reportedUserId: reportedUserId,
      contentType: contentType,
      contentId: contentId,
      contentLabel: contentLabel,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.api,
    required this.reportedUserId,
    this.contentType,
    this.contentId,
    required this.contentLabel,
  });
  final MarketplaceApi api;
  final String reportedUserId;
  final String? contentType;
  final String? contentId;
  final String contentLabel;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = _kReasons.first;
  final _details = TextEditingController();
  var _submitting = false;
  var _done = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await widget.api.submitReport(
        providerUserId: widget.reportedUserId,
        contentType: widget.contentType,
        contentId: widget.contentId,
        reason: _reason,
        details: _details.text.trim().isEmpty
            ? 'Reported: ${widget.contentLabel}'
            : _details.text.trim(),
      );
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e))));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(top: false, child: _done ? _success() : _form()),
        ),
      );

  Widget _success() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: Colors.green.withAlpha(22), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline,
                color: Colors.green, size: 32),
          ),
          const SizedBox(height: 16),
          const Text('Report submitted',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'Thank you. Our team will review this and take appropriate action.',
            textAlign: TextAlign.center,
            style: TextStyle(color: appMuted, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ),
        ],
      );

  Widget _form() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          const SizedBox(height: 16),
          Text('Report ${widget.contentLabel}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          const Text('Help us understand the problem.',
              style: TextStyle(color: appMuted, fontSize: 13)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: _kReasons
                .map((r) =>
                    DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _reason = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Additional details (optional)',
              hintText: 'Describe the issue…',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Report'),
            ),
          ),
        ],
      );

  Widget _handle() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
      );
}
