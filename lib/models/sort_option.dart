/// 排序字段
enum SortField {
  dateAdded,   // 入库时间
  videoId,     // 番号
  title,       // 标题
  date,        // 发行日期
  playCount,   // 播放次数
  lastPlayed,  // 最后播放时间
  random,      // 随机
}

/// 排序方向
enum SortDirection {
  ascending,   // 升序
  descending,  // 降序
}

/// 排序选项
class SortOption {
  final SortField field;
  final SortDirection direction;

  const SortOption({
    required this.field,
    this.direction = SortDirection.descending,
  });

  /// 默认排序（入库时间降序）
  static const SortOption defaultSort = SortOption(
    field: SortField.dateAdded,
    direction: SortDirection.descending,
  );

  /// 随机排序
  static const SortOption random = SortOption(
    field: SortField.random,
  );

  /// 复制并修改
  SortOption copyWith({
    SortField? field,
    SortDirection? direction,
  }) {
    return SortOption(
      field: field ?? this.field,
      direction: direction ?? this.direction,
    );
  }

  /// 获取排序字段名称
  String getFieldName() {
    switch (field) {
      case SortField.dateAdded:
        return '入库时间';
      case SortField.videoId:
        return '番号';
      case SortField.title:
        return '标题';
      case SortField.date:
        return '发行日期';
      case SortField.playCount:
        return '播放次数';
      case SortField.lastPlayed:
        return '播放时间';
      case SortField.random:
        return '随机';
    }
  }

  /// 获取排序方向名称
  String getDirectionName() {
    if (field == SortField.random) return '';
    switch (direction) {
      case SortDirection.ascending:
        return '升序';
      case SortDirection.descending:
        return '降序';
    }
  }

  /// 获取显示文本
  String getDisplayText() {
    if (field == SortField.random) return '随机排序';
    return '${getFieldName()} ${getDirectionName()}';
  }

  /// 获取数据库 ORDER BY 子句
  String getOrderByClause() {
    switch (field) {
      case SortField.dateAdded:
        return 'date_added ${_directionSql}';
      case SortField.videoId:
        return 'video_id ${_directionSql}';
      case SortField.title:
        return 'title ${_directionSql}';
      case SortField.date:
        return 'date ${_directionSql}';
      case SortField.playCount:
        return 'play_count ${_directionSql}';
      case SortField.lastPlayed:
        return 'last_played ${_directionSql}';
      case SortField.random:
        return 'RANDOM()';
    }
  }

  String get _directionSql {
    switch (direction) {
      case SortDirection.ascending:
        return 'ASC';
      case SortDirection.descending:
        return 'DESC';
    }
  }

  /// 是否为随机排序
  bool get isRandom => field == SortField.random;

  @override
  String toString() => getDisplayText();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SortOption &&
        other.field == field &&
        other.direction == direction;
  }

  @override
  int get hashCode => field.hashCode ^ direction.hashCode;
}
