import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 配置服务
class ConfigService {
  final SharedPreferences prefs;

  ConfigService({required this.prefs});

  static const String _prefix = 'bus115_';

  String _key(String key) => '$_prefix$key';

  /// 加载所有配置
  Future<Map<String, dynamic>> loadAll() async {
    return {
      'javbus_base_url': getString('javbus_base_url') ?? 'https://www.javbus.com',
      'javbus_enabled': getBool('javbus_enabled') ?? true,
      'cloud115_cookie': getString('cloud115_cookie'),
      'cloud115_alist_url': getString('cloud115_alist_url'),
      'jellyfin_server_url': getString('jellyfin_server_url'),
      'jellyfin_api_key': getString('jellyfin_api_key'),
      'jellyfin_username': getString('jellyfin_username'),
      'translation_api_url': getString('translation_api_url'),
      'translation_api_token': getString('translation_api_token'),
      'translation_model': getString('translation_model') ?? 'gpt-3.5-turbo',
      'translation_source_lang': getString('translation_source_lang') ?? '日语',
      'translation_target_lang': getString('translation_target_lang') ?? '中文',
      'fwhisper_base_url': getString('fwhisper_base_url'),
      'fwhisper_enabled': getBool('fwhisper_enabled') ?? false,
      'missav_url_prefix': getString('missav_url_prefix') ?? 'https://missav.ai',
      'python_server_url': getString('python_server_url'),
      'python_backend_url': getString('python_backend_url'),
      'python_backend_user': getString('python_backend_user'),
      'python_backend_pass': getString('python_backend_pass'),
    };
  }

  /// 获取字符串
  String? getString(String key) => prefs.getString(_key(key));

  /// 获取布尔值
  bool? getBool(String key) => prefs.getBool(_key(key));

  /// 获取整数值
  int? getInt(String key) => prefs.getInt(_key(key));

  /// 获取双精度浮点数
  double? getDouble(String key) => prefs.getDouble(_key(key));

  /// 设置值
  Future<bool> set(String key, dynamic value) async {
    if (value == null) return prefs.remove(_key(key));

    switch (value.runtimeType) {
      case String:
        return prefs.setString(_key(key), value);
      case bool:
        return prefs.setBool(_key(key), value);
      case int:
        return prefs.setInt(_key(key), value);
      case double:
        return prefs.setDouble(_key(key), value);
      default:
        // 尝试 JSON 序列化
        return prefs.setString(_key(key), jsonEncode(value));
    }
  }

  /// 移除配置
  Future<bool> remove(String key) => prefs.remove(_key(key));

  /// 清空所有配置
  Future<void> clear() => prefs.clear();
}
