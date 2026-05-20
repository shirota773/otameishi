import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app_preferences.dart';

import '../db/database.dart';
import '../db/repositories/card_repository.dart';
import '../db/repositories/event_repository.dart';
import '../db/repositories/search_repository.dart';
import '../db/repositories/tag_repository.dart';
export '../db/repositories/tag_repository.dart' show TagWithCount;
import '../models/business_card.dart';
import '../models/event.dart';
import 'package:image_picker/image_picker.dart';

import '../services/camera_service.dart';
import '../services/external_camera_service.dart';
import '../services/image_processing_service.dart';
import '../services/ocr_service.dart';
import '../services/qr_service.dart';
import '../services/sns_launcher_service.dart';
import '../services/storage_service.dart';
import '../usecases/capture_card_usecase.dart';
import '../usecases/delete_card_usecase.dart';
import '../usecases/manual_entry_usecase.dart';
import '../usecases/save_card_usecase.dart';
import '../usecases/search_cards_usecase.dart';
import '../usecases/update_card_usecase.dart';
export '../usecases/search_cards_usecase.dart' show SearchFilters;

// ─── image_picker ─────────────────────────────────────────────────────────────

/// Provides the [ImagePicker] singleton.  Override in tests with a mock.
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

// ─── Infrastructure ──────────────────────────────────────────────────────────

final databaseProviderProvider = Provider<DatabaseProvider>((ref) {
  final provider = DatabaseProvider();
  ref.onDispose(provider.close);
  return provider;
});

final databaseProvider = FutureProvider<Database>((ref) async {
  final dbp = ref.watch(databaseProviderProvider);
  return dbp.database;
});

// ─── Repositories ────────────────────────────────────────────────────────────

final cardRepositoryProvider = FutureProvider<CardRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SqliteCardRepository(db);
});

final tagRepositoryProvider = FutureProvider<TagRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SqliteTagRepository(db);
});

final eventRepositoryProvider = FutureProvider<EventRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SqliteEventRepository(db);
});

final searchRepositoryProvider = FutureProvider<SearchRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SqliteSearchRepository(db);
});

// ─── Services ────────────────────────────────────────────────────────────────

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraServiceImpl();
  ref.onDispose(service.dispose);
  return service;
});

final externalCameraServiceProvider = Provider<ExternalCameraService>(
  (ref) => ExternalCameraServiceImpl(),
);

final imageProcessingServiceProvider = Provider<ImageProcessingService>(
  (ref) => const ImageProcessingServiceImpl(),
);

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrServiceImpl();
  ref.onDispose(service.dispose);
  return service;
});

final qrServiceProvider = Provider<QrService>(
  (ref) => const QrServiceImpl(),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageServiceImpl(),
);

final snsLauncherServiceProvider = Provider<SnsLauncherService>(
  (ref) => const SnsLauncherServiceImpl(),
);

// ─── Use-cases ───────────────────────────────────────────────────────────────

final captureCardUseCaseProvider = Provider<CaptureCardUseCase>((ref) {
  return CaptureCardUseCase(
    imageProcessing: ref.watch(imageProcessingServiceProvider),
    ocr: ref.watch(ocrServiceProvider),
    storage: ref.watch(storageServiceProvider),
  );
});

final manualEntryUseCaseProvider = Provider<ManualEntryUseCase>((ref) {
  return ManualEntryUseCase(
    imageProcessing: ref.watch(imageProcessingServiceProvider),
    storage: ref.watch(storageServiceProvider),
  );
});

final saveCardUseCaseProvider = FutureProvider<SaveCardUseCase>((ref) async {
  final cardRepo = await ref.watch(cardRepositoryProvider.future);
  final tagRepo = await ref.watch(tagRepositoryProvider.future);
  final eventRepo = await ref.watch(eventRepositoryProvider.future);
  return SaveCardUseCase(
    cardRepository: cardRepo,
    tagRepository: tagRepo,
    eventRepository: eventRepo,
  );
});

final searchCardsUseCaseProvider = FutureProvider<SearchCardsUseCase>((ref) async {
  final repo = await ref.watch(searchRepositoryProvider.future);
  return SearchCardsUseCase(repo);
});

final updateCardUseCaseProvider = FutureProvider<UpdateCardUseCase>((ref) async {
  final cardRepo = await ref.watch(cardRepositoryProvider.future);
  final tagRepo = await ref.watch(tagRepositoryProvider.future);
  final eventRepo = await ref.watch(eventRepositoryProvider.future);
  return UpdateCardUseCase(
    cardRepository: cardRepo,
    tagRepository: tagRepo,
    eventRepository: eventRepo,
    storage: ref.watch(storageServiceProvider),
  );
});

final deleteCardUseCaseProvider =
    FutureProvider<DeleteCardUseCase>((ref) async {
  final cardRepo = await ref.watch(cardRepositoryProvider.future);
  return DeleteCardUseCase(
    cardRepo: cardRepo,
    storage: ref.watch(storageServiceProvider),
  );
});

// ─── Home view mode (UI-facing) ──────────────────────────────────────────────

/// Display mode for the home card list.
enum HomeViewMode { list, gallery }

/// Persisted in-memory only — F4 agent will wire SharedPreferences.  Defaults
/// to [HomeViewMode.list].
final homeViewModeProvider = StateProvider<HomeViewMode>(
  (_) => HomeViewMode.list,
);

// ─── Search filter state (UI-facing) ────────────────────────────────────────

/// Holds the user's currently active search filters (selected event IDs and
/// tag IDs).  Lives at the screen level via [autoDispose] so it resets when
/// the search screen is popped.
final searchFiltersProvider =
    StateProvider.autoDispose<SearchFilters>((_) => const SearchFilters());

// ─── Tag list with counts (UI-facing) ───────────────────────────────────────

/// Tag list with per-tag card counts, used by the tag management screen.
/// autoDispose so state is fresh each time the screen mounts; callers
/// invalidate this provider after add/delete to trigger a reload.
final tagListWithCountsProvider =
    FutureProvider.autoDispose<List<TagWithCount>>((ref) async {
  final repo = await ref.watch(tagRepositoryProvider.future);
  return repo.findAllWithCounts();
});

// ─── Card list (UI-facing) ───────────────────────────────────────────────────

/// Card list shown on the home screen.  Not autoDispose: the home screen is
/// kept alive by RootShell's IndexedStack, and we want predictable invalidation
/// after every save instead of relying on listener-count timing.
final cardListProvider = FutureProvider<List<BusinessCard>>((ref) async {
  final repo = await ref.watch(cardRepositoryProvider.future);
  return repo.findAll(sortBy: CardSortBy.createdAt);
});

// ─── Card by ID (UI-facing) ──────────────────────────────────────────────────

/// Fetches a single [BusinessCard] by ID.  autoDispose so the cache is released
/// once the detail screen is popped.  Callers invalidate this after a successful
/// edit to force a fresh load on re-entry.
final cardByIdProvider =
    FutureProvider.autoDispose.family<BusinessCard?, String>((ref, id) async {
  final repo = await ref.watch(cardRepositoryProvider.future);
  return repo.findById(id);
});

// ─── Event list (UI-facing) ──────────────────────────────────────────────────

/// Event list for the event list screen.  Not autoDispose so callers can
/// call `ref.invalidate(eventListProvider)` after create / update / delete and
/// the next watch rebuilds with fresh data regardless of listener count.
final eventListProvider = FutureProvider<List<Event>>((ref) async {
  final repo = await ref.watch(eventRepositoryProvider.future);
  return repo.findAll();
});

// ─── My card (UI-facing) ─────────────────────────────────────────────────────

/// The user's own profile card.  Resolves to null when none is set.
///
/// Not autoDispose — SettingsScreen invalidates this after set/clear so that
/// the next watch rebuilds regardless of listener count.
final myCardProvider = FutureProvider<BusinessCard?>((ref) async {
  final repo = await ref.watch(cardRepositoryProvider.future);
  return repo.findMyCard();
});

// ─── App preferences (theme / accent) ───────────────────────────────────────

final appPreferencesProvider = Provider<AppPreferences>(
  (_) => AppPreferencesImpl(),
);

// ─── Theme mode notifier ─────────────────────────────────────────────────────

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(ThemeMode.system) {
    _load();
  }

  final AppPreferences _prefs;

  Future<void> _load() async {
    final saved = await _prefs.getThemeMode();
    if (mounted) state = saved;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setThemeMode(mode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(appPreferencesProvider));
});

// ─── Accent color index notifier ─────────────────────────────────────────────

class AccentColorNotifier extends StateNotifier<int> {
  AccentColorNotifier(this._prefs) : super(0) {
    _load();
  }

  final AppPreferences _prefs;

  Future<void> _load() async {
    final saved = await _prefs.getAccentColorIndex();
    if (mounted) state = saved;
  }

  Future<void> setIndex(int index) async {
    state = index;
    await _prefs.setAccentColorIndex(index);
  }
}

final accentColorIndexProvider =
    StateNotifierProvider<AccentColorNotifier, int>((ref) {
  return AccentColorNotifier(ref.watch(appPreferencesProvider));
});
