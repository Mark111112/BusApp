import 'package:provider/provider.dart';
import '../core/injection_container.dart';
import 'movie_provider.dart';
import 'search_provider.dart';
import 'favorite_provider.dart';
import 'config_provider.dart';
import 'history_provider.dart';
import 'jellyfin_provider.dart';
import 'cloud115_provider.dart';
import 'library_provider.dart';
import '../services/dmm_service.dart';
import '../services/jellyfin_service.dart';

// 导出各个 Provider 类
export 'movie_provider.dart';
export 'search_provider.dart';
export 'favorite_provider.dart';
export 'config_provider.dart';
export 'history_provider.dart';
export 'jellyfin_provider.dart';
export 'cloud115_provider.dart';
export 'library_provider.dart';

/// 导出所有提供者
class AppProviders {
  static List<dynamic> get providers => [
    ChangeNotifierProvider<MovieProvider>(
      create: (_) => MovieProvider(),
    ),
    ChangeNotifierProvider<SearchProvider>(
      create: (_) => SearchProvider(),
    ),
    ChangeNotifierProvider<FavoriteProvider>(
      create: (_) => FavoriteProvider()..load(),
    ),
    ChangeNotifierProvider<HistoryProvider>(
      create: (_) => HistoryProvider()..load(),
    ),
    ChangeNotifierProvider<ConfigProvider>(
      create: (_) => ConfigProvider()..load(),
    ),
    ChangeNotifierProvider<JellyfinProvider>(
      create: (_) => JellyfinProvider()..initialize(),
    ),
    ChangeNotifierProvider<Cloud115Provider>(
      create: (_) => Cloud115Provider()..initialize(),
    ),
    // LibraryProvider depends on both JellyfinProvider and Cloud115Provider
    ChangeNotifierProxyProvider2<JellyfinProvider, Cloud115Provider, LibraryProvider>(
      create: (_) => LibraryProvider(),
      update: (_, jellyfin, cloud115, library) {
        // Set both provider references
        library!.setJellyfinProvider(jellyfin);
        library.setCloud115Provider(cloud115);
        return library;
      },
    ),
  ];

  // For backward compatibility - keep notifiers as providers
  static List<dynamic> get notifiers => providers;

  static Provider<DMMService> get dmmService => Provider<DMMService>(
    create: (_) => DMMService(),
  );

  static List<List<dynamic>> get all => [
    notifiers,
    [dmmService],
  ];
}
