/// 搜索结果项
class SearchResultItem {
  final String id;
  final String title;
  final String? cover;
  final String? date;
  final String? type; // 'movie' 或 'actor'
  final bool? hasMagnets; // 是否有磁力链接（null=未知，需要获取详情）

  SearchResultItem({
    required this.id,
    required this.title,
    this.cover,
    this.date,
    this.type,
    this.hasMagnets,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      id: json['id'] as String,
      title: json['title'] as String,
      cover: json['cover'] as String?,
      date: json['date'] as String?,
      type: json['type'] as String?,
      hasMagnets: json['hasMagnets'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cover': cover,
      'date': date,
      'type': type,
      'hasMagnets': hasMagnets,
    };
  }

  bool get isActor => type == 'actor';
  bool get isMovie => type == 'movie' || type == null;

  /// 复制并修改部分字段
  SearchResultItem copyWith({
    String? id,
    String? title,
    String? cover,
    String? date,
    String? type,
    bool? hasMagnets,
  }) {
    return SearchResultItem(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      date: date ?? this.date,
      type: type ?? this.type,
      hasMagnets: hasMagnets ?? this.hasMagnets,
    );
  }
}

/// 搜索分页结果
class SearchPagedResult {
  final List<SearchResultItem> items;
  final int currentPage;
  final bool hasNextPage;
  final int? nextPage;

  const SearchPagedResult({
    required this.items,
    required this.currentPage,
    required this.hasNextPage,
    this.nextPage,
  });

  /// 创建一个空结果
  const SearchPagedResult.empty()
      : items = const [],
        currentPage = 1,
        hasNextPage = false,
        nextPage = null;

  /// 是否有结果
  bool get hasResults => items.isNotEmpty;

  /// 结果总数
  int get itemCount => items.length;
}
