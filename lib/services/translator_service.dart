import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 翻译服务
/// 移植自 modules/translation/translator.py
class TranslatorService {
  String _apiUrl = 'https://api.openai.com/v1/chat/completions';
  String _apiToken = '';
  String _sourceLang = '日语';
  String _targetLang = '中文';
  String _model = 'gpt-3.5-turbo';

  final Dio _dio = Dio();

  /// 初始化
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiUrl = prefs.getString('bus115_translation_api_url') ?? _apiUrl;
    _sourceLang = prefs.getString('bus115_translation_source_lang') ?? _sourceLang;
    _targetLang = prefs.getString('bus115_translation_target_lang') ?? _targetLang;
    _apiToken = prefs.getString('bus115_translation_api_token') ?? '';
    _model = prefs.getString('bus115_translation_model') ?? _model;
  }

  /// 判断是否为 Ollama
  bool _isOllama(String url) {
    final lower = url.toLowerCase();
    return lower.contains('ollama') ||
        url.contains(':11434') ||
        RegExp(r'localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.')
            .hasMatch(url);
  }

  /// 翻译文本（异步）
  Future<String?> translate(String text) async {
    if (text.trim().isEmpty) return '';

    await initialize();

    // 检查 API Token
    if (_apiToken.isEmpty && !_isOllama(_apiUrl)) {
      throw Exception('翻译 API Token 未设置');
    }

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      if (_apiToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_apiToken';
      }

      final prompt =
          '将以下$_sourceLang文本翻译成$_targetLang，只返回翻译结果，不要解释：\n\n$text';

      Map<String, dynamic> payload;

      if (_isOllama(_apiUrl)) {
        // Ollama 格式
        if (_apiUrl.contains('/api/chat')) {
          payload = {
            'model': _model,
            'messages': [
              {'role': 'system', 'content': '你是一个专业的$_sourceLang到$_targetLang翻译器。'},
              {'role': 'user', 'content': prompt}
            ],
            'stream': false,
            'options': {'temperature': 0.3, 'top_p': 0.9}
          };
        } else {
          payload = {
            'model': _model,
            'prompt': '你是一个专业的$_sourceLang到$_targetLang翻译器。\n$prompt',
            'stream': false,
          };
        }
      } else if (_apiUrl.contains('siliconflow.cn')) {
        // SiliconFlow 格式
        payload = {
          'stream': false,
          'model': _model,
          'messages': [
            {'role': 'system', 'content': '你是一个专业的$_sourceLang到$_targetLang翻译器。'},
            {'role': 'user', 'content': prompt}
          ]
        };
      } else {
        // OpenAI 标准格式
        payload = {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': '你是一个专业的$_sourceLang到$_targetLang翻译器。'},
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.3,
          'top_p': 0.9
        };
      }

      final response = await _dio.post(
        _apiUrl,
        data: payload,
        options: Options(headers: headers, responseType: ResponseType.json),
      );

      if (response.statusCode == 200) {
        // 解析响应数据 - 参考 Python 的 response.json()
        Map<String, dynamic> data;

        if (response.data is Map) {
          data = response.data as Map<String, dynamic>;
        } else if (response.data is String) {
          final responseStr = response.data.toString();
          // 检查是否是 HTML 响应
          if (responseStr.trimLeft().startsWith('<!DOCTYPE html>') ||
              responseStr.trimLeft().startsWith('<html')) {
            throw Exception('API 地址配置错误：返回的是 HTML 页面而不是 JSON 数据。\n请检查 API 地址是否正确。\n当前配置: $_apiUrl');
          }
          // 尝试解析 JSON 字符串
          try {
            data = jsonDecode(response.data) as Map<String, dynamic>;
          } catch (e) {
            throw Exception('API 返回了无效的 JSON: ${responseStr.substring(0, responseStr.length > 200 ? 200 : responseStr.length)}');
          }
        } else {
          throw Exception('API 返回格式错误: 期望 JSON 对象，实际得到 ${response.data.runtimeType}');
        }

        // 提取翻译结果 - 参考 Python 的解析逻辑
        if (data.containsKey('choices')) {
          // OpenAI/Claude/SiliconFlow 格式
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final message = choices[0]['message'] as Map<String, dynamic>?;
            if (message != null) {
              final content = message['content']?.toString().trim() ?? '';
              if (content.isNotEmpty) return content;
            }
          }
        } else if (data.containsKey('response')) {
          // Ollama 格式
          final content = data['response']?.toString().trim() ?? '';
          if (content.isNotEmpty) return content;
        }

        // 检查 API 错误
        if (data.containsKey('error')) {
          final error = data['error'];
          if (error is String) {
            throw Exception('API 返回错误: $error');
          } else if (error is Map) {
            throw Exception('API 返回错误: ${error['message'] ?? error}');
          }
        }

        throw Exception('无法解析 API 响应，响应键: ${data.keys.join(', ')}');
      } else {
        // 非 200 状态码，尝试解析错误信息
        String errorDetail = response.statusMessage ?? '';
        try {
          if (response.data is String) {
            final errorData = jsonDecode(response.data);
            if (errorData is Map && errorData.containsKey('error')) {
              final error = errorData['error'];
              if (error is String) {
                errorDetail = error;
              } else if (error is Map) {
                errorDetail = error['message']?.toString() ?? error.toString();
              }
            }
          }
        } catch (_) {
          // 忽略解析错误，使用原始状态消息
        }
        throw Exception('HTTP 错误: ${response.statusCode} - $errorDetail');
      }
    } catch (e) {
      throw Exception('翻译请求失败: $e');
    }
  }

  /// 批量翻译
  Future<Map<String, String>> translateBatch(Map<String, String> texts) async {
    final results = <String, String>{};

    for (final entry in texts.entries) {
      try {
        final translated = await translate(entry.value);
        if (translated != null) {
          results[entry.key] = translated;
        }
      } catch (_) {
        // 继续处理下一个
      }

      // 避免请求过快
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return results;
  }

  /// 保存配置
  Future<void> saveConfig({
    String? apiUrl,
    String? sourceLang,
    String? targetLang,
    String? apiToken,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'bus115_';

    if (apiUrl != null) {
      _apiUrl = apiUrl;
      await prefs.setString('${prefix}translation_api_url', apiUrl);
    }
    if (sourceLang != null) {
      _sourceLang = sourceLang;
      await prefs.setString('${prefix}translation_source_lang', sourceLang);
    }
    if (targetLang != null) {
      _targetLang = targetLang;
      await prefs.setString('${prefix}translation_target_lang', targetLang);
    }
    if (apiToken != null) {
      _apiToken = apiToken;
      await prefs.setString('${prefix}translation_api_token', apiToken);
    }
    if (model != null) {
      _model = model;
      await prefs.setString('${prefix}translation_model', model);
    }
  }

  /// 获取可用模型列表（Ollama）
  Future<List<String>> getOllamaModels() async {
    try {
      final baseUrl = _apiUrl.contains('/api')
          ? _apiUrl.split('/api')[0]
          : _apiUrl.replaceAll('/v1/audio/transcriptions', '');

      final response = await _dio.get(
        '$baseUrl/api/tags',
        options: Options(
          headers: _apiToken.isNotEmpty
              ? {'Authorization': 'Bearer $_apiToken'}
              : null,
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final models = data['models'] as List? ?? [];
      return models.map((e) => e['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// 配置状态
  bool get isConfigured => _apiToken.isNotEmpty || _isOllama(_apiUrl);
}
