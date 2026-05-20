import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_card.dart';

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.api, required this.target});
  final MarketplaceApi api;
  final BookingTarget target;

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final _location = TextEditingController();
  final _notes = TextEditingController();
  var _municipality = 'Bongao';
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _municipality = widget.target.municipality.isEmpty
        ? 'Bongao'
        : widget.target.municipality;
  }

  @override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime? get _scheduledAt {
    if (_scheduledDate == null) return null;
    final time = _scheduledTime ?? const TimeOfDay(hour: 8, minute: 0);
    return DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select service date',
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Select service time',
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  Future<void> _book() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.createBooking(BookingPayload(
        providerUserId: widget.target.providerUserId,
        serviceListingId: widget.target.serviceListingId,
        serviceCategory: widget.target.category,
        municipality: _municipality,
        locationDetails: _location.text,
        notes: _notes.text,
        scheduledAt: _scheduledAt,
      ));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
          const SnackBar(content: Text('Booking request sent. Awaiting provider confirmation.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirect = widget.target.allowDirectBooking;
    final dateLabel = _scheduledDate == null
        ? 'Select date'
        : DateFormat('EEE, MMM d, yyyy').format(_scheduledDate!);
    final timeLabel = _scheduledTime == null
        ? 'Select time'
        : _scheduledTime!.format(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isDirect ? 'Book Now' : 'Book Provider',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(widget.target.title,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(widget.target.displayName ?? 'Provider',
                style: const TextStyle(color: appMuted)),
            if (isDirect) ...[
              const SizedBox(height: 8),
              AppCard(
                accentColor: appPrimary,
                child: const Row(children: [
                  Icon(Icons.bolt, color: appPrimary, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This provider accepts direct bookings. Submit your details and they will confirm shortly.',
                      style: TextStyle(fontSize: 12, color: appPrimary),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _municipality,
              decoration: const InputDecoration(labelText: 'Municipality'),
              items: municipalities
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _municipality = value ?? _municipality),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _location,
                decoration:
                    const InputDecoration(labelText: 'Location details')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(dateLabel,
                        style: TextStyle(
                            color: _scheduledDate == null ? appMuted : null)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _scheduledDate == null ? null : _pickTime,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Time',
                      prefixIcon: const Icon(Icons.access_time_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      enabled: _scheduledDate != null,
                    ),
                    child: Text(timeLabel,
                        style: TextStyle(
                            color: _scheduledTime == null ? appMuted : null)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _book,
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text(isDirect ? 'Book Now' : 'Send Booking Request'),
            ),
          ],
        ),
      ),
    );
  }
}
