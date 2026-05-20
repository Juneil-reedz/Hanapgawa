import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.url,
    required this.token,
    required this.room,
    required this.displayName,
  });

  final String url;
  final String token;
  final String room;
  final String displayName;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late final Room _room;
  EventsListener<RoomEvent>? _listener;

  bool _connected = false;
  bool _micEnabled = true;
  bool _camEnabled = true;
  bool _frontCamera = true;
  String _status = 'Connecting…';

  // Tracks
  LocalVideoTrack? _localVideo;
  final _remoteVideos = <String, VideoTrack>{};
  final _remoteAudios = <String, AudioTrack>{};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _connect();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _listener?.dispose();
    _room.disconnect();
    _room.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await [Permission.camera, Permission.microphone].request();

    _room = Room();
    _listener = _room.createListener();

    _listener!
      ..on<TrackSubscribedEvent>((e) {
        setState(() {
          if (e.track is VideoTrack) {
            _remoteVideos[e.participant.sid] = e.track as VideoTrack;
          } else if (e.track is AudioTrack) {
            _remoteAudios[e.participant.sid] = e.track as AudioTrack;
          }
        });
      })
      ..on<TrackUnsubscribedEvent>((e) {
        setState(() {
          _remoteVideos.remove(e.participant.sid);
          _remoteAudios.remove(e.participant.sid);
        });
      })
      ..on<ParticipantDisconnectedEvent>((_) {
        setState(() => _remoteVideos.removeWhere((_, __) => true));
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (mounted) Navigator.of(context).pop();
      });

    try {
      await _room.connect(
        widget.url,
        widget.token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      final videoTrack = await LocalVideoTrack.createCameraTrack(
        const CameraCaptureOptions(
          cameraPosition: CameraPosition.front,
          params: VideoParametersPresets.h540_169,
        ),
      );
      await _room.localParticipant?.publishVideoTrack(videoTrack);
      _localVideo = videoTrack;

      await _room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) {
        setState(() {
          _connected = true;
          _status = 'Connected';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Failed: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _toggleMic() async {
    final enabled = !_micEnabled;
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
    setState(() => _micEnabled = enabled);
  }

  Future<void> _toggleCamera() async {
    final enabled = !_camEnabled;
    await _room.localParticipant?.setCameraEnabled(enabled);
    setState(() => _camEnabled = enabled);
  }

  Future<void> _flipCamera() async {
    if (_localVideo == null) return;
    final next = _frontCamera ? CameraPosition.back : CameraPosition.front;
    await _localVideo!.switchCamera(next == CameraPosition.front ? '0' : '1');
    setState(() => _frontCamera = !_frontCamera);
  }

  void _endCall() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final remoteParticipants = _remoteVideos.values.toList();
    final hasRemote = remoteParticipants.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Remote video (full screen) or waiting state
          if (hasRemote)
            VideoTrackRenderer(remoteParticipants.first)
          else
            _WaitingView(status: _status, connected: _connected),

          // Local video (picture-in-picture)
          if (_localVideo != null && _camEnabled)
            Positioned(
              top: 60,
              right: 16,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VideoTrackRenderer(_localVideo!),
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  if (!hasRemote && _connected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(180),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, color: Colors.white, size: 8),
                        SizedBox(width: 4),
                        Text('Waiting', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                ]),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      icon: _micEnabled ? Icons.mic : Icons.mic_off,
                      label: _micEnabled ? 'Mute' : 'Unmute',
                      onTap: _toggleMic,
                      active: _micEnabled,
                    ),
                    _CallButton(
                      icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _camEnabled ? 'Stop video' : 'Start video',
                      onTap: _toggleCamera,
                      active: _camEnabled,
                    ),
                    _CallButton(
                      icon: Icons.flip_camera_ios_outlined,
                      label: 'Flip',
                      onTap: _flipCamera,
                      active: true,
                    ),
                    _CallButton(
                      icon: Icons.call_end,
                      label: 'End',
                      onTap: _endCall,
                      active: false,
                      danger: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.status, required this.connected});
  final String status;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          connected ? Icons.videocam_outlined : Icons.videocam_off_outlined,
          size: 64,
          color: connected ? appPrimary : Colors.grey,
        ),
        const SizedBox(height: 16),
        Text(
          connected ? 'Waiting for others to join…' : status,
          style: TextStyle(
            color: connected ? Colors.white70 : Colors.redAccent,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        if (connected) ...[
          const SizedBox(height: 8),
          const Text(
            'Share the room with the other person to start.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.active,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? Colors.red
        : active
            ? Colors.white24
            : Colors.white10;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}
