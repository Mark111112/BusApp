import '../../core/constants.dart';

/// 番号类型
enum VideoIdType {
  fanza,
  dmm,
  heyzo,
  caribbean,
  musume,
  onePondo,
  pacopacomama,
  kin8tengoku,
  tokyoHot,
  unknown,
}

/// 番号识别结果
class VideoIdMatch {
  final VideoIdType type;
  final String id;
  final String? normalizedId;

  VideoIdMatch({
    required this.type,
    required this.id,
    this.normalizedId,
  });
}

/// 番号匹配器
/// 移植自 modules/video_id_matcher.py
class VideoIdMatcher {
  /// 识别番号类型
  static VideoIdMatch identify(String input) {
    final id = input.trim().toLowerCase();

    // Heyzo: heyzo-xxxx (4位数字)
    if (AppConstants.heyzoRegex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.heyzo,
        id: id,
        normalizedId: _normalizeHeyzo(id),
      );
    }

    // Caribbean: mmddyy-xxx
    if (AppConstants.caribbeanRegex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.caribbean,
        id: id,
        normalizedId: _normalizeCaribbean(id),
      );
    }

    // 10Musume: mmddyy_xx
    if (AppConstants.musumeRegex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.musume,
        id: id,
        normalizedId: _normalizeMusume(id),
      );
    }

    // TokyoHot: nxxxx 或 kxxxx
    if (AppConstants.tokyoHotRegex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.tokyoHot,
        id: id,
        normalizedId: _normalizeTokyoHot(id),
      );
    }

    // Kin8tengoku: kin8-xxxx
    if (AppConstants.kin8Regex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.kin8tengoku,
        id: id,
        normalizedId: _normalizeKin8(id),
      );
    }

    // 1pondo/pacopacomama: mmddyy_xxx (无法直接区分)
    final ondoPacoMatch = RegExp(r'^(\d{6})_(\d{3})$').firstMatch(id);
    if (ondoPacoMatch != null) {
      return VideoIdMatch(
        type: VideoIdType.onePondo, // 默认，实际需要尝试两个
        id: id,
        normalizedId: null, // 需要两个都尝试
      );
    }

    // Fanza/DMM: 字母+数字
    if (AppConstants.fanzaRegex.hasMatch(id)) {
      return VideoIdMatch(
        type: VideoIdType.fanza,
        id: id,
        normalizedId: _normalizeFanza(id),
      );
    }

    return VideoIdMatch(
      type: VideoIdType.unknown,
      id: id,
    );
  }

  /// 从文件名中提取番号
  static String? extractFromFile(String filename) {
    // 去除扩展名
    final name = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 常见模式
    final patterns = [
      RegExp(r'([a-z]{2,6}[-_]?\d{3,})', caseSensitive: false),
      RegExp(r'(heyzo[-_]?\d{4})', caseSensitive: false),
      RegExp(r'(\d{6}[-_]\d{3})'),
      RegExp(r'(n\d{4})', caseSensitive: false),
      RegExp(r'(kin8[-_]?\d{4})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// 规范化 Heyzo ID
  static String _normalizeHeyzo(String id) {
    final match = RegExp(r'\d{4}').firstMatch(id);
    return match != null ? 'HEYZO-${match.group(0)}' : id.toUpperCase();
  }

  /// 规范化 Caribbean ID
  static String _normalizeCaribbean(String id) {
    return id.toUpperCase();
  }

  /// 规范化 10Musume ID
  static String _normalizeMusume(String id) {
    return id.replaceAll('_', '-').toUpperCase();
  }

  /// 规范化 TokyoHot ID
  static String _normalizeTokyoHot(String id) {
    return id.toUpperCase();
  }

  /// 规范化 Kin8 ID
  static String _normalizeKin8(String id) {
    final match = RegExp(r'\d{4}').firstMatch(id);
    return match != null ? 'KIN8-${match.group(0)}' : id.toUpperCase();
  }

  /// 规范化 Fanza ID
  static String _normalizeFanza(String id) {
    return id.toUpperCase().replaceAll('-', '');
  }

  /// 获取爬虫类型
  static String getScraperType(VideoIdType type) {
    switch (type) {
      case VideoIdType.heyzo:
        return 'heyzo';
      case VideoIdType.caribbean:
        return 'caribbean';
      case VideoIdType.musume:
        return 'musume';
      case VideoIdType.onePondo:
        return '1pondo';
      case VideoIdType.pacopacomama:
        return 'pacopacomama';
      case VideoIdType.kin8tengoku:
        return 'kin8tengoku';
      case VideoIdType.tokyoHot:
        return 'tokyohot';
      case VideoIdType.fanza:
      case VideoIdType.dmm:
      default:
        return 'fanza';
    }
  }
}
