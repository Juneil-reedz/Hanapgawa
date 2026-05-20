import 'package:flutter/material.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/models/models.dart';
import '../../core/theme.dart';

class ChatSheet extends StatefulWidget {
  const ChatSheet(
      {super.key,
      required this.api,
      required this.conversation,
      required this.title});
  final MarketplaceApi api;
  final Conversation conversation;
  final String title;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _reply = TextEditingController();
  var _messages = <ConversationMessage>[];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _messages =
        await widget.api.getConversationMessages(widget.conversation.id);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    final message = await widget.api
        .sendConversationMessage(widget.conversation.id, _reply.text.trim());
    setState(() {
      _messages = [..._messages, message];
      _reply.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(children: [
        AppBar(
          title: Text(widget.title),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close))
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _messages.map((message) {
                    final mine =
                        message.senderUserId == widget.api.storedUser?.id;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          color: mine ? appPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          message.message,
                          style: TextStyle(
                              color: mine ? Colors.white : Colors.black87),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              12, 8, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: _reply,
                    minLines: 1,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(hintText: 'Type a message...'))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
          ]),
        ),
      ]),
    );
  }
}
