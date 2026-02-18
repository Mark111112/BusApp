import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../screens/screens.dart';
import '../utils/theme.dart';

class BusApp extends StatelessWidget {
  const BusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [...AppProviders.notifiers, AppProviders.dmmService],
      child: MaterialApp(
        title: 'BUS115',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        routes: AppRoutes.routes,
      ),
    );
  }
}

class AppRoutes {
  static const String home = '/';
  static const String search = '/search';
  static const String movie = '/movie';
  static const String favorites = '/favorites';
  static const String player = '/player';
  static const String settings = '/settings';
  static const String library = '/library';
  static const String jellyfin = '/jellyfin'; // 保留兼容
  static const String jellyfinDetail = '/jellyfin_detail';
  static const String cloud115 = '/cloud115';
  static const String cloud115Library = '/cloud115_library';

  static final Map<String, WidgetBuilder> routes = {
    home: (context) => const HomeScreen(),
    search: (context) => const SearchScreen(),
    movie: (context) => const MovieScreen(),
    favorites: (context) => const FavoritesScreen(),
    settings: (context) => const SettingsScreen(),
    player: (context) => const PlayerScreen(),
    library: (context) => const LibraryScreen(),
    jellyfin: (context) => const JellyfinScreen(),
    jellyfinDetail: (context) => const JellyfinDetailScreen(),
    cloud115: (context) => const HomeScreen(),
    cloud115Library: (context) => const Cloud115LibraryScreen(),
  };
}
