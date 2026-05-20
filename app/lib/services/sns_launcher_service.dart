import 'package:url_launcher/url_launcher.dart';

import 'service_models.dart';

/// Pure classifier for an SNS URL string.  Pulled out of the service so
/// it can be unit-tested without touching url_launcher.
SnsKind classifySnsUrl(String url) {
  final lower = url.trim().toLowerCase();

  // Reject obvious non-URL inputs.
  if (lower.isEmpty || !(lower.startsWith('http://') || lower.startsWith('https://'))) {
    return SnsKind.web;
  }

  final uri = Uri.tryParse(lower);
  if (uri == null) return SnsKind.web;
  final host = uri.host;

  if (host == 'x.com' || host == 'www.x.com' ||
      host == 'twitter.com' || host == 'www.twitter.com' ||
      host == 'mobile.twitter.com') {
    return SnsKind.x;
  }
  if (host == 'instagram.com' || host == 'www.instagram.com') {
    return SnsKind.instagram;
  }
  if (host == 'discord.gg' || host == 'discord.com' ||
      host == 'www.discord.com') {
    return SnsKind.discord;
  }
  return SnsKind.web;
}

/// Launches outbound SNS / web URLs via the OS.
abstract interface class SnsLauncherService {
  SnsKind classify(String url);

  /// Returns true if the launch was attempted successfully.
  Future<bool> launch(String url);
}

class SnsLauncherServiceImpl implements SnsLauncherService {
  const SnsLauncherServiceImpl();

  @override
  SnsKind classify(String url) => classifySnsUrl(url);

  @override
  Future<bool> launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    // Allow-list schemes: only HTTP(S) URLs are safe to launch.  Other schemes
    // (javascript:, file:, intent:, etc.) could trigger unintended behavior on
    // the OS if a malicious card image yielded a stored payload like that.
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
