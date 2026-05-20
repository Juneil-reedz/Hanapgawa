import 'package:flutter/material.dart';

import '../../core/local/local_db.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../shared/widgets/empty_state.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  var _items = <Map<String, dynamic>>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await LocalDb.instance.getFavorites();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    await LocalDb.instance.removeFavorite(
        item['id']?.toString() ?? '', item['type']?.toString() ?? '');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border,
                  title: 'Nothing saved yet',
                  subtitle: 'Tap the Save button on any post to bookmark it here.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _SavedTile(
                      item: _items[i],
                      onRemove: () => _remove(_items[i]),
                    ),
                  ),
                ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.item, required this.onRemove});
  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  IconData get _typeIcon {
    switch (item['type']?.toString()) {
      case 'listing':
        return Icons.work_outline;
      case 'job':
        return Icons.newspaper_outlined;
      case 'review':
        return Icons.star_outline;
      case 'social':
        return Icons.chat_bubble_outline;
      default:
        return Icons.bookmark_border;
    }
  }

  String get _typeLabel {
    switch (item['type']?.toString()) {
      case 'listing':
        return 'Service';
      case 'job':
        return 'Job Post';
      case 'review':
        return 'Review';
      case 'social':
        return 'Post';
      default:
        return 'Saved';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? 'Saved item';
    final subtitle = item['subtitle']?.toString() ?? '';
    final category = item['category']?.toString();
    final municipality = item['municipality']?.toString();
    final createdAt = item['createdAt'] != null
        ? timeAgo(DateTime.tryParse(item['createdAt'].toString()) ?? DateTime.now())
        : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: appPrimary.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_typeIcon, size: 20, color: appPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: appPrimary.withAlpha(12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_typeLabel,
                        style: TextStyle(
                            color: appPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  if (createdAt.isNotEmpty)
                    Text(createdAt,
                        style: const TextStyle(color: appMuted, fontSize: 11)),
                ]),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: appMuted, fontSize: 12)),
                ],
                if (category != null || municipality != null) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    if (category != null)
                      _Pill(Icons.category_outlined, category),
                    if (municipality != null)
                      _Pill(Icons.place_outlined, municipality),
                  ]),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.bookmark_remove_outlined, color: appMuted),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: appMuted),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(color: appMuted, fontSize: 11)),
        ],
      );
}
