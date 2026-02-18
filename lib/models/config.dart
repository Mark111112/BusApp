/// 应用配置项
enum ConfigKey {
  // 115 网盘配置
  uid115,
  cookie115,

  // Jellyfin 配置
  jellyfinUrl,
  jellyfinToken,
  jellyfinUserId,

  // 翻译配置
  translatorType, // 'openai', 'ollama', 'siliconflow'
  apiKey,
  apiUrl,
  model,

  // 其他配置
  theme,
  language,
}

/// 配置模型
class AppConfig {
  final ConfigKey key;
  final String value;
  final String? description;

  AppConfig({
    required this.key,
    required this.value,
    this.description,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      key: _parseConfigKey(json['key'] as String? ?? ''),
      value: json['value'] as String? ?? '',
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key.name,
      'value': value,
      'description': description,
    };
  }

  static ConfigKey _parseConfigKey(String keyStr) {
    return ConfigKey.values.firstWhere(
      (k) => k.name == keyStr,
      orElse: () => ConfigKey.language,
    );
  }

  AppConfig copyWith({
    ConfigKey? key,
    String? value,
    String? description,
  }) {
    return AppConfig(
      key: key ?? this.key,
      value: value ?? this.value,
      description: description ?? this.description,
    );
  }
}
