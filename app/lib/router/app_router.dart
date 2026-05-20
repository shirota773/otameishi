import 'package:flutter/material.dart';

import '../screens/capture_review_screen.dart';
import '../screens/capture_screen.dart';
import '../screens/card_detail_screen.dart';
import '../screens/card_edit_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/event_edit_screen.dart';
import '../screens/root_shell.dart';
import '../screens/search_screen.dart';
import '../screens/tag_list_screen.dart';
import '../services/service_models.dart';

/// Arguments for the `/capture/review` route.
///
/// Wraps [CardDraft] and the optional [isMyCard] flag so callers can set
/// both without mutating the draft.
class CaptureReviewArgs {
  const CaptureReviewArgs({required this.draft, this.isMyCard = false});

  final CardDraft draft;
  final bool isMyCard;
}

/// Centralized route table.  Kept as classic Navigator routes (rather than
/// go_router) because the app's navigation is small and largely linear.
class AppRoutes {
  static Map<String, WidgetBuilder> table() => {
        '/': (_) => const RootShell(),
        '/capture': (_) => const CaptureScreen(),
        '/search': (_) => const SearchScreen(),
        '/tags': (_) => const TagListScreen(),
      };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/card':
        final id = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => CardDetailScreen(cardId: id),
          settings: settings,
        );
      case '/event':
        final id = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: id),
          settings: settings,
        );
      case '/card/edit':
        final cardId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => CardEditScreen(cardId: cardId),
          settings: settings,
        );
      case '/event/edit':
        final eventId = settings.arguments as String?;
        return MaterialPageRoute(
          builder: (_) => EventEditScreen(eventId: eventId),
          settings: settings,
        );
      case '/capture/review':
        // Accepts either a raw CardDraft (backward compat) or CaptureReviewArgs.
        final args = settings.arguments;
        final CardDraft draft;
        final bool isMyCard;
        if (args is CaptureReviewArgs) {
          draft = args.draft;
          isMyCard = args.isMyCard;
        } else {
          draft = args as CardDraft;
          isMyCard = false;
        }
        return MaterialPageRoute(
          builder: (_) => CaptureReviewScreen(draft: draft, isMyCard: isMyCard),
          settings: settings,
        );
      default:
        return null;
    }
  }
}
