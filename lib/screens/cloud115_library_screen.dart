import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cloud115_provider.dart';
import '../providers/library_provider.dart';
import '../providers/movie_provider.dart';
import '../services/cloud115_library_service.dart';
import '../services/cloud115_service.dart';
import '../services/database_service.dart';
import '../models/library_item.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 115 库管理页面
/// 用于导入和管理 115 网盘视频库
class Cloud115LibraryScreen extends StatefulWidget {
  const Cloud115LibraryScreen({super.key});

  @override
  State<Cloud115LibraryScreen> createState() => _Cloud115LibraryScreenState();
}

class _Cloud115LibraryScreenState extends State<Cloud115LibraryScreen> {
  final Cloud115LibraryService _libraryService = Cloud115LibraryService();
  final TextEditingController _searchController = TextEditingController();

  List<LibraryItem> _items = [];
  List<LibraryItem> _filteredItems = [];
  bool _isLoading = false;
  bool _isImporting = false;
  bool _isImportingDb = false;
  Map<String, int>? _stats;
  String _importProgress = '';
  int _importCurrent = 0;
  int _importTotal = 0;
  int _currentItemPage = 0;
  final int _pageSize = 30;
  bool _hasMoreItems = true;

  // 排序选项
  SortOption _sortOption = const SortOption(field: SortField.dateAdded);

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _currentItemPage = 0;
        _hasMoreItems = true;
      });
    }

    try {
      final newItems = await _libraryService.getLocalItems(
        start: _currentItemPage * _pageSize,
        limit: _pageSize,
        searchTerm: _searchController.text.isNotEmpty ? _searchController.text : null,
        sortBy: _sortOption,
      );

      final totalCount = await _libraryService.getLocalItemsCount(
        searchTerm: _searchController.text.isNotEmpty ? _searchController.text : null,
      );

      setState(() {
        if (loadMore) {
          _items.addAll(newItems);
        } else {
          _items = newItems;
        }
        _filteredItems = _items;
        _hasMoreItems = _items.length < totalCount;
        _currentItemPage++;
      });

      // 加载统计信息
      if (!loadMore) {
        final stats = await _libraryService.getLocalStats();
        setState(() {
          _stats = stats;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载库失败: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncFromServer() async {
    setState(() => _isLoading = true);

    try {
      final success = await _libraryService.syncFromServer();
      if (success) {
        await _loadLibrary();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('同步成功')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('同步失败，请检查服务器连接')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showImportDialog() async {
    final cloud115 = context.read<Cloud115Provider>();

    if (!cloud115.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录 115 网盘')),
      );
      return;
    }

    // 获取当前文件夹信息
    final currentFolderId = cloud115.currentFolderId;
    final currentFolderName = cloud115.currentFolderName;

    // 统计当前文件夹中的视频文件数
    final videoFiles = cloud115.onlyFiles;

    if (!mounted) return;

    bool recursive = false;
    bool fetchMetadata = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('导入视频库'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前文件夹: $currentFolderName'),
                const SizedBox(height: 8),
                Text('视频文件数: ${videoFiles.length}'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('递归导入子文件夹'),
                  subtitle: const Text('包括所有子文件夹中的视频（可能触发风控）', style: TextStyle(fontSize: 12)),
                  value: recursive,
                  onChanged: (value) {
                    setDialogState(() {
                      recursive = value;
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('从 JavBus 获取封面'),
                  subtitle: const Text('自动获取影片封面和演员信息', style: TextStyle(fontSize: 12)),
                  value: fetchMetadata,
                  onChanged: (value) {
                    setDialogState(() {
                      fetchMetadata = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  recursive
                      ? '将递归遍历所有子文件夹并导入视频文件'
                      : '仅导入当前文件夹中的视频文件',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (fetchMetadata)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '注意: 获取封面需要访问 JavBus，每个文件约需 0.5 秒',
                      style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                  'recursive': recursive,
                  'fetchMetadata': fetchMetadata,
                }),
                child: const Text('导入'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final isRecursive = result['recursive'] == true;
      final doFetch = result['fetchMetadata'] == true;
      if (isRecursive) {
        await _importFolderRecursive(currentFolderId, currentFolderName, fetchMetadata: doFetch);
      } else {
        await _importFolder(currentFolderId, currentFolderName, videoFiles, fetchMetadata: doFetch);
      }
    }
  }

  Future<void> _importFolder(
    String folderId,
    String folderName,
    List<Cloud115FileInfo> files, {
    bool fetchMetadata = true,
  }) async {
    setState(() => _isImporting = true);

    try {
      // 将 Cloud115FileInfo 转换为 Map 格式
      final fileList = files.map((file) => {
        'n': file.name,
        'name': file.name,
        'fid': file.fileId,
        'id': file.fileId,
        'pc': file.pickCode,
        'pick_code': file.pickCode,
        's': file.size,
        'size': file.size,
        'uo': file.thumbnailOriginal,
        'u': file.thumbnail,
      }).toList();

      // 从本地 115 文件列表创建库项目，带进度回调
      final items = await _libraryService.createItemsFrom115Files(
        fileList,
        fetchMetadata: fetchMetadata,
        onProgress: (current, total, fileName) {
          if (mounted) {
            setState(() {
              _importProgress = '获取元数据: $current/$total - $fileName';
            });
          }
        },
      );

      await _libraryService.saveItemsToLocal(items);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 ${items.length} 个视频文件')),
        );
        await _loadLibrary();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isImporting = false;
        _importProgress = '';
        _importCurrent = 0;
        _importTotal = 0;
      });
    }
  }

  /// 递归导入文件夹及其子文件夹中的所有视频
  Future<void> _importFolderRecursive(
    String folderId,
    String folderName, {
    bool fetchMetadata = true,
  }) async {
    setState(() {
      _isImporting = true;
      _importProgress = '正在扫描文件...';
      _importCurrent = 0;
      _importTotal = 0;
    });

    try {
      final cloud115 = context.read<Cloud115Provider>();

      // 递归收集所有视频文件
      final allVideos = await cloud115.getAllVideosRecursively(
        folderId: folderId,
        onProgress: (current, total, fileName) {
          setState(() {
            _importCurrent = current;
            _importTotal = total;
            _importProgress = '扫描中: $current 个文件';
          });
        },
        onRateLimit: (count) async {
          // 触发风控时显示对话框，询问用户是否继续
          if (!mounted) return false;
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('检测到风控'),
              content: Text('已发送 $count 个请求，115 可能触发风控限制。\n\n请稍等片刻，然后点击"继续"按钮。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('继续'),
                ),
              ],
            ),
          );
          return result ?? false;
        },
      );

      // 更新进度
      if (mounted) {
        setState(() {
          _importProgress = '扫描完成，正在获取元数据...';
        });
      }

      int importedCount = 0;

      // 逐个处理（用于显示进度）
      for (int i = 0; i < allVideos.length; i++) {
        final file = allVideos[i];

        setState(() {
          _importProgress = '处理中: ${i + 1}/${allVideos.length} - ${file.name}';
        });

        // 转换为 Map 格式
        final fileList = [
          {
            'n': file.name,
            'name': file.name,
            'fid': file.fileId,
            'id': file.fileId,
            'pc': file.pickCode,
            'pick_code': file.pickCode,
            's': file.size,
            'size': file.size,
            'uo': file.thumbnailOriginal,
            'u': file.thumbnail,
          }
        ];

        // 创建并保存库项目
        final items = await _libraryService.createItemsFrom115Files(
          fileList,
          fetchMetadata: fetchMetadata,
        );
        await _libraryService.saveItemsToLocal(items);

        importedCount += items.length;

        // 限流延迟
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (mounted) {
        setState(() {
          _importProgress = '导入完成！';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $importedCount 个视频文件')),
        );
        await _loadLibrary();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importProgress = '导入失败: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isImporting = false;
        _importProgress = '';
        _importCurrent = 0;
        _importTotal = 0;
      });
    }
  }

  Future<void> _extractVideoIds() async {
    setState(() => _isLoading = true);

    try {
      final success = await _libraryService.extractVideoIds();
      if (success) {
        await _loadLibrary();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频 ID 提取完成')),
          );
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearLibrary() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空库'),
        content: const Text('确定要清空所有已导入的视频吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (result == true) {
      final count = await _libraryService.clearLocalLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $count 个项目')),
        );
        await _loadLibrary();
      }
    }
  }

  /// 清理图片缓存
  Future<void> _clearImageCache() async {
    setState(() => _isLoading = true);

    try {
      // 清理 CachedNetworkImage 缓存
      await DefaultCacheManager().emptyCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片缓存已清理'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理缓存失败: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 刷新封面 - 从爬虫重新获取封面URL
  Future<void> _refreshCovers() async {
    final movieProvider = context.read<MovieProvider>();
    final cloud115Service = Cloud115LibraryService();

    // 从数据库获取所有115库项
    final allItems = await cloud115Service.getLocalItems(
      start: 0,
      limit: 10000, // 获取所有项目
    );

    // 找出没有封面或封面为空的项
    final needsRefresh = allItems
        .where((item) => item.coverImage == null || item.coverImage!.isEmpty)
        .toList();

    if (allItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('库中没有项目')),
        );
      }
      return;
    }

    // 显示选项对话框
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刷新封面'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总项目数: ${allItems.length}'),
            Text('缺少封面: ${needsRefresh.length}'),
            const SizedBox(height: 16),
            const Text('选择要刷新的范围:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'missing'),
            child: Text('仅刷新缺少封面的 (${needsRefresh.length})'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text('刷新全部 (${allItems.length})'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    final itemsToRefresh = choice == 'missing' ? needsRefresh : allItems;

    setState(() => _isLoading = true);

    int successCount = 0;
    int failCount = 0;

    for (final item in itemsToRefresh) {
      if (item.videoId == null || item.videoId!.isEmpty) {
        failCount++;
        continue;
      }

      if (item.fileId == null || item.fileId!.isEmpty) {
        failCount++;
        continue;
      }

      try {
        // 从爬虫获取影片信息
        await movieProvider.loadMovie(item.videoId!, forceRefresh: true);
        final movie = movieProvider.movie;

        if (movie != null && movie.cover != null && movie.cover!.isNotEmpty) {
          // 更新数据库中的封面
          await cloud115Service.updateCoverImage(item.fileId!, movie.cover!);
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        if (kDebugMode) print('[RefreshCovers] 获取封面失败: ${item.videoId}, $e');
        failCount++;
      }

      // 每处理10个更新一下进度显示
      if ((successCount + failCount) % 10 == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在刷新... 成功: $successCount, 失败: $failCount'),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // 限流，避免请求过快
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('刷新完成: 成功 $successCount, 失败 $failCount'),
          backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
        ),
      );
      // 刷新列表显示
      await _loadLibrary();
    }
  }

  /// 执行数据库导入
  Future<void> _executeImport(String externalDbPath, Map<String, dynamic> options) async {
    final db = await DatabaseService.instance.database;

    int totalImported = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      // 1. 导入 115 视频库
      if (options['import115'] == true) {
        setState(() => _importProgress = '正在导入 115 视频库...');

        final count = await _importTable(
          db,
          externalDbPath,
          'cloud115_library',
          sourceColumn: 'title, filepath, url, thumbnail, description, category, date_added, last_played, play_count, video_id, cover_image, actors, date, file_id, pickcode, size',
          onProgress: (current, total) {
            setState(() {
              _importCurrent = current;
              _importTotal = total;
              _importProgress = '115 库: $current/$total';
            });
          },
        );

        totalImported += count.toInt();
        if (count > 0) successCount++;
        else failedCount++;
      }

      // 2. 导入 Jellyfin 影片库
      if (options['importJellyfin'] == true) {
        setState(() => _importProgress = '正在导入 Jellyfin 影片库...');

        final count = await _importTable(
          db,
          externalDbPath,
          'jelmovie',
          sourceColumn: 'title, jellyfin_id, item_id, video_id, library_name, library_id, play_url, path, cover_image, actors, date, date_added, last_played, play_count, overview, runtime_seconds, runtime_text, file_size_bytes, file_size_text, genres, resolution',
          onProgress: (current, total) {
            setState(() {
              _importCurrent = current;
              _importTotal = total;
              _importProgress = 'Jellyfin 影片: $current/$total';
            });
          },
        );

        totalImported += count.toInt();
        if (count > 0) successCount++;
        else failedCount++;
      }

      // 3. 导入 Jellyfin 同步状态
      if (options['importSync'] == true) {
        setState(() => _importProgress = '正在导入同步状态...');

        final count = await _importTable(
          db,
          externalDbPath,
          'jelibrary_sync',
          sourceColumn: 'library_id, last_sync_date_created, last_sync_date_last_saved, last_sync_ts',
          onProgress: (current, total) {
            setState(() {
              _importCurrent = current;
              _importTotal = total;
              _importProgress = '同步状态: $current/$total';
            });
          },
        );

        totalImported += count.toInt();
        if (count > 0) successCount++;
        else failedCount++;
      }

      setState(() => _importProgress = '导入完成！');

      // 4. 显示结果
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入完成！成功: $successCount 个表, 共导入 $totalImported 条记录'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // 重新加载库
        await _loadLibrary();
      }

    } catch (e) {
      if (kDebugMode) {
        print('[ImportDatabase] 导入失败: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 导入单个表
  Future<int> _importTable(
    Database db,
    String externalDbPath,
    String tableName, {
    required String sourceColumn,
    required void Function(int current, int total) onProgress,
  }) async {
    int importedCount = 0;

    try {
      // 使用 ATTACH DATABASE 连接外部数据库
      await db.execute('''
        ATTACH DATABASE ? AS external_db
      ''', [externalDbPath]);

      // 获取总数
      final countResult = await db.rawQuery('''
        SELECT COUNT(*) as total FROM external_db.$tableName
      ''');

      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

      if (totalCount == 0) {
        // 断开外部数据库
        await db.execute('DETACH DATABASE external_db');
        return 0;
      }

      // 分批导入，每次导入 100 条
      const batchSize = 100;
      int current = 0;

      while (current < totalCount) {
        // 使用 INSERT OR IGNORE 避免重复
        await db.rawQuery('''
          INSERT OR IGNORE INTO $tableName ($sourceColumn)
          SELECT $sourceColumn FROM external_db.$tableName
          LIMIT ? OFFSET ?
        ''', [batchSize, current]);

        current += batchSize;
        importedCount += batchSize;

        onProgress(current > totalCount ? totalCount : current, totalCount);

        // 限流延迟，避免卡顿
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // 断开外部数据库
      await db.execute('DETACH DATABASE external_db');

      return importedCount;

    } catch (e) {
      if (kDebugMode) {
        print('[$_importTable] 导入表 $tableName 失败: $e');
      }

      try {
        // 断开外部数据库
        await db.execute('DETACH DATABASE external_db');
      } catch (_) {}

      rethrow;
    }
  }

  /// 导入数据库
  /// 导入外部数据库
  Future<void> _importDatabase() async {
    try {
      // 1. 选择文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: '选择 bus115.db 数据库文件',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) return;

      // 2. 显示导入选项对话框
      if (!mounted) return;

      final options = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入数据库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文件: $filePath'),
              const SizedBox(height: 16),
              const Text('选择要导入的数据类型:'),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('115 视频库 (cloud115_library)'),
                value: true,
                onChanged: null,
              ),
              CheckboxListTile(
                title: const Text('Jellyfin 影片库 (jelmovie)'),
                value: false,
                onChanged: null,
              ),
              CheckboxListTile(
                title: const Text('Jellyfin 同步状态 (jelibrary_sync)'),
                value: false,
                onChanged: null,
              ),
              const SizedBox(height: 16),
              const Text(
                '提示: 导入的数据将与现有数据合并。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'import115': true,
                'importJellyfin': false,
                'importSync': false,
              }),
              child: const Text('开始导入'),
            ),
          ],
        ),
      );

      if (options == null) return;

      setState(() => _isImportingDb = true);
      setState(() {
        _importProgress = '准备导入...';
        _importCurrent = 0;
        _importTotal = 0;
      });

      // 3. 执行导入
      await _executeImport(filePath, options);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImportingDb = false);
      }
    }
  }

  void _showItemDetail(LibraryItem item) {
    if (item.videoId != null && item.videoId!.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/movie',
        arguments: {
          'libraryItem': item,
          'fromCloud115': true,
        },
      );
    } else {
      // 没有 video_id，跳转到搜索页面
      Navigator.pushNamed(context, '/search');
    }
  }

  /// 直接播放视频
  Future<void> _playVideo(LibraryItem item) async {
    if (item.pickcode == null || item.pickcode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播放：缺少 pickcode')),
      );
      return;
    }

    final cloud115 = context.read<Cloud115Provider>();

    try {
      final result = await cloud115.playVideo(
        Cloud115FileInfo(
          fileId: item.fileId ?? '',
          name: item.title,
          size: int.tryParse(item.size ?? '0') ?? 0,
          pickCode: item.pickcode!,
          thumbnail: item.thumbnail,
          updateTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          isFile: true,
          isVideo: true,
        ),
      );

      if (result != null && mounted) {
        Navigator.pushNamed(
          context,
          '/player',
          arguments: result,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取播放信息失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  void _onSearch(String value) {
    setState(() {
      if (value.isEmpty) {
        _filteredItems = _items;
      } else {
        _filteredItems = _items.where((item) {
          return item.title.toLowerCase().contains(value.toLowerCase()) ||
              (item.videoId?.toLowerCase().contains(value.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('115 视频库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadLibrary,
            tooltip: '刷新',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'sync':
                  await _syncFromServer();
                  break;
                case 'extract':
                  await _extractVideoIds();
                  break;
                case 'refresh_covers':
                  await _refreshCovers();
                  break;
                case 'clear_cache':
                  await _clearImageCache();
                  break;
                case 'clear':
                  await _clearLibrary();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'sync', child: Text('从服务器同步')),
              const PopupMenuItem(value: 'extract', child: Text('提取视频 ID')),
              const PopupMenuItem(value: 'refresh_covers', child: Text('刷新封面')),
              const PopupMenuItem(value: 'clear_cache', child: Text('清理图片缓存')),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清空库', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 搜索框
                _buildSearchBar(),
                // 统计信息和导入按钮
                _buildHeader(),
                // 影片网格
                Expanded(
                  child: _buildMovieGrid(),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: '搜索影片',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          border: const OutlineInputBorder(),
        ),
        onChanged: _onSearch,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：统计信息 + 排序按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '已导入: ${_stats?['total'] ?? 0} 个视频',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_stats?['with_video_id'] != null && _stats!['with_video_id']! > 0)
                      Text(
                        '已识别 ID: ${_stats!['with_video_id']}',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // 排序按钮
              SortSelectorButton(
                currentSort: _sortOption,
                onSortChanged: (option) {
                  setState(() {
                    _sortOption = option;
                  });
                  _loadLibrary();
                },
              ),
            ],
          ),
          // 显示导入进度
          if (_importProgress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _importTotal > 0 ? _importCurrent / _importTotal : null,
                    backgroundColor: Colors.grey[300],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _importProgress,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          SizedBox(height: _importProgress.isNotEmpty ? 8 : 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : _showImportDialog,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: Text(_isImporting ? '导入中...' : '导入当前文件夹'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isImportingDb ? null : _importDatabase,
                icon: _isImportingDb
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.import_contacts),
                label: Text(_isImportingDb ? '导入中...' : '导入数据库'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMovieGrid() {
    if (_items.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200 &&
            _hasMoreItems &&
            !_isLoading) {
          _loadLibrary(loadMore: true);
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: _filteredItems.length +
            (_hasMoreItems && _isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _filteredItems.length) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final item = _filteredItems[index];
          return _buildMovieCard(item);
        },
      ),
    );
  }

  Widget _buildMovieCard(LibraryItem item) {
    // 构建播放按钮
    final playButton = Positioned(
      bottom: 8,
      right: 8,
      child: GestureDetector(
        onTap: () => _playVideo(item),
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
      ),
    );

    return MovieCard(
      coverUrl: item.coverImage ?? item.thumbnail,
      title: item.title,
      videoId: item.videoId,
      actorName: item.actors,
      date: item.date,
      style: MovieCardStyle.library,
      libraryLabel: '115',
      libraryLabelColor: Colors.orange[600],
      customSuffixIcon: playButton,
      onTap: () => _showItemDetail(item),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '还没有导入任何视频',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '点击"导入当前文件夹"开始',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
