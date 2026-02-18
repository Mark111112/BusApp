import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/repositories.dart';
import '../services/services.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // 外部依赖
  final prefs = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => prefs);

  // 数据库
  sl.registerLazySingleton(() => DatabaseService.instance);

  // 服务
  sl.registerLazySingleton(() => ConfigService(prefs: prefs));
  sl.registerLazySingleton(() => JavBusService());
  sl.registerLazySingleton(() => ScraperService());
  sl.registerLazySingleton(() => Cloud115Service());
  sl.registerLazySingleton(() => JellyfinService());
  sl.registerLazySingleton(() => TranslatorService());
  sl.registerLazySingleton(() => VideoPlayerService());
  sl.registerLazySingleton(() => DMMService());

  // 仓库
  sl.registerLazySingleton(() => MovieRepository());
  sl.registerLazySingleton(() => FavoriteRepository());
  sl.registerLazySingleton(() => SearchHistoryRepository());
  sl.registerLazySingleton(() => PlaybackRepository());
}
