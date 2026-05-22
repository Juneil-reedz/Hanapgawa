/// Converts any exception or error into a short, user-readable sentence.
/// Strips technical prefixes and maps network / HTTP errors to plain English.
String friendlyError(Object e) {
  final raw = e.toString().replaceFirst('Exception: ', '').trim();
  final lower = raw.toLowerCase();

  // Network / DNS failures
  if (lower.contains('enotfound') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('no address associated')) {
    return 'No internet connection. Please check your network.';
  }
  if (lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed before') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('handshakeexception')) {
    return 'Could not connect to the server. Please try again.';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return 'Request timed out. Please try again.';
  }

  // Non-JSON / server unavailable
  if (lower.contains('server is not responding') ||
      lower.contains('make sure the backend')) {
    return 'Server is temporarily unavailable. Please try again later.';
  }

  // Auth / session errors
  if (lower.contains('(401)') ||
      lower.contains('unauthorized') ||
      lower.contains('jwt expired') ||
      lower.contains('invalid token') ||
      lower.contains('token expired')) {
    return 'Your session has expired. Please log in again.';
  }

  // Permission errors
  if (lower.contains('(403)') || lower.contains('forbidden')) {
    return "You don't have permission to do that.";
  }

  // Not found
  if (raw == 'Request failed (404).' || lower == 'not found') {
    return 'This item could not be found.';
  }

  // Rate limiting
  if (lower.contains('(429)') || lower.contains('too many requests')) {
    return 'Too many requests. Please wait a moment and try again.';
  }

  // Generic server errors
  if (lower.contains('(500)') ||
      lower.contains('(502)') ||
      lower.contains('(503)') ||
      lower.contains('internal server')) {
    return 'Something went wrong on our end. Please try again.';
  }

  // Any other "Request failed (XXX)"
  if (raw.startsWith('Request failed (')) {
    return 'Request failed. Please try again.';
  }

  // Message from our own backend — already human-readable, pass through
  return raw.isEmpty ? 'Something went wrong. Please try again.' : raw;
}

Map<String, dynamic> asMap(Object? value) => value is Map<String, dynamic>
    ? value
    : value is Map
        ? value.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

List<T> listOf<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List ? value.map((item) => parse(asMap(item))).toList() : <T>[];

List<String> stringList(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];

List<String> splitCsv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return double.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

int? nullableInt(Object? value) => value == null ? null : asInt(value);

DateTime parseDate(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

String formatDate(DateTime value) =>
    '${value.month}/${value.day}/${value.year}';

String formatDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final min = value.minute.toString().padLeft(2, '0');
  final ampm = value.hour < 12 ? 'AM' : 'PM';
  return '${formatDate(value)} $hour:$min $ampm';
}

String timeAgo(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return formatDate(value);
}
