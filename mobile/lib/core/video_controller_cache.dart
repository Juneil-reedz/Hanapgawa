import 'package:video_player/video_player.dart';

class CachedVideoController {
  CachedVideoController(Future<VideoPlayerController> future) {
    ready = future.then((createdController) {
      controller = createdController;
      isReady = true;
      return createdController;
    });
  }

  late final Future<VideoPlayerController> ready;
  late final VideoPlayerController controller;
  bool isReady = false;
  DateTime lastUsed = DateTime.now();

  void touch() {
    lastUsed = DateTime.now();
  }
}

class VideoControllerCache {
  VideoControllerCache._();

  static final Map<String, CachedVideoController> _cache = {};

  static CachedVideoController? peek(String source) => _cache[source];

  static Future<VideoPlayerController> get(
    String source,
    Future<VideoPlayerController> Function() create,
  ) async {
    final cached = _cache[source];
    if (cached != null) {
      cached.touch();
      await cached.ready;
      return cached.controller;
    }

    final entry = CachedVideoController(create());
    _cache[source] = entry;
    try {
      await entry.ready;
      entry.touch();
      return entry.controller;
    } catch (_) {
      _cache.remove(source);
      rethrow;
    }
  }
}
