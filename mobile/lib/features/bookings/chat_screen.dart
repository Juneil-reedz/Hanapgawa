import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/marketplace_api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_service.dart';
import '../../core/models/models.dart';
import 'video_call_screen.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.conversation,
    required this.title,
  });
  final MarketplaceApi api;
  final Conversation conversation;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  Timer? _refreshTimer;

  var _messages = <ConversationMessage>[];
  var _loading = true;
  String? _pendingImage;
  var _recording = false;
  DateTime? _recordStartedAt;
  ConversationMessage? _replyingTo;
  ConversationMessage? _pinnedMessage;
  final _reactions = <String, String>{};

  // Chat customisation
  Color _accentColor = appPrimary;
  var _muted = false;
  // Map of targetUserId → nickname (shared across both participants)
  var _nicknames = <String, String>{};
  var _searchMode = false;
  var _searchQuery = '';
  final _searchCtrl = TextEditingController();

  String get _myId => widget.api.storedUser?.id ?? '';
  String get _otherUserId =>
      widget.conversation.clientUserId == _myId
          ? widget.conversation.providerUserId
          : widget.conversation.clientUserId;

  String get _displayTitle {
    final nick = _nicknames[_otherUserId];
    return (nick != null && nick.isNotEmpty) ? nick : widget.title;
  }
  List<ConversationMessage> get _visibleMessages {
    if (!_searchMode || _searchQuery.isEmpty) return _messages;
    return _messages
        .where(
            (m) => m.message.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadNicknames();
    _load();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _load(showSpinner: false));
  }

  Future<void> _loadNicknames() async {
    try {
      final list = await widget.api
          .getConversationNicknames(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _nicknames = {for (final n in list) n.targetUserId: n.nickname};
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final msgs =
          await widget.api.getConversationMessages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
      // Cache for offline use
      LocalDb.instance.cacheMessages(
        widget.conversation.id,
        msgs.map((m) => m.toJson()).toList(),
      );
    } catch (_) {
      if (!mounted) return;
      // Fall back to locally cached messages
      final cached = await LocalDb.instance
          .getCachedMessages(widget.conversation.id);
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _messages = cached.map(ConversationMessage.fromJson).toList();
          _loading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _loading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    setState(() => _pendingImage = base64Encode(bytes));
  }

  void _clearPendingImage() => setState(() => _pendingImage = null);

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    final image = _pendingImage;
    final reply = _replyingTo;
    setState(() {
      _textCtrl.clear();
      _pendingImage = null;
      _replyingTo = null;
    });

    // Queue offline
    if (!SyncService.instance.isOnline) {
      await LocalDb.instance.queueAction('send_message', {
        'conversationId': widget.conversation.id,
        'content': text,
        if (image != null) 'image': image,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Message queued — will send when online'),
          ]),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    try {
      final msg = await widget.api.sendConversationMessage(
        widget.conversation.id,
        text,
        image: image,
        replyToMessageId: reply?.id,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      if (SyncService.isNetworkError(e)) {
        await LocalDb.instance.queueAction('send_message', {
          'conversationId': widget.conversation.id,
          'content': text,
          if (image != null) 'image': image,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.sync, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('Message queued — will send when online')),
          ]),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      final started = _recordStartedAt;
      setState(() {
        _recording = false;
        _recordStartedAt = null;
      });
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      final duration = started == null
          ? 0
          : DateTime.now().difference(started).inSeconds.clamp(1, 600);
      try {
        final msg = await widget.api.sendConversationMessage(
          widget.conversation.id,
          '',
          voiceMessage: base64Encode(bytes),
          voiceDuration: duration,
        );
        if (!mounted) return;
        setState(() => _messages = [..._messages, msg]);
        _scrollToBottom();
      } catch (e) {
        if (mounted) _snack(friendlyError(e));
      }
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _snack('Microphone permission is required for voice messages.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    setState(() {
      _recording = true;
      _recordStartedAt = DateTime.now();
    });
  }

  Future<void> _playVoice(ConversationMessage msg) async {
    final voice = msg.voiceMessage;
    if (voice == null || voice.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/play_${msg.id}.m4a';
    final file = File(path);
    if (!await file.exists()) await file.writeAsBytes(base64Decode(voice));
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  Future<void> _startVideoCall() async {
    final room = 'hanapgawa-${widget.conversation.id}';
    try {
      final data = await widget.api.createLiveKitToken(room);
      final msg = await widget.api.sendConversationMessage(
        widget.conversation.id,
        '📹 Video call started. Tap to join.',
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      await _joinVideoCall(room, data);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _joinVideoCall(String room, [Map<String, dynamic>? existingData]) async {
    try {
      final data = existingData ?? await widget.api.createLiveKitToken(room);
      if (!mounted) return;
      final url = data['url']?.toString() ?? '';
      final token = data['token']?.toString() ?? '';
      if (url.isEmpty || token.isEmpty) {
        _snack('Could not get call credentials.');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          url: url,
          token: token,
          room: room,
          displayName: widget.title,
        ),
      ));
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _deleteMessage(ConversationMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.api.deleteConversationMessage(widget.conversation.id, msg.id);
    if (mounted) {
      setState(
          () => _messages = _messages.where((m) => m.id != msg.id).toList());
    }
  }

  Future<void> _editMessage(ConversationMessage msg) async {
    final ctrl = TextEditingController(text: msg.message);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditMessageSheet(
        controller: ctrl,
        accentColor: _accentColor,
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    try {
      final updated = await widget.api
          .editConversationMessage(widget.conversation.id, msg.id, result);
      if (mounted) {
        setState(() => _messages =
            _messages.map((m) => m.id == msg.id ? updated : m).toList());
      }
    } catch (e) {
      if (mounted) {
        _snack(friendlyError(e));
      }
    }
  }

  void _replyTo(ConversationMessage msg) {
    setState(() => _replyingTo = msg);
  }

  ConversationMessage? _messageById(String? id) {
    if (id == null) return null;
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  String _senderName(ConversationMessage message) {
    if (message.senderUserId == _myId) return 'You';
    return widget.title;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _reactTo(ConversationMessage msg, String emoji) {
    setState(() => _reactions[msg.id] = emoji);
    _snack('Reaction added: $emoji');
  }

  Future<void> _copyMessage(ConversationMessage msg) async {
    if (msg.message.trim().isEmpty) {
      _snack('No text to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: msg.message));
    if (mounted) _snack('Message copied.');
  }

  void _pinMessage(ConversationMessage msg) {
    setState(() => _pinnedMessage = msg);
    _snack('Message pinned.');
  }

  Future<void> _reportMessage(ConversationMessage msg) async {
    final details =
        msg.message.isEmpty ? 'Reported media message ${msg.id}' : msg.message;
    try {
      await widget.api.submitReport(
        providerUserId: widget.conversation.providerUserId,
        reason: 'Inappropriate message',
        details: details,
      );
      if (mounted) _snack('Report submitted.');
    } catch (e) {
      if (mounted) {
        _snack(friendlyError(e));
      }
    }
  }

  void _openMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(leading: Icon(Icons.more_horiz), title: Text('More')),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme and chat color'),
            onTap: () {
              Navigator.pop(ctx);
              Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
                if (mounted) _openThemePicker();
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Nicknames'),
            subtitle: _nicknames.isNotEmpty
                ? Text(_nicknames.values.join(', '),
                    maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              // Wait for the close animation (~250ms) before opening the next sheet
              Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
                if (mounted) _openNicknames();
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(_muted ? 'Muted' : 'On'),
            trailing: Switch(
              value: !_muted,
              activeColor: _accentColor,
              onChanged: (_) {
                Navigator.pop(ctx);
                setState(() => _muted = !_muted);
                _snack(_muted ? 'Notifications muted.' : 'Notifications on.');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.perm_media_outlined),
            title: const Text('Media and files'),
            onTap: () {
              Navigator.pop(ctx);
              Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
                if (mounted) _openMediaFiles();
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title:
                const Text('Block user', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
                if (mounted) _blockUser();
              });
            },
          ),
        ]),
      ),
    );
  }

  void _openThemePicker() {
    final colors = [
      appPrimary,
      Colors.blue,
      Colors.green,
      Colors.pink,
      Colors.orange,
      Colors.teal,
      Colors.red,
      Colors.indigo,
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Chat color',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: colors.map((c) {
                final selected = _accentColor == c;
                return GestureDetector(
                  onTap: () {
                    setState(() => _accentColor = c);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Colors.white,
                              width: 3,
                            )
                          : null,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: c.withAlpha(100),
                                  blurRadius: 8,
                                  spreadRadius: 2)
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _openNicknames() async {
    final conv = widget.conversation;
    final myId = _myId;
    final otherId = _otherUserId;
    final myRealName = widget.api.storedUser?.fullName ?? 'You';
    final otherRealName = widget.title;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _NicknameSheet(
        api: widget.api,
        conversationId: conv.id,
        myId: myId,
        otherId: otherId,
        myRealName: myRealName,
        otherRealName: otherRealName,
        initialNicknames: Map.from(_nicknames),
        accentColor: _accentColor,
        onSaved: (updated) {
          if (mounted) setState(() => _nicknames = updated);
        },
      ),
    );
  }

  void _openMediaFiles() {
    final images = _messages.where((m) => m.image != null).toList();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Media and files',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (images.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No media shared yet.',
                  style: TextStyle(color: appMuted)),
            )
          else
            SizedBox(
              height: 280,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: images.length,
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(images[i].image!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _blockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block user?'),
        content:
            Text('You will no longer receive messages from ${widget.title}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.submitReport(
        providerUserId: widget.conversation.providerUserId,
        reason: 'Block user',
        details: 'User blocked ${widget.title}',
      );
      if (mounted) _snack('${widget.title} has been blocked.');
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  void _showMessageMenu(ConversationMessage msg) {
    final mine = msg.senderUserId == _myId;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji reactions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '😡']
                      .map((emoji) => InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _reactTo(msg, emoji);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  _replyTo(msg);
                },
              ),
              if (msg.message.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(msg);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Pin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinMessage(msg);
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(msg);
                  },
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(msg);
                  },
                ),
              if (!mine)
                ListTile(
                  leading:
                      const Icon(Icons.report_outlined, color: Colors.orange),
                  title: const Text('Report'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _reportMessage(msg);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searchMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _searchMode = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                }),
              ),
              title: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search messages...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            )
          : AppBar(
              title: Text(_displayTitle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() {
                    _searchMode = true;
                    _searchQuery = '';
                    _searchCtrl.clear();
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Start video call',
                  onPressed: _startVideoCall,
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete conversation?'),
                          content: const Text(
                              'All messages will be permanently deleted.'),
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
                      );
                      if (confirm == true && mounted) {
                        await widget.api
                            .deleteConversation(widget.conversation.id);
                        if (!mounted) return;
                        // ignore: use_build_context_synchronously
                        Navigator.pop(context, 'deleted');
                      }
                    } else if (value == 'more') {
                      _openMoreOptions();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'more',
                        child: Row(children: [
                          Icon(Icons.tune_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('More options'),
                        ])),
                    PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Delete conversation',
                              style: TextStyle(color: Colors.red)),
                        ])),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (_pinnedMessage != null)
            Material(
              color: appPrimary.withAlpha(18),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.push_pin_outlined, color: appPrimary),
                title: Text(
                  _pinnedMessage!.message.isEmpty
                      ? 'Pinned media'
                      : _pinnedMessage!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _pinnedMessage = null),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: _visibleMessages.length,
                      itemBuilder: (_, i) {
                        final msg = _visibleMessages[i];
                        if (msg.isSystem) {
                          return _SystemMessageRow(text: msg.message);
                        }
                        final isMine = msg.senderUserId == _myId;
                        return _SwipeToReply(
                          isMine: isMine,
                          onReply: () => _replyTo(msg),
                          child: _MessageBubble(
                            message: msg,
                            repliedTo: _messageById(msg.replyToMessageId),
                            repliedToSenderName:
                                _messageById(msg.replyToMessageId) == null
                                    ? null
                                    : _senderName(
                                        _messageById(msg.replyToMessageId)!),
                            senderName: _senderName(msg),
                            reaction: _reactions[msg.id],
                            isMine: isMine,
                            accentColor: _accentColor,
                            onPlayVoice: () => _playVoice(msg),
                            onLongPress: () => _showMessageMenu(msg),
                            onMenuTap: () => _showMessageMenu(msg),
                            onTap: msg.message.contains('📹')
                                ? () => _joinVideoCall(
                                    'hanapgawa-${widget.conversation.id}')
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (_pendingImage != null)
            _PendingImagePreview(
              base64Image: _pendingImage!,
              onRemove: _clearPendingImage,
            ),
          _InputBar(
            controller: _textCtrl,
            replyingTo: _replyingTo,
            onCancelReply: () => setState(() => _replyingTo = null),
            onSend: _send,
            onPickImage: _pickImage,
            onVoice: _toggleRecording,
            recording: _recording,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.repliedTo,
    required this.repliedToSenderName,
    required this.senderName,
    required this.reaction,
    required this.isMine,
    required this.accentColor,
    required this.onPlayVoice,
    required this.onLongPress,
    required this.onMenuTap,
    this.onTap,
  });
  final ConversationMessage message;
  final ConversationMessage? repliedTo;
  final String? repliedToSenderName;
  final String senderName;
  final String? reaction;
  final bool isMine;
  final Color accentColor;
  final VoidCallback onPlayVoice;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          decoration: BoxDecoration(
            color: isMine ? accentColor : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (repliedTo != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 2,
                      height: 30,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.white.withAlpha(100)
                            : accentColor.withAlpha(140),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.reply,
                                size: 11,
                                color: isMine
                                    ? Colors.white.withAlpha(130)
                                    : appMuted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                _replyLabel(senderName, repliedToSenderName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMine
                                      ? Colors.white.withAlpha(130)
                                      : appMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 1),
                          Text(
                            repliedTo!.message.isEmpty
                                ? 'Photo'
                                : repliedTo!.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isMine
                                  ? Colors.white.withAlpha(110)
                                  : Colors.black38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (message.image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    base64Decode(message.image!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              if (message.image != null && message.message.isNotEmpty)
                const SizedBox(height: 6),
              if (message.voiceMessage != null) ...[
                InkWell(
                  onTap: onPlayVoice,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMine ? Colors.white24 : appSurface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_arrow,
                          color: isMine ? Colors.white : accentColor),
                      const SizedBox(width: 6),
                      Icon(Icons.graphic_eq,
                          size: 18, color: isMine ? Colors.white70 : appMuted),
                      const SizedBox(width: 8),
                      Text(_voiceDuration(message.voiceDuration),
                          style: TextStyle(
                              color: isMine ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                if (message.message.isNotEmpty) const SizedBox(height: 6),
              ],
              if (message.message.isNotEmpty)
                message.message.contains('📹')
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMine ? Colors.white24 : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isMine
                                  ? Colors.white38
                                  : Colors.blue.shade200),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.videocam,
                              color: isMine ? Colors.white : Colors.blue,
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to join video call',
                            style: TextStyle(
                              color: isMine ? Colors.white : Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ]),
                      )
                    : Text(
                        message.message,
                        style: TextStyle(
                            color: isMine ? Colors.white : Colors.black87,
                            fontSize: 15),
                      ),
              if (reaction != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isMine ? Colors.white24 : appSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(reaction!, style: const TextStyle(fontSize: 14)),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.forwardedFromMessageId != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.forward,
                          size: 12, color: isMine ? Colors.white70 : appMuted),
                    ),
                  Text(
                    timeAgo(message.createdAt),
                    style: TextStyle(
                      color: isMine ? Colors.white70 : appMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onMenuTap,
                    child: Icon(
                      Icons.more_horiz,
                      size: 14,
                      color: isMine ? Colors.white54 : appMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _voiceDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _replyLabel(String senderName, String? repliedToName) {
  if (repliedToName == null) return '$senderName replied';
  if (senderName == repliedToName) {
    return senderName == 'You'
        ? 'You replied to Yourself'
        : '$senderName replied to themselves';
  }
  return '$senderName replied to $repliedToName';
}

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.isMine,
    required this.onReply,
    required this.child,
  });
  final bool isMine;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _offset = 0;
  bool _triggered = false;
  static const _threshold = 56.0;

  void _onUpdate(DragUpdateDetails d) {
    final delta = d.delta.dx;
    // my messages: swipe left (negative); others: swipe right (positive)
    final newOffset = (_offset + delta).clamp(
      widget.isMine ? -_threshold : 0.0,
      widget.isMine ? 0.0 : _threshold,
    );
    setState(() => _offset = newOffset);

    if (!_triggered && _offset.abs() >= _threshold) {
      _triggered = true;
      HapticFeedback.mediumImpact();
      widget.onReply();
    }
  }

  void _onEnd(DragEndDetails _) {
    _triggered = false;
    setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset.abs() / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply icon revealed behind the bubble
          Positioned.fill(
            child: Align(
              alignment:
                  widget.isMine ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progress,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: appPrimary.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.reply_rounded,
                          color: appPrimary, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _PendingImagePreview extends StatelessWidget {
  const _PendingImagePreview(
      {required this.base64Image, required this.onRemove});
  final String base64Image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(base64Image),
                height: 64, width: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Image ready to send',
                  style: TextStyle(color: Colors.grey.shade700))),
          IconButton(
              onPressed: onRemove, icon: const Icon(Icons.close, size: 20)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onSend,
    required this.onPickImage,
    required this.onVoice,
    required this.recording,
  });
  final TextEditingController controller;
  final ConversationMessage? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onVoice;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (replyingTo != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: appSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.reply, size: 16, color: appMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  replyingTo!.message.isEmpty
                      ? 'Replying to photo'
                      : replyingTo!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
              ),
              InkWell(
                  onTap: onCancelReply,
                  child: const Icon(Icons.close, size: 16)),
            ]),
          ),
        Row(children: [
          IconButton(
              onPressed: onPickImage,
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Attach image'),
          IconButton(
              onPressed: onVoice,
              icon: Icon(recording ? Icons.stop_circle : Icons.mic_none),
              color: recording ? Colors.red : null,
              tooltip: recording ? 'Stop recording' : 'Record voice message'),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(backgroundColor: appPrimary)),
        ]),
      ]),
    );
  }
}

class _EditMessageSheet extends StatefulWidget {
  const _EditMessageSheet(
      {required this.controller, required this.accentColor});
  final TextEditingController controller;
  final Color accentColor;

  @override
  State<_EditMessageSheet> createState() => _EditMessageSheetState();
}

class _EditMessageSheetState extends State<_EditMessageSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit_outlined,
                      color: widget.accentColor, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Edit message',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.accentColor.withAlpha(80)),
                ),
                child: TextField(
                  controller: widget.controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(14),
                    border: InputBorder.none,
                    hintText: 'Edit your message...',
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, text);
  }
}

// ── System message row ─────────────────────────────────────────────────────

class _SystemMessageRow extends StatelessWidget {
  const _SystemMessageRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ── Nickname bottom sheet ──────────────────────────────────────────────────

class _NicknameSheet extends StatefulWidget {
  const _NicknameSheet({
    required this.api,
    required this.conversationId,
    required this.myId,
    required this.otherId,
    required this.myRealName,
    required this.otherRealName,
    required this.initialNicknames,
    required this.accentColor,
    required this.onSaved,
  });
  final MarketplaceApi api;
  final String conversationId;
  final String myId;
  final String otherId;
  final String myRealName;
  final String otherRealName;
  final Map<String, String> initialNicknames;
  final Color accentColor;
  final void Function(Map<String, String> updated) onSaved;

  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  late final TextEditingController _myCtrl;
  late final TextEditingController _otherCtrl;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _myCtrl = TextEditingController(
        text: widget.initialNicknames[widget.myId] ?? '');
    _otherCtrl = TextEditingController(
        text: widget.initialNicknames[widget.otherId] ?? '');
  }

  @override
  void dispose() {
    _myCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Map<String, String> updated = {};

      for (final entry in [
        (widget.myId, _myCtrl.text.trim()),
        (widget.otherId, _otherCtrl.text.trim()),
      ]) {
        await widget.api.setConversationNickname(
            widget.conversationId, entry.$1, entry.$2);
        if (entry.$2.isNotEmpty) updated[entry.$1] = entry.$2;
      }

      widget.onSaved(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save nicknames: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, String realName, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 4),
      StatefulBuilder(
        builder: (_, setSt) => TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: realName,
            helperText: 'Leave empty to use real name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      ctrl.clear();
                      setSt(() {});
                    },
                  )
                : null,
          ),
          onChanged: (_) => setSt(() {}),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Text('Nicknames',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Nicknames are visible to everyone in this conversation.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _field('Your nickname', widget.myRealName, _myCtrl),
        const SizedBox(height: 16),
        _field('${widget.otherRealName}\'s nickname', widget.otherRealName,
            _otherCtrl),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: widget.accentColor),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save nicknames'),
          ),
        ),
      ]),
    );
  }
}
