import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/services.dart';

/// 配置提供者
class ConfigProvider extends ChangeNotifier {
  ConfigService? _config;
  final Map<String, dynamic> _settings = {};
  bool _isLoading = false;

  ConfigProvider({ConfigService? config}) {
    _config = config;
  }

  Map<String, dynamic> get settings => Map.unmodifiable(_settings);
  bool get isLoading => _isLoading;

  /// 加载配置
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_config == null) {
        final prefs = await SharedPreferences.getInstance();
        _config = ConfigService(prefs: prefs);
      }

      final all = await _config!.loadAll();
      _settings.clear();
      _settings.addAll(all);
    } catch (_) {
      _settings.clear();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 获取配置项
  T? get<T>(String key) {
    if (_config == null) return null;
    return _settings[key] as T?;
  }

  /// 设置配置项
  Future<void> set<T>(String key, T value) async {
    _settings[key] = value;
    if (_config != null) {
      await _config!.set(key, value);
    }
    notifyListeners();
  }

  /// JavBus 配置
  String get javBusBaseUrl => get<String>('javbus_base_url') ?? 'https://www.javbus.com';
  Future<void> setJavBusBaseUrl(String url) => set('javbus_base_url', url);

  /// 115 配置
  String? get cloud115Cookie => get<String>('cloud115_cookie');
  Future<void> setCloud115Cookie(String cookie) => set('cloud115_cookie', cookie);

  /// Jellyfin 配置
  String? get jellyfinServerUrl => get<String>('jellyfin_server_url');
  String? get jellyfinApiKey => get<String>('jellyfin_api_key');
  Future<void> setJellyfinServerUrl(String url) => set('jellyfin_server_url', url);
  Future<void> setJellyfinApiKey(String key) => set('jellyfin_api_key', key);

  /// 翻译配置
  String get translationApiUrl => get<String>('translation_api_url') ?? '';
  String get translationApiToken => get<String>('translation_api_token') ?? '';
  String get translationModel => get<String>('translation_model') ?? 'gpt-3.5-turbo';
  Future<void> setTranslationApiUrl(String url) => set('translation_api_url', url);
  Future<void> setTranslationApiToken(String token) => set('translation_api_token', token);
  Future<void> setTranslationModel(String model) => set('translation_model', model);

  /// MissAV 配置
  String get missAvUrlPrefix => get<String>('missav_url_prefix') ?? 'https://missav.ai';
  Future<void> setMissAvUrlPrefix(String url) => set('missav_url_prefix', url);

  /// Python 服务器配置（用于在线播放代理 - MissAV）
  String get pythonServerUrl => get<String>('python_server_url') ?? '';
  Future<void> setPythonServerUrl(String url) => set('python_server_url', url);

  /// Python 后端配置（用于 115 转码服务）
  String get pythonBackendUrl => get<String>('python_backend_url') ?? '';
  String? get pythonBackendUser => get<String>('python_backend_user');
  String? get pythonBackendPass => get<String>('python_backend_pass');
  Future<void> setPythonBackendUrl(String url) => set('python_backend_url', url);
  Future<void> setPythonBackendUser(String user) => set('python_backend_user', user);
  Future<void> setPythonBackendPass(String pass) => set('python_backend_pass', pass);
}
