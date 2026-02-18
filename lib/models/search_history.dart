/// 搜索历史模型
class SearchHistory {
  final String keyword;
  final int searchTime;

  SearchHistory({
    required this.keyword,
    required this.searchTime,
  });

  factory SearchHistory.fromJson(Map<String, dynamic> json) {
    return SearchHistory(
      keyword: json['keyword'] as String? ?? '',
      searchTime: json['search_time'] as int? ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keyword': keyword,
      'search_time': searchTime,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchHistory &&
          runtimeType == other.runtimeType &&
          keyword == other.keyword;

  @override
  int get hashCode => keyword.hashCode;
}
