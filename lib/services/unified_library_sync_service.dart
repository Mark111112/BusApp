import 'package:flutter/foundation.dart';
import '../repositories/unified_library_repository.dart';
import '../repositories/cloud115_library_repository.dart';
import '../repositories/jellyfin_repository.dart';
import '../repositories/movie_repository.dart';
import '../services/database_service.dart';
import '../models/unified_library_item.dart';
import '../models/library_item.dart';
import '../models/jellyfin.dart';

/// 统一库同步服务
/// 负责将 115、Jellyfin、STRM 的数据合并到 unified_library 表
class UnifiedLibrarySyncService {
  final UnifiedLibraryRepository _unifiedRepo;
  final Cloud115LibraryRepository _cloud115Repo;
  final JellyfinRepository _jellyfinRepo;
  final MovieRepository _movieRepo;
  final DatabaseService _db;

  UnifiedLibrarySyncService({
    UnifiedLibraryRepository? unifiedRepo,
    Cloud115LibraryRepository? cloud115Repo,
    JellyfinRepository? jellyfinRepo,
    MovieRepository? movieRepo,
    DatabaseService? db,
  })  : _unifiedRepo = unifiedRepo ?? UnifiedLibraryRepository(),
        _cloud115Repo = cloud115Repo ?? Cloud115LibraryRepository(),
        _jellyfinRepo = jellyfinRepo ?? JellyfinRepository(),
        _movieRepo = movieRepo ?? MovieRepository(),
        _db = db ?? DatabaseService.instance;

  /// 同步所有数据到统一库
  /// 返回同步的统计信息
  Future<SyncResult> syncAll({
    void Function(int current, int total, String message)? onProgress,
  }) async {
    onProgress?.call(0, 4, '开始同步...');

    // 步骤1：收集所有数据
    onProgress?.call(1, 4, '收集数据...');
    final syncData = await _collectAllData();

    // 步骤2：合并数据
    onProgress?.call(2, 4, '合并数据...');
    final mergedItems = await _mergeData(syncData);

    // 步骤3：写入数据库
    onProgress?.call(3, 4, '写入数据库...');
    await _unifiedRepo.insertOrUpdateBatch(mergedItems);

    onProgress?.call(4, 4, '同步完成');

    final stats = await _unifiedRepo.getStatistics();
    return SyncResult(
      totalItems: mergedItems.length,
      withVideoId: stats['withVideoId'] ?? 0,
      withCloud115: stats['withCloud115'] ?? 0,
      withJellyfin: stats['withJellyfin'] ?? 0,
      withStrm: stats['withStrm'] ?? 0,
    );
  }

  /// 收集所有来源的数据
  Future<_SyncData> _collectAllData() async {
    // 收集 115 数据（无分页限制）
    final cloud115Items = await _cloud115Repo.getAllItemsUnbounded();

    // 收集 Jellyfin 数据
    final jellyfinMovies = await _jellyfinRepo.getAllMovies();

    // 收集 STRM 数据（直接查询数据库）
    final db = await _db.database;
    final strmRows = await db.query('strm_library');
    final strmItems = strmRows.map((row) => LibraryItem.fromJson({
      ...row,
      'type': 'strm',
    })).toList();

    // 收集 JavBus 数据（用于补充标题和封面）
    final videoIds = <String>{};
    for (final item in cloud115Items) {
      if (item.videoId != null && item.videoId!.isNotEmpty) {
        videoIds.add(item.videoId!);
      }
    }
    for (final movie in jellyfinMovies) {
      if (movie.videoId != null && movie.videoId!.isNotEmpty) {
        videoIds.add(movie.videoId!);
      }
    }
    for (final item in strmItems) {
      if (item.videoId != null && item.videoId!.isNotEmpty) {
        videoIds.add(item.videoId!);
      }
    }

    // 批量获取 JavBus 数据
    final javbusData = <String, _JavBusData>{};
    for (final videoId in videoIds) {
      try {
        final movie = await _movieRepo.getMovie(videoId);
        if (movie != null) {
          // 将 actors 列表转为逗号分隔的字符串（统一格式）
          final actorsString = movie.actors != null && movie.actors!.isNotEmpty
              ? movie.actors!.map((a) => a.name).join(', ')
              : null;

          javbusData[videoId] = _JavBusData(
            title: movie.title,
            cover: movie.cover,
            actors: actorsString,
            date: movie.date,
            duration: movie.duration,
            description: movie.description,
          );
        }
      } catch (e) {
        // 忽略单个影片的获取失败
      }
    }

    return _SyncData(
      cloud115Items: cloud115Items,
      jellyfinMovies: jellyfinMovies,
      strmItems: strmItems,
      javbusData: javbusData,
    );
  }

  /// 合并数据
  Future<List<UnifiedLibraryItem>> _mergeData(_SyncData data) async {
    final Map<String, _MergingItem> mergingMap = {};

    // 处理 115 数据
    for (final item in data.cloud115Items) {
      final unifiedId = UnifiedLibraryItem.generateUnifiedId(item.videoId, item.filepath);

      mergingMap.putIfAbsent(unifiedId, () => _MergingItem(unifiedId: unifiedId));

      final mergeItem = mergingMap[unifiedId]!;

      // 添加来源
      mergeItem.sources.add(MediaSourceInfo(
        source: MediaSource.cloud115,
        fileId: item.fileId,
        pickcode: item.pickcode,
        filepath: item.filepath,
        size: item.size,
      ));

      // 收集候选数据
      if (item.videoId != null && item.videoId!.isNotEmpty) {
        mergeItem.videoId = item.videoId!;
      }
      mergeItem.cloud115Title = item.title;
      mergeItem.cloud115Cover = item.coverImage ?? item.thumbnail;
      mergeItem.cloud115Actors = item.actors;
      mergeItem.cloud115Date = item.date;
      mergeItem.playCount = (mergeItem.playCount ?? 0) + (item.playCount ?? 0);
      if (item.lastPlayed != null && item.lastPlayed! > (mergeItem.lastPlayed ?? 0)) {
        mergeItem.lastPlayed = item.lastPlayed;
      }
    }

    // 处理 Jellyfin 数据
    for (final movie in data.jellyfinMovies) {
      final unifiedId = UnifiedLibraryItem.generateUnifiedId(movie.videoId, movie.title);

      mergingMap.putIfAbsent(unifiedId, () => _MergingItem(unifiedId: unifiedId));

      final mergeItem = mergingMap[unifiedId]!;

      // 添加来源
      mergeItem.sources.add(MediaSourceInfo(
        source: MediaSource.jellyfin,
        itemId: movie.itemId,
        libraryId: movie.libraryId,
        libraryName: movie.libraryName,
        filepath: movie.path,
      ));
      if (kDebugMode && mergeItem.sources.length == 1) {
        // 只在第一个来源时打印，避免太多输出
        print('[Sync] Jellyfin: ${movie.title} -> libraryId=${movie.libraryId}, libraryName=${movie.libraryName}');
      }

      // 收集候选数据
      if (movie.videoId != null && movie.videoId!.isNotEmpty) {
        mergeItem.videoId = movie.videoId!;
      }
      mergeItem.jellyfinTitle = movie.title;
      mergeItem.jellyfinCover = movie.coverImage;
      mergeItem.jellyfinActors = movie.actors.isNotEmpty ? movie.actors.join(', ') : null;
      mergeItem.jellyfinDate = movie.date;
      // 将秒转换为分钟
      mergeItem.jellyfinDuration = movie.runtimeSeconds != null
          ? (movie.runtimeSeconds! / 60).round()
          : null;
      mergeItem.playCount = (mergeItem.playCount ?? 0) + movie.playCount;
      final lastPlayed = movie.lastPlayed ?? 0;
      if (lastPlayed > 0 && lastPlayed > (mergeItem.lastPlayed ?? 0)) {
        mergeItem.lastPlayed = lastPlayed;
      }
    }

    // 处理 STRM 数据
    for (final item in data.strmItems) {
      final unifiedId = UnifiedLibraryItem.generateUnifiedId(item.videoId, item.filepath);

      mergingMap.putIfAbsent(unifiedId, () => _MergingItem(unifiedId: unifiedId));

      final mergeItem = mergingMap[unifiedId]!;

      // 添加来源
      mergeItem.sources.add(MediaSourceInfo(
        source: MediaSource.strm,
        filepath: item.filepath,
        url: item.url,
      ));

      // 收集候选数据
      if (item.videoId != null && item.videoId!.isNotEmpty) {
        mergeItem.videoId = item.videoId!;
      }
      mergeItem.strmTitle = item.title;
      mergeItem.strmCover = item.coverImage ?? item.thumbnail;
      mergeItem.strmActors = item.actors;
      mergeItem.strmDate = item.date;
      mergeItem.playCount = (mergeItem.playCount ?? 0) + (item.playCount ?? 0);
      if (item.lastPlayed != null && item.lastPlayed! > (mergeItem.lastPlayed ?? 0)) {
        mergeItem.lastPlayed = item.lastPlayed;
      }
    }

    // 构建 UnifiedLibraryItem
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = <UnifiedLibraryItem>[];

    for (final entry in mergingMap.entries) {
      final mergeItem = entry.value;

      // 获取 JavBus 数据
      final javbus = mergeItem.videoId != null
          ? data.javbusData[mergeItem.videoId!]
          : null;

      // 选择最佳标题
      final title = UnifiedLibraryItem.selectBestTitle(
        javbusTitle: javbus?.title,
        jellyfinTitle: mergeItem.jellyfinTitle,
        cloud115Title: mergeItem.cloud115Title ?? mergeItem.strmTitle ?? '',
      );

      // 选择最佳封面
      final coverImage = javbus?.cover ??
          mergeItem.jellyfinCover ??
          mergeItem.cloud115Cover ??
          mergeItem.strmCover;

      // 选择最佳演员
      final actors = javbus?.actors ??
          mergeItem.jellyfinActors ??
          mergeItem.cloud115Actors ??
          mergeItem.strmActors;

      // 选择最佳日期
      final date = javbus?.date ??
          mergeItem.jellyfinDate ??
          mergeItem.cloud115Date ??
          mergeItem.strmDate;

      // 选择最佳时长
      final duration = javbus?.duration ?? mergeItem.jellyfinDuration;

      // 选择最佳简介（只有 JavBus 有简介，Jellyfin 的按需获取）
      final description = javbus?.description;

      result.add(UnifiedLibraryItem(
        unifiedId: mergeItem.unifiedId,
        title: title,
        coverImage: coverImage,
        actors: actors,
        date: date,
        duration: duration,
        description: description,
        sources: mergeItem.sources,
        playCount: mergeItem.playCount ?? 0,
        lastPlayed: mergeItem.lastPlayed ?? 0,
        dateAdded: now,
        createdAt: now,
        updatedAt: now,
      ));
    }

    return result;
  }
}

/// 同步结果
class SyncResult {
  final int totalItems;
  final int withVideoId;
  final int withCloud115;
  final int withJellyfin;
  final int withStrm;

  SyncResult({
    required this.totalItems,
    required this.withVideoId,
    required this.withCloud115,
    required this.withJellyfin,
    required this.withStrm,
  });

  @override
  String toString() {
    return 'SyncResult(total: $totalItems, withVideoId: $withVideoId, '
        '115: $withCloud115, Jellyfin: $withJellyfin, STRM: $withStrm)';
  }
}

/// 同步数据容器
class _SyncData {
  final List<LibraryItem> cloud115Items;
  final List<JellyfinMovie> jellyfinMovies;
  final List<LibraryItem> strmItems;
  final Map<String, _JavBusData> javbusData;

  _SyncData({
    required this.cloud115Items,
    required this.jellyfinMovies,
    required this.strmItems,
    required this.javbusData,
  });
}

/// JavBus 数据
class _JavBusData {
  final String? title;
  final String? cover;
  final String? actors;
  final String? date;
  final int? duration;
  final String? description;

  _JavBusData({
    this.title,
    this.cover,
    this.actors,
    this.date,
    this.duration,
    this.description,
  });
}

/// 合并中的项目
class _MergingItem {
  final String unifiedId;
  final List<MediaSourceInfo> sources = [];

  String? videoId;

  // 标题候选
  String? cloud115Title;
  String? jellyfinTitle;
  String? strmTitle;

  // 封面候选
  String? cloud115Cover;
  String? jellyfinCover;
  String? strmCover;

  // 演员候选
  String? cloud115Actors;
  String? jellyfinActors;
  String? strmActors;

  // 日期候选
  String? cloud115Date;
  String? jellyfinDate;
  String? strmDate;

  // 时长候选
  int? jellyfinDuration;

  // 统计
  int? playCount;
  int? lastPlayed;

  _MergingItem({required this.unifiedId});
}
