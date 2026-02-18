import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class MissAVService {
  String _baseUrl;
  late final Dio _dio;
  final int _maxRetries;
  String? _pythonServerUrl;

  static const String _videoM3u8Prefix = 'https://surrit.com/';
  static const String _videoPlaylistSuffix = '/playlist.m3u8';

  static final RegExp _uuidPattern1 = RegExp(r"m3u8\|([a-f0-9\|]+)\|com\|surrit\|https\|video");
  static final RegExp _uuidPattern2 = RegExp(r"https://surrit\.com/([a-f0-9-]+)/playlist\.m3u8");
  static final RegExp _uuidPattern3 = RegExp(r'''video[^>]*src=["'](?<url>https://surrit\.com/[^"']+)["']''');
  static final RegExp _uuidPattern4 = RegExp(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}');
  static final RegExp _m3u8Pattern = RegExp(r'https?://[^"\x27<>\s]+\.m3u8');
  static final RegExp _resolutionPattern = RegExp(r'RESOLUTION=(\d+)x(\d+)');

  final Random _random = Random();

  MissAVService({
    String? baseUrl,
    String? pythonServerUrl,
    int timeout = 15,
    int maxRetries = 3,
  })  : _baseUrl = baseUrl ?? 'https://missav.ai',
        _pythonServerUrl = pythonServerUrl,
        _maxRetries = maxRetries {
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: timeout),
      receiveTimeout: Duration(seconds: timeout),
    ));
  }

  /// 设置 Python 服务器 URL
  void setPythonServerUrl(String? url) {
    if (url != null && url.isNotEmpty) {
      _pythonServerUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  /// 优先通过 Python 服务器获取
  Future<String?> getStreamUrl(String movieId, {String? quality}) async {
    // 如果配置了 Python 服务器，优先使用
    if (_pythonServerUrl != null && _pythonServerUrl!.isNotEmpty) {
      if (kDebugMode) print('[MissAV] Using Python server: $_pythonServerUrl');
      final url = await _fetchFromPythonServer(movieId);
      if (url != null) {
        return url;
      }
      if (kDebugMode) print('[MissAV] Python server failed, falling back to direct request');
    }

    // 回退到直接请求
    return _fetchDirect(movieId, quality);
  }

  /// 从 MissAV Stream 服务获取播放 URL
  Future<String?> _fetchFromPythonServer(String movieId) async {
    try {
      final url = '$_pythonServerUrl/api/resolve/$movieId';
      if (kDebugMode) print('[MissAV] Fetching from stream service: $url');

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
        ),
      ).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final success = data['success'] as bool?;
        if (success == true) {
          final streamUrl = data['stream_url'] as String?;
          if (streamUrl != null && streamUrl.isNotEmpty) {
            if (kDebugMode) print('[MissAV] Got stream URL from stream service: $streamUrl');
            return streamUrl;
          }
        }
      } else if (response.statusCode == 404) {
        if (kDebugMode) print('[MissAV] Stream service: Movie not found (404)');
      }
    } catch (e) {
      if (kDebugMode) print('[MissAV] Stream service error: $e');
    }
    return null;
  }

  /// 直接请求 missav.ai（可能被 Cloudflare 拦截）
  Future<String?> _fetchDirect(String movieId, String? quality) async {
    final movieUrl = '$_baseUrl/${Uri.encodeComponent(movieId)}';
    if (kDebugMode) print('[MissAV] Fetching direct: $movieUrl');

    String? html;
    int attempt = 0;

    while (attempt < _maxRetries) {
      attempt++;
      html = await _fetchPage(movieUrl, attempt: attempt);

      if (html != null && html.isNotEmpty) {
        break;
      }

      if (attempt < _maxRetries) {
        if (kDebugMode) print('[MissAV] Retrying... ($attempt/$_maxRetries)');
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    if (html == null || html.isEmpty) {
      if (kDebugMode) print('[MissAV] Cannot fetch page after $_maxRetries attempts');
      return null;
    }

    final metadata = await _fetchMetadata(html, movieUrl);
    if (metadata == null) {
      if (kDebugMode) print('[MissAV] Cannot extract metadata');
      return null;
    }

    if (metadata == 'direct_url') {
      return _directUrl;
    }

    final playlistUrl = '$_videoM3u8Prefix$metadata$_videoPlaylistSuffix';
    if (kDebugMode) print('[MissAV] Playlist URL: $playlistUrl');

    final playlistContent = await _fetchPlaylist(playlistUrl);
    if (playlistContent == null) {
      if (kDebugMode) print('[MissAV] Cannot fetch playlist, using direct URL');
      return playlistUrl;
    }

    return _parsePlaylist(playlistUrl, playlistContent, quality);
  }

  String? _directUrl;

  String _getRandomSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (index) => chars[_random.nextInt(chars.length)]).join();
  }

  Future<String?> _fetchPage(String url, {required int attempt}) async {
    try {
      final sessionId = _getRandomSessionId();

      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'max-age=0',
        'Connection': 'keep-alive',
        'sec-ch-ua': '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'document',
        'sec-fetch-mode': 'navigate',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'upgrade-insecure-requests': '1',
        'Cookie': 'age_verify=true; missav_session=$sessionId',
        'Referer': _baseUrl,
      };

      if (attempt > 1) {
        headers['X-Requested-With'] = 'XMLHttpRequest-$sessionId';
      }

      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Timeout');
        },
      );

      if (response.statusCode == 200) {
        final html = response.data as String;
        if (kDebugMode) print('[MissAV] Page length: ${html.length} (attempt $attempt)');
        return html;
      } else if (response.statusCode == 403) {
        if (kDebugMode) print('[MissAV] 403 Forbidden, will retry with different headers');
      } else {
        if (kDebugMode) print('[MissAV] Status code: ${response.statusCode} (attempt $attempt)');
      }
    } on DioException catch (e) {
      if (kDebugMode) print('[MissAV] DioException: ${e.type} - ${e.message} (attempt $attempt)');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) print('[MissAV] Fetch page failed: $e (attempt $attempt)');
    }
    return null;
  }

  Future<String?> _fetchPlaylist(String url) async {
    try {
      final response = await _dio.get(url).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        return response.data as String;
      }
    } catch (e) {
      if (kDebugMode) print('[MissAV] Fetch playlist failed: $e');
    }
    return null;
  }

  Future<String?> _fetchMetadata(String html, String movieUrl) async {
    if (kDebugMode) print('[MissAV] Extracting metadata...');

    final patterns = [
      _uuidPattern1,
      _uuidPattern2,
      _uuidPattern3,
      _uuidPattern4,
    ];

    String? directM3u8Url;

    for (int i = 0; i < patterns.length; i++) {
      final match = patterns[i].firstMatch(html);
      if (match != null) {
        if (kDebugMode) print('[MissAV] Matched pattern ${i + 1}');

        if (i == 0) {
          final result = match.group(1);
          if (result != null) {
            final parts = result.split('|').reversed.toList();
            final uuidStr = parts.join('-');
            if (_isValidUuid(uuidStr)) {
              if (kDebugMode) print('[MissAV] UUID valid: $uuidStr');
              return uuidStr;
            }
          }
        } else if (i == 1) {
          final uuid = match.group(1);
          if (uuid != null && _isValidUuid(uuid)) {
            if (kDebugMode) print('[MissAV] UUID valid: $uuid');
            return uuid;
          }
        } else if (i == 2) {
          final urlPart = match.namedGroup('url');
          if (urlPart != null && urlPart.endsWith('.m3u8')) {
            if (kDebugMode) print('[MissAV] Found m3u8: $urlPart');
            directM3u8Url = urlPart;
          }
        } else if (i == 3) {
          final uuid = match.group(0);
          if (uuid != null && _isValidUuid(uuid)) {
            if (kDebugMode) print('[MissAV] Got UUID: $uuid');
            return uuid;
          }
        }
      }
    }

    if (directM3u8Url == null) {
      final m3u8Match = _m3u8Pattern.firstMatch(html);
      if (m3u8Match != null) {
        directM3u8Url = m3u8Match.group(0);
        if (kDebugMode) print('[MissAV] Found m3u8: $directM3u8Url');
      }
    }

    if (directM3u8Url != null) {
      if (kDebugMode) print('[MissAV] Using direct m3u8: $directM3u8Url');
      _directUrl = directM3u8Url;
      return 'direct_url';
    }

    if (kDebugMode) print('[MissAV] No match found');
    return null;
  }

  bool _isValidUuid(String uuid) {
    return RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$').hasMatch(uuid);
  }

  String? _parsePlaylist(String playlistUrl, String playlistContent, String? quality) {
    try {
      final matches = _resolutionPattern.allMatches(playlistContent).toList();
      if (matches.isEmpty) {
        if (kDebugMode) print('[MissAV] No resolution info, using main playlist');
        return playlistUrl;
      }

      final qualityMap = <String, int>{};
      for (final match in matches) {
        final width = int.parse(match.group(1)!);
        final height = int.parse(match.group(2)!);
        qualityMap[height.toString()] = width;
      }

      final qualityList = qualityMap.keys.map(int.parse).toList()..sort();

      String qualityStr;
      List<String> urlPatterns;

      if (quality == null || quality.isEmpty) {
        final highestHeight = qualityList.last.toString();
        qualityStr = '${highestHeight}p';
        if (kDebugMode) print('[MissAV] Highest quality: $qualityStr');

        urlPatterns = [
          '${qualityMap[highestHeight]}x$highestHeight/video.m3u8',
          '${highestHeight}p/video.m3u8',
        ];
      } else {
        final qualityCleaned = quality.trim().toLowerCase();
        final qualityNum = int.parse(qualityCleaned.replaceAll('p', ''));

        final closestHeight = qualityList.reduce((a, b) =>
            (a - qualityNum).abs() < (b - qualityNum).abs() ? a : b);
        qualityStr = '${closestHeight}p';
        if (kDebugMode) print('[MissAV] Quality: $qualityStr (close to $quality)');

        urlPatterns = [
          '${qualityMap[closestHeight.toString()]}x$closestHeight/video.m3u8',
          '${closestHeight}p/video.m3u8',
        ];
      }

      String? resolutionUrl;
      for (final pattern in urlPatterns) {
        if (playlistContent.contains(pattern)) {
          final lines = playlistContent.split('\n');
          for (final line in lines) {
            if (line.contains(pattern)) {
              resolutionUrl = line.trim();
              break;
            }
          }
          if (resolutionUrl != null) break;
        }
      }

      if (resolutionUrl == null) {
        final nonCommentLines = playlistContent
            .split('\n')
            .where((l) => !l.trim().startsWith('#') && l.trim().isNotEmpty)
            .toList();
        resolutionUrl = nonCommentLines.isNotEmpty ? nonCommentLines.last : playlistContent.split('\n').last;
        if (kDebugMode) print('[MissAV] Using default: $resolutionUrl');
      } else {
        if (kDebugMode) print('[MissAV] Found resolution URL: $resolutionUrl');
      }

      if (resolutionUrl.startsWith('http')) {
        return resolutionUrl;
      } else {
        final baseUrl = playlistUrl.split('/').sublist(0, -1).join('/');
        return '$baseUrl/$resolutionUrl';
      }
    } catch (e) {
      if (kDebugMode) print('[MissAV] Parse playlist error: $e');
      return playlistUrl;
    }
  }

  void updateBaseUrl(String baseUrl) {
    _baseUrl = baseUrl;
  }
}
