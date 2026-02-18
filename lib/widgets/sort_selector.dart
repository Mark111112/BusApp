import 'package:flutter/material.dart';
import '../models/sort_option.dart';

/// 排序选择器按钮
class SortSelectorButton extends StatelessWidget {
  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;
  final List<SortField> availableFields;

  const SortSelectorButton({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
    this.availableFields = const [
      SortField.dateAdded,
      SortField.videoId,
      SortField.title,
      SortField.date,
      SortField.random,
    ],
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showSortMenu(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getSortIcon(),
              size: 18,
              color: Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Text(
              currentSort.getDisplayText(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSortIcon() {
    switch (currentSort.field) {
      case SortField.dateAdded:
      case SortField.lastPlayed:
        return Icons.access_time;
      case SortField.videoId:
        return Icons.tag;
      case SortField.title:
        return Icons.title;
      case SortField.date:
        return Icons.calendar_today;
      case SortField.playCount:
        return Icons.play_circle_outline;
      case SortField.random:
        return Icons.shuffle;
    }
  }

  void _showSortMenu(BuildContext context) {
    // 先选择字段
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SortFieldSelectorSheet(
        currentSort: currentSort,
        availableFields: availableFields,
        onFieldSelected: (field) {
          Navigator.pop(context);
          if (field == SortField.random) {
            // 随机排序不需要选择方向
            onSortChanged(const SortOption(field: SortField.random));
          } else {
            // 选择排序方向
            _showDirectionMenu(context, field);
          }
        },
      ),
    );
  }

  void _showDirectionMenu(BuildContext context, SortField field) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SortDirectionSelectorSheet(
        field: field,
        currentDirection: currentSort.field == field ? currentSort.direction : SortDirection.descending,
        onDirectionSelected: (direction) {
          onSortChanged(SortOption(field: field, direction: direction));
        },
      ),
    );
  }
}

/// 排序字段选择器
class _SortFieldSelectorSheet extends StatelessWidget {
  final SortOption currentSort;
  final List<SortField> availableFields;
  final ValueChanged<SortField> onFieldSelected;

  const _SortFieldSelectorSheet({
    required this.currentSort,
    required this.availableFields,
    required this.onFieldSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Text(
                    '选择排序方式',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 选项列表
            ListView.builder(
              shrinkWrap: true,
              itemCount: availableFields.length,
              itemBuilder: (context, index) {
                final field = availableFields[index];
                final isSelected = field == currentSort.field;
                return ListTile(
                  leading: Icon(_getIconForField(field)),
                  title: Text(_getNameForField(field)),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () => onFieldSelected(field),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _getIconForField(SortField field) {
    switch (field) {
      case SortField.dateAdded:
      case SortField.lastPlayed:
        return Icons.access_time;
      case SortField.videoId:
        return Icons.tag;
      case SortField.title:
        return Icons.title;
      case SortField.date:
        return Icons.calendar_today;
      case SortField.playCount:
        return Icons.play_circle_outline;
      case SortField.random:
        return Icons.shuffle;
    }
  }

  String _getNameForField(SortField field) {
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
        return '随机排序';
    }
  }
}

/// 排序方向选择器
class _SortDirectionSelectorSheet extends StatelessWidget {
  final SortField field;
  final SortDirection currentDirection;
  final ValueChanged<SortDirection> onDirectionSelected;

  const _SortDirectionSelectorSheet({
    required this.field,
    required this.currentDirection,
    required this.onDirectionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fieldName = _getFieldName(field);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '按 $fieldName 排序',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),
            // 方向选项
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.green),
              title: const Text('升序（从小到大）'),
              trailing: currentDirection == SortDirection.ascending
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                onDirectionSelected(SortDirection.ascending);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward, color: Colors.orange),
              title: const Text('降序（从大到小）'),
              trailing: currentDirection == SortDirection.descending
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                onDirectionSelected(SortDirection.descending);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _getFieldName(SortField field) {
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
}
