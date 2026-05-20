import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite database for offline-first caching and pending action queue.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'hanapgawa_v1.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (d, _) async {
        await _createV1Tables(d);
        await _createV2Tables(d);
        await _createV3Tables(d);
      },
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2Tables(d);
        if (oldVersion < 3) await _createV3Tables(d);
      },
    );
  }

  Future<void> _createV1Tables(Database d) async {
    await d.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        icon TEXT DEFAULT '',
        active INTEGER DEFAULT 1,
        synced_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE cached_feed (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        data_json TEXT NOT NULL,
        item_created_at INTEGER NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE favorites (
        id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        type TEXT NOT NULL,
        data_json TEXT NOT NULL,
        saved_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE pending_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending_sync',
        created_at INTEGER NOT NULL,
        attempts INTEGER DEFAULT 0
      )
    ''');
    await d.execute('''
      CREATE TABLE cached_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE cached_notifications (
        id TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        is_read INTEGER DEFAULT 0,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE cached_user (
        id TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createV2Tables(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS cached_bookings (
        id TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS cached_conversations (
        id TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS cached_jobs (
        id TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS cached_admin_data (
        key TEXT PRIMARY KEY,
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createV3Tables(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS kv_store (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ── Settings (key-value) ────────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('kv_store', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('kv_store', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  Future<void> upsertCategories(List<Map<String, dynamic>> cats) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final cat in cats) {
      batch.insert(
        'categories',
        {
          'id': cat['id']?.toString() ?? '',
          'name': cat['name']?.toString() ?? '',
          'description': cat['description']?.toString() ?? '',
          'icon': cat['icon']?.toString() ?? '',
          'active': (cat['active'] == true || cat['active'] == 1) ? 1 : 0,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final d = await db;
    return d.query('categories', orderBy: 'name ASC');
  }

  Future<bool> hasCategories() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) as c FROM categories');
    return (Sqflite.firstIntValue(r) ?? 0) > 0;
  }

  // ── Feed cache ─────────────────────────────────────────────────────────────

  Future<void> cacheFeedItems(List<Map<String, dynamic>> items) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final item in items) {
      final createdAt = _parseMs(item['createdAt']) ?? now;
      batch.insert(
        'cached_feed',
        {
          'id': item['id']?.toString() ?? '$now',
          'type': item['type']?.toString() ?? 'unknown',
          'data_json': jsonEncode(item),
          'item_created_at': createdAt,
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedFeed({int limit = 40}) async {
    final d = await db;
    final rows = await d.query(
      'cached_feed',
      orderBy: 'item_created_at DESC',
      limit: limit,
    );
    return rows
        .map((r) =>
            jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<void> clearOldFeedCache({int keepDays = 7}) async {
    final d = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: keepDays))
        .millisecondsSinceEpoch;
    await d.delete('cached_feed',
        where: 'cached_at < ?', whereArgs: [cutoff]);
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  Future<void> saveFavorite(
      String postId, String type, Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(
      'favorites',
      {
        'id': '${type}_$postId',
        'post_id': postId,
        'type': type,
        'data_json': jsonEncode(data),
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String postId, String type) async {
    final d = await db;
    await d.delete('favorites',
        where: 'id = ?', whereArgs: ['${type}_$postId']);
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final d = await db;
    final rows =
        await d.query('favorites', orderBy: 'saved_at DESC');
    return rows
        .map((r) =>
            jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<bool> isFavorite(String postId, String type) async {
    final d = await db;
    final rows = await d
        .query('favorites', where: 'id = ?', whereArgs: ['${type}_$postId']);
    return rows.isNotEmpty;
  }

  // ── Pending actions ────────────────────────────────────────────────────────

  Future<int> queueAction(
      String actionType, Map<String, dynamic> payload) async {
    final d = await db;
    return d.insert('pending_actions', {
      'action_type': actionType,
      'payload_json': jsonEncode(payload),
      'status': 'pending_sync',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final d = await db;
    return d.query(
      'pending_actions',
      where: 'status = ? AND attempts < 3',
      whereArgs: ['pending_sync'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markActionSynced(int id) async {
    final d = await db;
    await d.update(
      'pending_actions',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markActionFailed(int id) async {
    final d = await db;
    await d.rawUpdate(
      "UPDATE pending_actions SET attempts = attempts + 1, "
      "status = CASE WHEN attempts + 1 >= 3 THEN 'sync_failed' "
      "ELSE 'pending_sync' END WHERE id = ?",
      [id],
    );
  }

  Future<void> markActionPermanentlyFailed(int id) async {
    final d = await db;
    await d.update(
      'pending_actions',
      {'status': 'sync_failed', 'attempts': 3},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getPendingCount() async {
    final d = await db;
    final r = await d.rawQuery(
      "SELECT COUNT(*) as c FROM pending_actions "
      "WHERE status = 'pending_sync' AND attempts < 3",
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<void> cacheMessages(
      String conversationId, List<Map<String, dynamic>> messages) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final msg in messages) {
      batch.insert(
        'cached_messages',
        {
          'id': msg['id']?.toString() ?? '${conversationId}_$now',
          'conversation_id': conversationId,
          'data_json': jsonEncode(msg),
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedMessages(
      String conversationId) async {
    final d = await db;
    final rows = await d.query(
      'cached_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'cached_at ASC',
    );
    return rows
        .map((r) =>
            jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  Future<void> cacheNotifications(
      List<Map<String, dynamic>> notifications) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final notif in notifications) {
      batch.insert(
        'cached_notifications',
        {
          'id': notif['id']?.toString() ?? '$now',
          'data_json': jsonEncode(notif),
          'is_read': (notif['isRead'] == true) ? 1 : 0,
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedNotifications() async {
    final d = await db;
    final rows = await d.query(
      'cached_notifications',
      orderBy: 'cached_at DESC',
      limit: 50,
    );
    return rows
        .map((r) =>
            jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── User profile ───────────────────────────────────────────────────────────

  Future<void> cacheUser(String userId, Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(
      'cached_user',
      {
        'id': userId,
        'data_json': jsonEncode(data),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedUser(String userId) async {
    final d = await db;
    final rows =
        await d.query('cached_user', where: 'id = ?', whereArgs: [userId]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['data_json'] as String)
        as Map<String, dynamic>;
  }

  // ── Bookings ───────────────────────────────────────────────────────────────

  Future<void> cacheBookings(List<Map<String, dynamic>> items) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    await d.delete('cached_bookings');
    for (final item in items) {
      batch.insert(
        'cached_bookings',
        {
          'id': item['id']?.toString() ?? '$now',
          'data_json': jsonEncode(item),
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedBookings() async {
    final d = await db;
    final rows = await d.query('cached_bookings', orderBy: 'cached_at DESC');
    return rows
        .map((r) => jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── Conversations ──────────────────────────────────────────────────────────

  Future<void> cacheConversations(List<Map<String, dynamic>> items) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    await d.delete('cached_conversations');
    for (final item in items) {
      batch.insert(
        'cached_conversations',
        {
          'id': item['id']?.toString() ?? '$now',
          'data_json': jsonEncode(item),
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedConversations() async {
    final d = await db;
    final rows = await d.query('cached_conversations', orderBy: 'cached_at DESC');
    return rows
        .map((r) => jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── Jobs ───────────────────────────────────────────────────────────────────

  Future<void> cacheJobs(List<Map<String, dynamic>> items) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    await d.delete('cached_jobs');
    for (final item in items) {
      batch.insert(
        'cached_jobs',
        {
          'id': item['id']?.toString() ?? '$now',
          'data_json': jsonEncode(item),
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedJobs() async {
    final d = await db;
    final rows = await d.query('cached_jobs', orderBy: 'cached_at DESC');
    return rows
        .map((r) => jsonDecode(r['data_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── Admin data ─────────────────────────────────────────────────────────────

  Future<void> cacheAdminData(String key, dynamic data) async {
    final d = await db;
    await d.insert(
      'cached_admin_data',
      {
        'key': key,
        'data_json': jsonEncode(data),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getCachedAdminData(String key) async {
    final d = await db;
    final rows = await d.query('cached_admin_data', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['data_json'] as String);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int? _parseMs(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return null;
  }
}
