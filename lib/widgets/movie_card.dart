import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'javbus_image.dart';
import '../services/javbus_service.dart';
import '../services/cloud115_library_service.dart';

/// 影片卡片样式
enum MovieCardStyle {
  /// 标准样式：封面 + 右下角播放按钮
  standard,
  /// 收藏样式：封面 + 左上角收藏标 + 右下角播放按钮
  favorite,
  /// 搜索结果样式：封面 + 左上角番号标签
  search,
  /// 库管理样式：封面 + 右下角播放按钮 + 来源标签
  library,
}

/// 统一的影片卡片组件
class MovieCard extends StatelessWidget {
  /// 封面 URL
  final String? coverUrl;

  /// 标题
  final String title;

  /// 番号
  final String? videoId;

  /// 演员名称
  final String? actorName;

  /// 发行日期
  final String? date;

  /// 卡片样式
  final MovieCardStyle style;

  /// 左上角自定义图标（覆盖默认）
  final Widget? customPrefixIcon;

  /// 右上角自定义图标（如磁力状态）
  final Widget? topRightIcon;

  /// 右下角自定义图标（覆盖默认）
  final Widget? customSuffixIcon;

  /// 库来源标签
  final String? libraryLabel;

  /// 库来源标签颜色
  final Color? libraryLabelColor;

  /// 点击事件
  final VoidCallback? onTap;

  /// 长按事件
  final VoidCallback? onLongPress;

  /// 是否显示播放按钮（默认 true）
  final bool showPlayButton;

  const MovieCard({
    super.key,
    this.coverUrl,
    required this.title,
    this.videoId,
    this.actorName,
    this.date,
    this.style = MovieCardStyle.standard,
    this.customPrefixIcon,
    this.topRightIcon,
    this.customSuffixIcon,
    this.libraryLabel,
    this.libraryLabelColor,
    this.onTap,
    this.onLongPress,
    this.showPlayButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图片
                  _buildCover(),
                  // 左上角图标
                  ..._buildPrefixIcons(),
                  // 右上角图标
                  if (topRightIcon != null) topRightIcon!,
                  // 右下角播放按钮
                  if (showPlayButton && customSuffixIcon != null) customSuffixIcon!,
                  if (showPlayButton && customSuffixIcon == null && _shouldShowPlayButton())
                    _buildPlayButton(),
                ],
              ),
            ),
            // 信息区域
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  /// 构建封面
  Widget _buildCover() {
    return _MovieCover(
      coverUrl: coverUrl,
      videoId: videoId,
    );
  }

  /// 构建左上角图标列表
  List<Widget> _buildPrefixIcons() {
    if (customPrefixIcon != null) return [customPrefixIcon!];
    final defaultIcon = _buildDefaultPrefixIcon();
    if (defaultIcon != null) return [defaultIcon];
    return [];
  }

  /// 构建默认左上角图标
  Widget? _buildDefaultPrefixIcon() {
    switch (style) {
      case MovieCardStyle.favorite:
        return Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.favorite,
              color: Colors.white,
              size: 16,
            ),
          ),
        );
      case MovieCardStyle.search:
        if (videoId != null && videoId!.isNotEmpty) {
          return Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green[600],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                videoId!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
        return null;
      default:
        return null;
    }
  }

  /// 是否显示播放按钮
  bool _shouldShowPlayButton() {
    return style == MovieCardStyle.standard ||
        style == MovieCardStyle.favorite ||
        style == MovieCardStyle.library;
  }

  /// 构建播放按钮
  Widget _buildPlayButton() {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.play_arrow,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  /// 构建信息区域
  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 库标签和番号行
          _buildLabelRow(),
          if (videoId != null || libraryLabel != null)
            const SizedBox(height: 4),
          // 标题
          _buildTitle(),
          // 演员或日期
          if (actorName != null && actorName!.isNotEmpty)
            _buildActorName(),
          if (date != null && date!.isNotEmpty)
            _buildDate(),
        ],
      ),
    );
  }

  /// 构建库标签和番号行
  Widget _buildLabelRow() {
    return Row(
      children: [
        // 库标签
        if (libraryLabel != null && libraryLabel!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: libraryLabelColor ?? Colors.grey,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              libraryLabel!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        // 番号（搜索样式在左上角已有，这里不显示）
        if (libraryLabel != null && libraryLabel!.isNotEmpty && videoId != null && style != MovieCardStyle.search)
          const SizedBox(width: 4),
        if (videoId != null && style != MovieCardStyle.search)
          Expanded(
            child: Text(
              videoId!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// 构建标题
  Widget _buildTitle() {
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    );
  }

  /// 构建演员名称
  Widget _buildActorName() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        actorName!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
    );
  }

  /// 构建日期
  Widget _buildDate() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        date!,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
    );
  }
}

/// 影片封面组件 - 支持异步从 JavBus 获取封面
class _MovieCover extends StatefulWidget {
  final String? coverUrl;
  final String? videoId;

  const _MovieCover({
    this.coverUrl,
    this.videoId,
  });

  @override
  State<_MovieCover> createState() => _MovieCoverState();
}

class _MovieCoverState extends State<_MovieCover> {
  /// 封面加载状态
  bool _hasTriedDirectUrl = false;
  bool _isFetchingFromJavBus = false;
  String? _fetchedCoverUrl;

  @override
  void didUpdateWidget(_MovieCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果 videoId 变化，重置状态
    if (oldWidget.videoId != widget.videoId) {
      _hasTriedDirectUrl = false;
      _isFetchingFromJavBus = false;
      _fetchedCoverUrl = null;
    }
  }

  /// 尝试从 JavBus 获取封面
  Future<void> _fetchCoverFromJavBus() async {
    if (_isFetchingFromJavBus || widget.videoId == null || widget.videoId!.isEmpty) {
      return;
    }

    setState(() {
      _isFetchingFromJavBus = true;
    });

    try {
      final javbusService = JavBusService();
      final movie = await javbusService.getMovieDetail(widget.videoId!);
      if (movie != null && movie.cover != null && movie.cover!.isNotEmpty) {
        // 更新数据库中的封面
        await _updateCoverInDatabase(widget.videoId!, movie.cover!);

        if (mounted) {
          setState(() {
            _fetchedCoverUrl = movie.cover;
            _isFetchingFromJavBus = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isFetchingFromJavBus = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('[_MovieCover] 从 JavBus 获取封面失败: $e');
      if (mounted) {
        setState(() {
          _isFetchingFromJavBus = false;
        });
      }
    }
  }

  /// 更新数据库中的封面
  Future<void> _updateCoverInDatabase(String videoId, String coverUrl) async {
    try {
      final cloud115Service = Cloud115LibraryService();
      // 通过 videoId 查找所有匹配的项目
      final items = await cloud115Service.findItemsByVideoId(videoId);

      // 更新所有匹配项目的封面
      for (final item in items) {
        if (item.fileId != null && item.fileId!.isNotEmpty) {
          await cloud115Service.updateCoverImage(item.fileId!, coverUrl);
          if (kDebugMode) print('[_MovieCover] 已更新封面 [$videoId]: $coverUrl');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[_MovieCover] 更新数据库封面失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 如果有传入的封面 URL，直接使用
    if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty) {
      return JavBusImage(
        key: ValueKey('cover_${widget.videoId}'),
        imageUrl: widget.coverUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorWidget: _buildErrorWidget(),
      );
    }

    // 2. 如果已经从 JavBus 获取到封面，使用它
    if (_fetchedCoverUrl != null && _fetchedCoverUrl!.isNotEmpty) {
      if (kDebugMode) print('[_MovieCover] 使用爬取的封面: $_fetchedCoverUrl');
      return JavBusImage(
        key: ValueKey('fetched_$_fetchedCoverUrl'),
        imageUrl: _fetchedCoverUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorWidget: _buildErrorWidget(),
      );
    }

    // 3. 如果有 videoId，尝试直接 URL
    if (widget.videoId != null && widget.videoId!.isNotEmpty) {
      final directUrl = 'https://www.javbus.com/pics/thumb/${widget.videoId}.jpg';

      // 如果是第一次尝试，使用直接 URL
      if (!_hasTriedDirectUrl) {
        _hasTriedDirectUrl = true;
        if (kDebugMode) print('[_MovieCover] 尝试直接 URL: $directUrl，并开始异步爬取');

        // 延迟尝试从 JavBus 获取（避免阻塞 UI）
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _fetchCoverFromJavBus();
          }
        });
      }

      // 如果正在从 JavBus 获取，显示加载中
      if (_isFetchingFromJavBus) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      // 尝试直接 URL
      return JavBusImage(
        key: ValueKey('direct_${widget.videoId}'),
        imageUrl: directUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorWidget: _buildErrorWidget(),
      );
    }

    // 4. 没有任何信息，显示占位符
    if (kDebugMode) print('[_MovieCover] 没有封面信息，显示占位符');
    return _buildPlaceholder();
  }

  /// 构建错误/占位符组件
  Widget _buildErrorWidget() {
    return Container(
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.movie, size: 48, color: Colors.grey),
          if (widget.videoId != null && widget.videoId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.videoId!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建占位符组件
  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.movie, size: 48, color: Colors.grey),
      ),
    );
  }
}
