import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../infra/auth_state_manager.dart';
import '../infra/device_identity_service.dart';
import '../infra/device_token_store.dart';
import '../infra/event_bus.dart';
import '../infra/medrash_http_client.dart';
import '../infra/overlay_manager.dart';
import '../infra/turnstile_token_provider.dart';
import '../ui/widgets/navii_svg_loader.dart';
import '../../features/leaderboard/repositories/leaderboard_repository.dart';
import '../../features/leaderboard/repositories/netlify_supabase_leaderboard_repository.dart';
import '../../features/profile/repositories/participant_stats_repository.dart';
import '../../features/profile/repositories/profile_repository.dart';
import '../../features/profile/repositories/recovery_repository.dart';
import '../../features/profile/storage/guest_profile_prompt_store.dart';
import '../../features/profile/storage/streak_store.dart';
import '../../features/quiz/repositories/netlify_supabase_quiz_repository.dart';
import '../../features/quiz/repositories/quiz_repository.dart';
import '../../features/quiz/storage/quiz_attempt_store.dart';
import '../../features/quiz/storage/ranked_best_score_store.dart';
import '../../features/session/repositories/netlify_supabase_session_repository.dart';
import '../../features/session/repositories/session_repository.dart';
import '../../features/session/storage/last_session_store.dart';
import 'get_it.dart';

Future<void> initCore() async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  // P7 — Navii avatars. Loader is wired unconditionally; the widget itself
  // gates rendering on `AppConfig.enableNaviiAvatars`, so leaving the
  // singleton in place when the flag is off costs nothing at runtime.
  globalNaviiSvgLoader ??= HttpNaviiSvgLoader();

  getIt.registerLazySingleton<EventBus>(EventBus.new);
  getIt.registerLazySingleton<OverlayController>(OverlayController.new);
  getIt.registerLazySingleton<DeviceIdentityService>(
    () => DeviceIdentityService(preferences),
  );
  getIt.registerLazySingleton<TurnstileTokenProvider>(
    () => TurnstileTokenProvider.platformDefault(
      siteKey: AppConfig.turnstileSiteKey,
    ),
  );
  getIt.registerLazySingleton<DeviceTokenStore>(
    () => DeviceTokenStore(
      preferences: preferences,
      functionsBaseUrl: AppConfig.functionsBaseUrl,
      deviceIdentityService: getIt<DeviceIdentityService>(),
      turnstileTokenProvider: getIt<TurnstileTokenProvider>(),
    ),
  );
  getIt.registerLazySingleton<MedRashHttpClient>(
    () => MedRashHttpClient(
      functionsBaseUrl: AppConfig.functionsBaseUrl,
      tokenProvider: () => getIt<DeviceTokenStore>().currentToken(),
    ),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => LocalProfileRepository(
      preferences,
      eventBus: getIt<EventBus>(),
      httpClient: getIt<MedRashHttpClient>(),
      authStateManager: getIt<AuthStateManager>(),
    ),
  );
  // P8.c — participant analytics (donut + per-category bars). Registered
  // after ProfileRepository because it depends on it for the request
  // payload's `profile` snapshot.
  getIt.registerLazySingleton<ParticipantStatsRepository>(
    () => ParticipantStatsRepository(
      httpClient: getIt<MedRashHttpClient>(),
      authStateManager: getIt<AuthStateManager>(),
      profileRepository: getIt<ProfileRepository>(),
    ),
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
      authStateManager: getIt<AuthStateManager>(),
      fallback: InMemorySessionRepository(),
    ),
  );
  getIt.registerLazySingleton<LastSessionStore>(
    () => LastSessionStore(preferences),
  );
  getIt.registerLazySingleton<RankedBestScoreStore>(
    () => RankedBestScoreStore(preferences, eventBus: getIt<EventBus>()),
  );
  getIt.registerLazySingleton<GuestProfilePromptStore>(
    () => GuestProfilePromptStore(preferences, eventBus: getIt<EventBus>()),
  );
  getIt.registerLazySingleton<StreakStore>(
    () => StreakStore(preferences, eventBus: getIt<EventBus>()),
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

  getIt.registerLazySingleton<RecoveryRepository>(
    () => NetlifyRecoveryRepository(
      httpClient: getIt<MedRashHttpClient>(),
      authStateManager: getIt<AuthStateManager>(),
    ),
  );

  // Hydrate persisted quiz state (active attempt + cached completed snapshot)
  // and best-effort seed live quiz data before any screen tries to use it.
  await getIt<QuizRepository>().initialize();

  // Eagerly construct stores whose constructors subscribe to global events
  // we cannot afford to miss before any UI reads them. The GuestProfilePromptStore
  // listens for AttemptSubmittedEvent — that event typically fires from
  // QuizResultPage on the QR-deep-link path BEFORE the participant ever
  // visits Home/Ranked (which are where the store is otherwise first read).
  getIt<GuestProfilePromptStore>();
  // Same rationale: StreakStore must observe AttemptSubmittedEvent even when
  // the participant hasn't opened Home yet (e.g. QR-deep-link → quiz → result).
  getIt<StreakStore>();
}