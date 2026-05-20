import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'chat_screen.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.api,
    required this.conversation,
    required this.isUnread,
    required this.isPinned,
    required this.onDeleted,
    required this.onTogglePin,
    required this.onToggleRead,
    required this.onOpened,
  });

  final MarketplaceApi api;
  final Conversation conversation;
  final bool isUnread;
  final bool isPinned;
  final VoidCallback onDeleted;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleRead;
  final VoidCallback onOpened;

  String _otherName() =>
      conversation.clientUserId == api.storedUser?.id
          ? conversation.providerName ?? 'User'
          : conversation.clientName ?? 'User';

  String _displayName() {
    final nick = conversation.otherNickname;
    return (nick != null && nick.isNotEmpty) ? nick : _otherName();
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  void _openChat(BuildContext context) async {
    final name = _otherName();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
            api: api,
            conversation: conversation,
            title: name),
      ),
    );
    onOpened();
    if (result == 'deleted') onDeleted();
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: isPinned ? appPrimary : null,
            ),
            title: Text(isPinned ? 'Unpin conversation' : 'Pin conversation'),
            onTap: () {
              Navigator.pop(ctx);
              onTogglePin();
            },
          ),
          ListTile(
            leading: Icon(
              isUnread
                  ? Icons.mark_chat_read_outlined
                  : Icons.mark_chat_unread_outlined,
              color: isUnread ? Colors.green : appPrimary,
            ),
            title: Text(isUnread ? 'Mark as read' : 'Mark as unread'),
            onTap: () {
              Navigator.pop(ctx);
              onToggleRead();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title:
                const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context);
            },
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('All messages will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    ).then((confirm) async {
      if (confirm != true) return;
      await api.deleteConversation(conversation.id);
      onDeleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName();
    final initials = _initials(name);

    return InkWell(
      onTap: () => _openChat(context),
      onLongPress: () => _showOptions(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: isUnread
              ? const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF9F67FF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isUnread ? null : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade100, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with unread / pin badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        appPrimary,
                        appPrimary.withAlpha(180),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (isUnread)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3)),
                    ),
                  ),
                if (isPinned)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.push_pin,
                          color: Colors.white, size: 9),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 15,
                            color: isUnread ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeAgo(conversation.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: isUnread
                              ? Colors.white70
                              : appMuted,
                          fontWeight: isUnread
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessagePreview.isEmpty
                              ? 'No messages yet'
                              : conversation.lastMessagePreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isUnread
                                ? Colors.white70
                                : Colors.grey.shade500,
                            fontWeight: isUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Three-dot menu
            GestureDetector(
              onTap: () => _showOptions(context),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: isUnread ? Colors.white60 : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
