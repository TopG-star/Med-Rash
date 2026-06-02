import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../config/app_config.dart';

/// Loads Navii avatar SVG bytes for a seed. Pluggable so tests can inject
/// a stub without hitting the network.
abstract class NaviiSvgLoader {
  /// Returns the SVG bytes for [seed] at [pixelSize], or `null` on any
  /// failure (network, decode, 4xx/5xx). Callers fall back to a monogram
  /// avatar when the result is null.
  Future<Uint8List?> load({required String seed, required int pixelSize});
}

/// Default implementation: hits the self-hosted Navii endpoint at
/// `${AppConfig.functionsBaseUrl}avatar?seed=…&size=…`, persists responses
/// via `flutter_cache_manager` (one HTTP round trip per seed+size per
/// device), and layers a small in-memory LRU on top so list-scroll
/// repaints don't re-decode.
class HttpNaviiSvgLoader implements NaviiSvgLoader {
  HttpNaviiSvgLoader({
    BaseCacheManager? cacheManager,
    String? baseUrl,
    int memoryCacheSize = 64,
  })  : _cache = cacheManager ?? DefaultCacheManager(),
        _baseUrl = baseUrl ?? AppConfig.functionsBaseUrl,
        _memoryCacheSize = memoryCacheSize;

  final BaseCacheManager _cache;
  final String _baseUrl;
  final int _memoryCacheSize;

  // Insertion-ordered map → cheapest possible LRU.
  final Map<String, Uint8List> _memory = <String, Uint8List>{};

  // Stable per-URL fail flag for the session so a scroll over a broken
  // seed does not trigger a retry storm.
  final Set<String> _failed = <String>{};

  @override
  Future<Uint8List?> load({required String seed, required int pixelSize}) async {
    final String trimmed = seed.trim();
    if (trimmed.isEmpty) return null;
    final int clampedSize = pixelSize.clamp(16, 1024);
    final String url = _buildUrl(trimmed, clampedSize);

    if (_failed.contains(url)) return null;

    final Uint8List? memoryHit = _memory.remove(url);
    if (memoryHit != null) {
      _memory[url] = memoryHit;
      return memoryHit;
    }

    try {
      final fileInfo = await _cache.getSingleFile(url);
      final Uint8List bytes = await fileInfo.readAsBytes();
      _putMemory(url, bytes);
      return bytes;
    } catch (_) {
      _failed.add(url);
      return null;
    }
  }

  String _buildUrl(String seed, int size) {
    final String sep = _baseUrl.endsWith('/') ? '' : '/';
    final String versionQuery = AppConfig.naviiVersion.isEmpty
        ? ''
        : '&v=${Uri.encodeQueryComponent(AppConfig.naviiVersion)}';
    return '$_baseUrl${sep}avatar'
        '?seed=${Uri.encodeQueryComponent(seed)}'
        '&size=$size'
        '$versionQuery';
  }

  void _putMemory(String url, Uint8List bytes) {
    _memory[url] = bytes;
    while (_memory.length > _memoryCacheSize) {
      _memory.remove(_memory.keys.first);
    }
  }
}

/// Globally-resolved loader the `GamifiedAvatar` reads at build time.
/// `main()` (and tests) set this; when null, every Navii spec falls back
/// to its monogram.
NaviiSvgLoader? globalNaviiSvgLoader;
