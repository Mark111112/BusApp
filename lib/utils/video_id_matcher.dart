/// 视频 ID 匹配器
/// 从文件名或标题中提取视频番号
class VideoIDMatcher {
  /// 常见的视频番号正则表达式模式
  static final List<RegExp> _patterns = [
    // 标准格式: ABC-123, ABC-1234, PPPD-561
    RegExp(r'^([A-Z]{2,6}-\d{2,5})', caseSensitive: false),
    // 无连字符: ABC123, ABC1234
    RegExp(r'^([A-Z]{2,6}\d{2,5})', caseSensitive: false),
    // 带前缀: [ABC-123], ABC-123-
    RegExp(r'^\[?([A-Z]{2,6}-?\d{2,5})', caseSensitive: false),
    // NFK 格式: nfk1234
    RegExp(r'^([a-z]{2,6}\d{2,5})', caseSensitive: false),
    // 1pondo 格式: 1pon123456
    RegExp(r'^(1pon\d{6})', caseSensitive: false),
    // caribbeancom 格式: caribbeancom123456-7
    RegExp(r'^(caribbeancom\d{6}-?\d?)', caseSensitive: false),
    // heyzo 格式: heyzo-1234
    RegExp(r'^(heyzo-?\d{4})', caseSensitive: false),
    // Tokyo Hot 格式: n1234
    RegExp(r'^(k?\d{4})', caseSensitive: false),
    // 带括号: (ABC-123)
    RegExp(r'^\(?([A-Z]{2,6}-?\d{2,5})', caseSensitive: false),
  ];

  /// 从文本中提取视频 ID
  String? extractVideoId(String text) {
    if (text.isEmpty) return null;

    // 先尝试标准格式
    for (final pattern in _patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        String id = match.group(1)!.toUpperCase();
        // 标准化：确保大写字母和数字之间有连字符
        id = _normalizeVideoId(id);
        if (id.isNotEmpty) {
          return id;
        }
      }
    }

    // 尝试从文件名中提取（处理包含路径的情况）
    final fileName = text.split('/').last.split('\\').last;
    if (fileName != text) {
      return extractVideoId(fileName);
    }

    return null;
  }

  /// 标准化视频 ID
  /// 例如: ABC123 -> ABC-123, 1PONDO123 -> 1PONDO-123
  String _normalizeVideoId(String id) {
    // 如果已经有连字符，直接返回
    if (id.contains('-')) {
      return id.toUpperCase();
    }

    // 在字母和数字之间添加连字符
    final match = RegExp(r'^([A-Z]+)(\d+)$', caseSensitive: false).firstMatch(id);
    if (match != null) {
      final letters = match.group(1)!.toUpperCase();
      final numbers = match.group(2)!;
      return '$letters-$numbers';
    }

    return id.toUpperCase();
  }

  /// 从 ProviderIds 中提取视频 ID
  String? extractFromProviderIds(Map<String, dynamic>? providerIds) {
    if (providerIds == null) return null;

    if (providerIds['Tmdb'] != null) {
      return 'TMDB-${providerIds['Tmdb']}';
    }
    if (providerIds['Imdb'] != null) {
      return 'IMDB-${providerIds['Imdb']}';
    }

    return null;
  }

  /// 判断是否是有效的视频 ID
  bool isValidVideoId(String? id) {
    if (id == null || id.isEmpty) return false;
    return _patterns.any((pattern) => pattern.hasMatch(id));
  }

  /// 从列表中找到最佳匹配的视频 ID
  String? findBestMatch(List<String> candidates) {
    for (final candidate in candidates) {
      final id = extractVideoId(candidate);
      if (id != null && isValidVideoId(id)) {
        return id;
      }
    }
    return null;
  }

  /// 从 NFO 风格的标题中提取（例如: PPPD-561-性欲が凄すぎて...）
  String? extractFromNfoStyle(String title) {
    // NFO 风格通常在标题开头包含番号
    final match = RegExp(r'^([A-Z]+-\d+)', caseSensitive: false).firstMatch(title);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    return extractVideoId(title);
  }
}
