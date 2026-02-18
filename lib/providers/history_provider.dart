import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../models/view_history.dart';

/// 浏览历史提供者
class HistoryProvider extends ChangeNotifier {
  static const int _maxHistoryCount = 50; // 最多保存50条历史
  static const String _historyKey = 'view_history';

  List<ViewHistory> _history = [];
  bool _isLoading = false;

  List<ViewHistory> get history => _history.reversed.toList(); // 最新的在前
  bool get isLoading => _isLoading;
  int get count => _history.length;
  bool get hasHistory => _history.isNotEmpty;

  /// 加载浏览历史
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);
      if (historyJson != null) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _history = decoded
            .map((e) => ViewHistory.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          print('[History] 加载了 ${_history.length} 条浏览历史');
          if (_history.isNotEmpty) {
            print('[History] 第一条: id=${_history.first.movieId}, title=${_history.first.title}, cover=${_history.first.cover}');
          }
        }
      }
    } catch (_) {
      _history = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 添加到浏览历史
  Future<void> addView({
    required String movieId,
    String? title,
    String? cover,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 移除旧记录（如果存在）
    _history.removeWhere((h) => h.movieId == movieId);

    // 添加新记录
    final newItem = ViewHistory(
      movieId: movieId,
      title: title,
      cover: cover,
      viewTime: now,
    );
    _history.add(newItem);

    if (kDebugMode) {
      print('[History] 添加浏览历史: $movieId, title: $title, cover: $cover');
      print('[History] 当前历史数量: ${_history.length}');
    }

    // 限制历史记录数量
    if (_history.length > _maxHistoryCount) {
      _history.removeAt(0);
    }

    await _save();
    notifyListeners();
  }

  /// 从浏览历史移除
  Future<void> remove(String movieId) async {
    _history.removeWhere((h) => h.movieId == movieId);
    await _save();
    notifyListeners();
  }

  /// 清空浏览历史
  Future<void> clear() async {
    _history.clear();
    await _save();
    notifyListeners();
  }

  /// 保存到本地存储
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, historyJson);
    } catch (_) {}
  }

  /// 检查影片是否在历史中
  bool contains(String movieId) {
    return _history.any((h) => h.movieId == movieId);
  }
}
