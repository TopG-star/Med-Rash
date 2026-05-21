import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../infra/auth_state_manager.dart';
import '../infra/device_identity_service.dart';
import '../infra/event_bus.dart';
import '../infra/medrash_http_client.dart';
import '../infra/overlay_manager.dart';
import '../../features/leaderboard/repositories/leaderboard_repository.dart';
import '../../features/leaderboard/repositories/netlify_supabase_leaderboard_repository.dart';
import '../../features/profile/repositories/profile_repository.dart';
import '../../features/quiz/repositories/netlify_supabase_quiz_repository.dart';
import '../../features/quiz/repositories/quiz_repository.dart';
import '../../features/quiz/storage/quiz_attempt_store.dart';
import '../../features/session/repositories/netlify_supabase_session_repository.dart';
import '../../features/session/repositories/session_repository.dart';
import 'get_it.dart';

Future<void> initCore() async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  getIt.registerLazySingleton<EventBus>(EventBus.new);
  getIt.registerLazySingleton<OverlayController>(OverlayController.new);
  getIt.registerLazySingleton<MedRashHttpClient>(
    () => MedRashHttpClient(
      functionsBaseUrl: AppConfig.functionsBaseUrl,
      gateApiKey: AppConfig.gateApiKey.isEmpty ? null : AppConfig.gateApiKey,
    ),
  );
  getIt.registerLazySingleton<DeviceIdentityService>(
    () => DeviceIdentityService(preferences),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => LocalProfileRepository(preferences),
  );
  getIt.registerLazySingleton<QuizAttemptStore>(
    () => QuizAttemptStore(preferences),
  );
  getIt.registerLazySingleton<QuizRepository>(
    () => NetlifySupabaseQuizRepository(
      httpClient: getIt<MedRashHttpClient>(),
      authStateManager: getIt<AuthStateManager>(),
      profileRepository: getIt<ProfileRepository>(),
      store: getIt<QuizAttemptStore>(),
      eventBus: getIt<EventBus>(),
    ),
  );
  getIt.registerLazySingleton<SessionRepository>(
    () => NetlifySupabaseSessionRepository(
      httpClient: getIt<MedRashHttpClient>(),
      fallback: InMemorySessionRepository(),
    ),
  );
  final AuthStateManager authStateManager = AuthStateManager(
    deviceIdentityService: getIt<DeviceIdentityService>(),
  );
  await authStateManager.initialize();
  getIt.registerSingleton<AuthStateManager>(authStateManager);

  getIt.registerLazySingleton<LeaderboardRepository>(
    () => NetlifySupabaseLeaderboardRepository(
      httpClient: getIt<MedRashHttpClient>(),
      authStateManager: getIt<AuthStateManager>(),
      profileRepository: getIt<ProfileRepository>(),
      eventBus: getIt<EventBus>(),
      fallback: InMemoryLeaderboardRepository(),
    ),
  );

  // Hydrate persisted quiz state (active attempt + cached completed snapshot)
  // and best-effort seed live quiz data before any screen tries to use it.
  await getIt<QuizRepository>().initialize();
}