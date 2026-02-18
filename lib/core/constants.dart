/// 应用常量定义
class AppConstants {
  // API
  static const String defaultJavBusUrl = 'https://www.javbus.com';
  static const int defaultTimeout = 15;

  // 数据库
  static const String databaseName = 'bus115.db';
  static const int databaseVersion = 1;

  // 115 配置
  static const String cloud115UserAgent = 'Mozilla/5.0 115Browser/27.0.5.7';
  static const List<String> cloud115ApiUrls = [
    'https://webapi.115.com/files',
    'http://web.api.115.com/files',
  ];

  // 视频播放
  static const int defaultVideoTimeout = 30;
  static const List<String> videoExtensions = [
    'mp4', 'mkv', 'avi', 'wmv', 'mov', 'flv', 'm4v', 'rmvb', 'rm', 'ts', 'webm'
  ];

  // 番号匹配正则
  static final RegExp heyzoRegex = RegExp(r'^(?:heyzo[-_]?)?\d{4}$');
  static final RegExp caribbeanRegex = RegExp(r'^(\d{6})-(\d{3})$');
  static final RegExp musumeRegex = RegExp(r'^(\d{6})_(\d{2})$');
  static final RegExp tokyoHotRegex = RegExp(r'^[n,k]\d{3,5}$');
  static final RegExp kin8Regex = RegExp(r'^kin8[-_]?\d{4}$');
  static final RegExp fanzaRegex = RegExp(r'^[a-z]{2,6}[-_]?\d{3,}[a-z]?$');
}

/// 错误码
class ErrorCodes {
  static const String networkError = 'NETWORK_ERROR';
  static const String parseError = 'PARSE_ERROR';
  static const String authError = 'AUTH_ERROR';
  static const String notFound = 'NOT_FOUND';
  static const String timeout = 'TIMEOUT';
}
